import AppKit
import VibePetCore

/// App-side glue around the Core `HookInstaller`: resolves the bundled `VibePetHooks`
/// source, publishes per-tool detection/status rows, and surfaces install failures
/// via `ErrorPresenter`. Used by both the settings page and onboarding step ③.
@MainActor
final class HookInstallCoordinator: ObservableObject {
    @Published private(set) var rows: [ToolInstallStatus] = []
    @Published private(set) var health: [HookHealthReport] = []
    @Published var lastError: PresentedError?

    private let installer: HookInstaller
    private let hookBinarySource: URL

    init(
        installer: HookInstaller = HookInstallCoordinator.defaultInstaller(),
        hookBinarySource: URL = HookInstallCoordinator.bundledHookBinary()
    ) {
        self.installer = installer
        self.hookBinarySource = hookBinarySource
        refresh()
    }

    func refresh() {
        rows = installer.toolStatuses()
        health = installer.healthReports()
    }

    /// The diagnosis for a tool, or nil if it has no reported issues.
    func healthReport(for tool: ToolKind) -> HookHealthReport? {
        health.first { $0.tool == tool && !$0.issues.isEmpty }
    }

    /// Whether any *detected* tool has a one-click-repairable drift. Drives the
    /// onboarding hint that nudges the user to repair a pre-existing broken install.
    func hasRepairableDriftAmongDetected() -> Bool {
        let detected = Set(rows.filter(\.detected).map(\.tool))
        return health.contains { detected.contains($0.tool) && !$0.repairableIssues.isEmpty }
    }

    func install(_ tool: ToolKind) {
        do {
            _ = try installer.install(tool: tool, hookBinarySource: hookBinarySource)
            lastError = nil
        } catch {
            lastError = ErrorPresenter.presentInstallFailure(error, tool: tool)
        }
        refresh()
    }

    /// Re-establishes consistent on-disk state for a drifted install (forces a config
    /// rewrite, unlike the idempotent `install`).
    func repair(_ tool: ToolKind) {
        do {
            _ = try installer.repair(tool: tool, hookBinarySource: hookBinarySource)
            lastError = nil
        } catch {
            lastError = ErrorPresenter.presentInstallFailure(error, tool: tool)
        }
        refresh()
    }

    func uninstall(_ tool: ToolKind) {
        do {
            try installer.uninstall(tool: tool)
            lastError = nil
        } catch {
            lastError = ErrorPresenter.presentInstallFailure(error, tool: tool)
        }
        refresh()
    }

    /// A status notice for a row (e.g. Codex `/hooks` trust guidance), or nil.
    func notice(for row: ToolInstallStatus) -> PresentedError? {
        ErrorPresenter.present(installStatus: row.status, tool: row.tool)
    }

    static func defaultInstaller() -> HookInstaller {
        let binaryPath = InstallPaths.hookBinaryURL().path
        return HookInstaller(writers: [
            ClaudeCodeConfigWriter(hookBinaryPath: binaryPath),
            CodexConfigWriter(hookBinaryPath: binaryPath),
        ])
    }

    /// The `VibePetHooks` shipped next to this executable (dev build or app bundle).
    /// Uses `HooksBinaryLocator` to also cover sibling `Helpers/` and dev `.build`
    /// layouts, falling back to the executable-adjacent path when nothing resolves.
    static func bundledHookBinary() -> URL {
        let executableDirectory = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        return HooksBinaryLocator.locate(executableDirectory: executableDirectory)
            ?? executableDirectory.appendingPathComponent("VibePetHooks", isDirectory: false)
    }
}

extension ToolKind {
    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }
}

extension InstallStatus {
    var label: String { localizedLabel(AppLocalizer(language: .simplifiedChinese)) }

    func localizedLabel(_ localizer: AppLocalizer) -> String {
        switch self {
        case .notInstalled: localizer.text(.statusNotInstalled)
        case .installedNeedsTrust: localizer.text(.statusInstalledNeedsTrust)
        case .enabled: localizer.text(.statusEnabled)
        case .outdated: localizer.text(.statusOutdated)
        }
    }
}

extension HookHealthReport.Issue {
    /// User-facing Chinese summary for compatibility with existing settings tests.
    var zhLabel: String { localizedLabel(AppLocalizer(language: .simplifiedChinese)) }

    func localizedLabel(_ localizer: AppLocalizer) -> String {
        switch self {
        case .binaryNotFound:
            return localizer.text(.hookProgramMissing)
        case .binaryNotExecutable:
            return localizer.text(.hookProgramNotExecutable)
        case .configMalformedJSON:
            return localizer.text(.hookConfigJSONBroken)
        case .staleCommandPath:
            return localizer.text(.hookConfiguredPathInvalid)
        case .managedHooksMissing:
            return localizer.text(.hookEntryMissing)
        case .orphanedInstall:
            return localizer.text(.hookManifestMissing)
        case .codexFeatureDisabled:
            return localizer.text(.codexHooksFeatureDisabled)
        case .otherHooksDetected(let names):
            let joined = names.joined(separator: localizer.language == .simplifiedChinese ? "、" : ", ")
            return localizer.text(.hookCoexistenceDetected, joined)
        }
    }
}

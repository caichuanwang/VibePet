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
    private let hookBinaryLocation: HooksBinaryLocation

    init(
        installer: HookInstaller = HookInstallCoordinator.defaultInstaller(),
        hookBinarySource: URL? = nil,
        hookBinaryLocation: HooksBinaryLocation? = nil
    ) {
        self.installer = installer
        self.hookBinaryLocation = hookBinarySource.map(HooksBinaryLocation.found)
            ?? hookBinaryLocation
            ?? HookInstallCoordinator.bundledHookBinaryLocation()
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
        guard let hookBinarySource = resolveHookBinarySource(for: tool) else { return }
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
        guard let hookBinarySource = resolveHookBinarySource(for: tool) else { return }
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

    private func resolveHookBinarySource(for tool: ToolKind) -> URL? {
        switch hookBinaryLocation {
        case .found(let url):
            return url
        case .invalidExplicitOverride(let url):
            lastError = ErrorPresenter.presentInstallFailure(
                HookBinarySourceError.invalidExplicitOverride(url),
                tool: tool
            )
        case .notFound(let attempted):
            lastError = ErrorPresenter.presentInstallFailure(
                HookBinarySourceError.notFound(attempted),
                tool: tool
            )
        }
        return nil
    }

    /// Resolves the checked `VibePetHooks` source next to this executable (dev build
    /// or app bundle). Invalid explicit overrides remain errors and never fall back.
    static func bundledHookBinaryLocation() -> HooksBinaryLocation {
        let executableDirectory = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        return HooksBinaryLocator.locateResult(executableDirectory: executableDirectory)
    }
}

private enum HookBinarySourceError: LocalizedError {
    case invalidExplicitOverride(URL)
    case notFound([URL])

    var errorDescription: String? {
        switch self {
        case .invalidExplicitOverride(let url):
            "\(HooksBinaryLocator.environmentKey) is not an executable regular file: \(url.path)"
        case .notFound(let attempted):
            "VibePetHooks was not found; attempted: \(attempted.map(\.path).joined(separator: ", "))"
        }
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
        case .configMalformedJSON, .configMalformedTOML:
            return localizer.text(.hookConfigJSONBroken)
        case .manifestMalformed, .manifestSettingsPathMismatch, .manifestHookSetMismatch:
            return localizer.text(.hookManifestMissing)
        case .staleCommandPath:
            return localizer.text(.hookConfiguredPathInvalid)
        case .managedHooksMissing, .managedHookKeyMissing, .codexToolArgumentMissing:
            return localizer.text(.hookEntryMissing)
        case .binaryVersionMismatch:
            return localizer.text(.hookConfiguredPathInvalid)
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

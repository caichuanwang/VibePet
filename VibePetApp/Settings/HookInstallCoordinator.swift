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
    var label: String {
        switch self {
        case .notInstalled: "未安装"
        case .installedNeedsTrust: "已写入，待信任"
        case .enabled: "已启用"
        case .outdated: "版本落后"
        }
    }
}

extension HookHealthReport.Issue {
    /// User-facing Chinese summary for the settings page (Core's `description` stays
    /// technical English for the CLI/logs).
    var zhLabel: String {
        switch self {
        case .binaryNotFound:
            "Hook 程序缺失"
        case .binaryNotExecutable:
            "Hook 程序无法执行"
        case .configMalformedJSON:
            "配置文件 JSON 损坏（需手动修复）"
        case .staleCommandPath:
            "配置指向的程序路径已失效"
        case .managedHooksMissing:
            "配置中缺少 VibePet 的 hook 条目"
        case .orphanedInstall:
            "配置残留 VibePet hook，但安装记录已丢失"
        case .codexFeatureDisabled:
            "Codex [features] hooks 开关被关闭"
        case .otherHooksDetected(let names):
            "检测到其它 hook 共存：\(names.joined(separator: "、"))"
        }
    }
}

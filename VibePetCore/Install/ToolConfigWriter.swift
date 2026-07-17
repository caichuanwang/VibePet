import Foundation

/// Injects/removes VibePet's hook entries in a tool's configuration file, touching
/// only its own entries and preserving everything the user wrote (technical design
/// §4.3). `HookInstaller` orchestrates backup + manifest around these calls.
public protocol ToolConfigWriter: Sendable {
    var tool: ToolKind { get }
    /// The tool config file VibePet edits (e.g. `~/.claude/settings.json`).
    var configURL: URL { get }
    /// The hook keys VibePet manages, recorded in the manifest's `writtenHooks`.
    var managedHookKeys: [String] { get }

    /// All files this writer mutates and that must be backed up before writing.
    /// Defaults to `[configURL]`; Codex overrides to include its `hooks.json`.
    var managedFiles: [URL] { get }

    func configExists() -> Bool

    /// Injects VibePet's hook entries (command = stable binary path + `arguments`),
    /// idempotently. Existing user entries are preserved.
    func install(arguments: [String]) throws

    /// Removes only VibePet's entries, preserving user entries.
    func uninstall() throws

    /// Installs while returning tool-specific state that uninstall needs to avoid
    /// reverting settings VibePet did not own.
    func installWithReceipt(arguments: [String]) throws -> ToolConfigInstallReceipt

    /// Removes managed entries using the first-install receipt from the manifest.
    func uninstall(receipt: ToolConfigInstallReceipt) throws
}

public enum ToolConfigInstallReceipt: Equatable, Sendable {
    case none
    case codexFeature(CodexFeatureStateBeforeInstall)
}

public enum ToolConfigMutationError: Error, Equatable, Sendable {
    case malformedJSON(path: String)
    case malformedTOML(path: String)
    case unreadable(path: String)
}

public enum SetupToolSelector {
    public static func tools(for argument: String?) -> [ToolKind]? {
        switch argument {
        case nil, "all": [.claudeCode, .codex]
        case "claude", "claudeCode": [.claudeCode]
        case "codex": [.codex]
        default: nil
        }
    }
}

public extension ToolConfigWriter {
    var managedFiles: [URL] { [configURL] }

    func configExists() -> Bool {
        FileManager.default.fileExists(atPath: configURL.path)
    }

    /// Whether the tool appears installed on this machine — its config file or its
    /// containing directory (e.g. `~/.claude`, `~/.codex`) exists. Used to list only
    /// detected tools in onboarding/settings.
    func toolDetected() -> Bool {
        if configExists() { return true }
        var isDirectory: ObjCBool = false
        let parent = configURL.deletingLastPathComponent().path
        return FileManager.default.fileExists(atPath: parent, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func installWithReceipt(arguments: [String]) throws -> ToolConfigInstallReceipt {
        try install(arguments: arguments)
        return .none
    }

    func uninstall(receipt: ToolConfigInstallReceipt) throws {
        try uninstall()
    }
}

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
}

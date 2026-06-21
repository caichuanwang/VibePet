import Foundation

/// Tracks, per tool, exactly what VibePet wrote — so uninstall removes only its own
/// entries and install can detect "already done" (technical design §4.3). Persisted
/// as `install-manifest.json` under the support directory.
public struct InstallManifest: Codable, Equatable, Sendable {
    public var version: Int
    /// Version of the installed `bin/VibePetHooks`; re-copied when behind.
    public var hookBinaryVersion: String?
    /// Keyed by `ToolKind.rawValue` ("claudeCode" / "codex").
    public var tools: [String: ToolInstallRecord]

    public init(version: Int = 1, hookBinaryVersion: String? = nil, tools: [String: ToolInstallRecord] = [:]) {
        self.version = version
        self.hookBinaryVersion = hookBinaryVersion
        self.tools = tools
    }
}

public struct ToolInstallRecord: Codable, Equatable, Sendable {
    public var installed: Bool
    public var activationState: ActivationState
    public var settingsPath: String?
    /// Only the hook keys VibePet wrote (e.g. `["PreToolUse","Stop","Notification"]`).
    public var writtenHooks: [String]
    public var backupPath: String?

    public init(
        installed: Bool,
        activationState: ActivationState,
        settingsPath: String?,
        writtenHooks: [String],
        backupPath: String?
    ) {
        self.installed = installed
        self.activationState = activationState
        self.settingsPath = settingsPath
        self.writtenHooks = writtenHooks
        self.backupPath = backupPath
    }
}

/// Whether a written tool hook is actually live. Codex command hooks may require the
/// user to trust them in `/hooks` before they run, so "written" ≠ "active"
/// (technical design §4.2). Claude Code has no trust gate → active once written.
public enum ActivationState: String, Codable, Equatable, Sendable {
    case notInstalled
    case installedNeedsTrust
    case trustedActive
}

/// Reads/writes the manifest JSON, returning an empty default when absent.
public struct InstallManifestStore: Sendable {
    private let applicationSupportRoot: URL?

    public init(applicationSupportRoot: URL? = nil) {
        self.applicationSupportRoot = applicationSupportRoot
    }

    public var manifestURL: URL {
        InstallPaths.manifestURL(applicationSupportRoot: applicationSupportRoot)
    }

    public func read() -> InstallManifest {
        guard
            let data = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONDecoder().decode(InstallManifest.self, from: data)
        else {
            return InstallManifest()
        }
        return manifest
    }

    public func write(_ manifest: InstallManifest) throws {
        try SupportDirectory.ensure(applicationSupportRoot: applicationSupportRoot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    }

    /// Promotes an installed-but-untrusted tool to `trustedActive` — the runtime
    /// evidence that the user trusted VibePet's hooks (e.g. the App received a real
    /// Codex hook event). Idempotent; returns whether it changed state. A no-op for a
    /// tool that is not installed or is already active (technical design §4.2 / M6-5a).
    @discardableResult
    public func markTrustedActive(tool: ToolKind) -> Bool {
        var manifest = read()
        guard
            var record = manifest.tools[tool.rawValue],
            record.installed,
            record.activationState == .installedNeedsTrust
        else {
            return false
        }
        record.activationState = .trustedActive
        manifest.tools[tool.rawValue] = record
        try? write(manifest)
        return true
    }
}

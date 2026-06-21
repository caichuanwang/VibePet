import Foundation

/// Per-tool installation state reported to the CLI and settings page (technical
/// design §4.3 `status`).
public enum InstallStatus: Equatable, Sendable {
    case notInstalled
    /// Written but not yet live — Codex awaiting `/hooks` trust.
    case installedNeedsTrust
    /// Live (Claude once written; Codex once a real event proved it active).
    case enabled
    /// Installed but the binary is behind the current version.
    case outdated
}

/// A tool's detection + install status, for the settings page and onboarding step ③.
public struct ToolInstallStatus: Equatable, Sendable {
    public let tool: ToolKind
    public let detected: Bool
    public let status: InstallStatus

    public init(tool: ToolKind, detected: Bool, status: InstallStatus) {
        self.tool = tool
        self.detected = detected
        self.status = status
    }
}

/// Orchestrates install / uninstall / status for each tool, driven by the manifest
/// (technical design §4.3). Install is idempotent (skips when already installed at
/// the current binary version), backs up the original config before writing, and
/// records exactly what it wrote so uninstall is precise and reversible.
public struct HookInstaller: Sendable {
    private let applicationSupportRoot: URL?
    private let store: InstallManifestStore
    private let binaryInstaller: BinaryInstaller
    private let writers: [ToolKind: any ToolConfigWriter]
    private let currentBinaryVersion: String

    public init(
        applicationSupportRoot: URL? = nil,
        writers: [any ToolConfigWriter],
        currentBinaryVersion: String = VibePetCore.hookBinaryVersion
    ) {
        self.applicationSupportRoot = applicationSupportRoot
        self.store = InstallManifestStore(applicationSupportRoot: applicationSupportRoot)
        self.binaryInstaller = BinaryInstaller(applicationSupportRoot: applicationSupportRoot)
        self.writers = Dictionary(uniqueKeysWithValues: writers.map { ($0.tool, $0) })
        self.currentBinaryVersion = currentBinaryVersion
    }

    @discardableResult
    public func install(tool: ToolKind, hookBinarySource: URL) throws -> ToolInstallRecord {
        guard let writer = writers[tool] else {
            throw InstallError.noWriter(tool)
        }

        var manifest = store.read()
        // Copy/upgrade the shared binary (no-op if present and current).
        try binaryInstaller.install(
            from: hookBinarySource,
            version: currentBinaryVersion,
            installedVersion: manifest.hookBinaryVersion
        )
        manifest.hookBinaryVersion = currentBinaryVersion

        // Idempotent: already installed → only persist a possible binary version bump.
        if let existing = manifest.tools[tool.rawValue], existing.installed {
            try store.write(manifest)
            return existing
        }

        let backupPath = try backUpIfPresent(writer)
        try writer.install(arguments: Self.arguments(for: tool))

        let record = ToolInstallRecord(
            installed: true,
            activationState: Self.defaultActivation(for: tool),
            settingsPath: writer.configURL.path,
            writtenHooks: writer.managedHookKeys,
            backupPath: backupPath
        )
        manifest.tools[tool.rawValue] = record
        try store.write(manifest)
        return record
    }

    public func uninstall(tool: ToolKind) throws {
        guard let writer = writers[tool] else { return }
        var manifest = store.read()
        guard manifest.tools[tool.rawValue] != nil else { return }

        try writer.uninstall()
        manifest.tools.removeValue(forKey: tool.rawValue)

        // Drop the shared binary once no tool references it.
        if manifest.tools.values.allSatisfy({ !$0.installed }) {
            try? FileManager.default.removeItem(at: binaryInstaller.binaryURL)
            manifest.hookBinaryVersion = nil
        }
        try store.write(manifest)
    }

    /// Forces a config rewrite to clear the drift `HookHealthCheck` reports (moved
    /// binary, hand-edited JSON, removed hook, disabled Codex flag, orphaned install).
    /// Unlike `install`, it does not short-circuit when the manifest says "installed",
    /// since the whole point is that the on-disk state no longer matches the manifest.
    /// A prior activation state is preserved so a trusted Codex isn't pushed back to
    /// "needs trust" by a repair.
    @discardableResult
    public func repair(tool: ToolKind, hookBinarySource: URL) throws -> ToolInstallRecord {
        guard let writer = writers[tool] else {
            throw InstallError.noWriter(tool)
        }

        var manifest = store.read()
        // Re-copy the binary if missing/behind/changed, then rewrite the config.
        try binaryInstaller.install(
            from: hookBinarySource,
            version: currentBinaryVersion,
            installedVersion: manifest.hookBinaryVersion
        )
        manifest.hookBinaryVersion = currentBinaryVersion

        // No fresh backup: the first install already preserved the user's pristine
        // config, and the on-disk file now carries VibePet's own entries. Re-rewrite
        // it and keep the original backup reference.
        try writer.install(arguments: Self.arguments(for: tool))

        let previous = manifest.tools[tool.rawValue]
        let record = ToolInstallRecord(
            installed: true,
            activationState: previous?.activationState ?? Self.defaultActivation(for: tool),
            settingsPath: writer.configURL.path,
            writtenHooks: writer.managedHookKeys,
            backupPath: previous?.backupPath
        )
        manifest.tools[tool.rawValue] = record
        try store.write(manifest)
        return record
    }

    /// Per-tool detection + status for the settings page and onboarding step ③,
    /// in stable order (Claude Code, then Codex). Only tools this installer has a
    /// writer for are included.
    public func toolStatuses() -> [ToolInstallStatus] {
        [ToolKind.claudeCode, .codex].compactMap { tool in
            guard let writer = writers[tool] else { return nil }
            return ToolInstallStatus(tool: tool, detected: writer.toolDetected(), status: status(tool: tool))
        }
    }

    /// Deep health reports for every managed tool, in stable order. Composes the
    /// manifest status with `HookHealthCheck`'s config-drift diagnosis. Backs both the
    /// `VibePetSetup doctor` CLI and the settings page diagnostics.
    public func healthReports() -> [HookHealthReport] {
        [ToolKind.claudeCode, .codex].compactMap { health(tool: $0) }
    }

    public func health(tool: ToolKind) -> HookHealthReport? {
        guard let writer = writers[tool] else { return nil }
        return HookHealthCheck.check(
            tool: tool,
            writer: writer,
            managedBinaryURL: binaryInstaller.binaryURL,
            recordedInstalled: status(tool: tool) != .notInstalled
        )
    }

    public func status(tool: ToolKind) -> InstallStatus {
        let manifest = store.read()
        guard let record = manifest.tools[tool.rawValue], record.installed else {
            return .notInstalled
        }
        if manifest.hookBinaryVersion != currentBinaryVersion {
            return .outdated
        }
        switch record.activationState {
        case .trustedActive:
            return .enabled
        case .installedNeedsTrust:
            return .installedNeedsTrust
        case .notInstalled:
            return .notInstalled
        }
    }

    // MARK: - Helpers

    public enum InstallError: Error, Equatable, Sendable {
        case noWriter(ToolKind)
    }

    /// Codex's hook command is tagged so the CLI selects `CodexAdapter`.
    static func arguments(for tool: ToolKind) -> [String] {
        switch tool {
        case .claudeCode: []
        case .codex: ["--tool", "codex"]
        }
    }

    /// Claude has no trust gate; Codex must be trusted in `/hooks` before it runs.
    static func defaultActivation(for tool: ToolKind) -> ActivationState {
        switch tool {
        case .claudeCode: .trustedActive
        case .codex: .installedNeedsTrust
        }
    }

    /// Copies every existing managed file into `backups/` before writing, returning
    /// the primary (`configURL`) backup path (nil when there was nothing to back up).
    private func backUpIfPresent(_ writer: any ToolConfigWriter) throws -> String? {
        let backupsDir = InstallPaths.backupsDirectory(applicationSupportRoot: applicationSupportRoot)
        let stamp = Self.timestampFormatter.string(from: Date())
        var primaryBackupPath: String?

        for file in writer.managedFiles where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
            let name = "\(writer.tool.rawValue)-\(file.lastPathComponent).\(stamp).bak"
            let backupURL = backupsDir.appendingPathComponent(name, isDirectory: false)
            try FileManager.default.copyItem(at: file, to: backupURL)
            if file == writer.configURL {
                primaryBackupPath = backupURL.path
            }
        }
        return primaryBackupPath
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter
    }()
}

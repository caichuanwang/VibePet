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
/// (technical design §4.3). Install reconciles only VibePet-managed entries, backs
/// up the original config before first write, and records exactly what it wrote so
/// uninstall is precise and reversible.
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
        try reconcile(
            tool: tool,
            hookBinarySource: hookBinarySource,
            refreshUnknownCodexOwnership: false
        )
    }

    public func uninstall(tool: ToolKind) throws {
        guard let writer = writers[tool] else { return }
        var manifest = try store.readStrict()
        guard manifest.tools[tool.rawValue] != nil else { return }

        let record = manifest.tools[tool.rawValue]
        let receipt: ToolConfigInstallReceipt
        if tool == .codex {
            receipt = .codexFeature(record?.codexFeatureStateBeforeInstall ?? .unknown)
        } else {
            receipt = .none
        }
        try writer.uninstall(receipt: receipt)
        manifest.tools.removeValue(forKey: tool.rawValue)

        // Drop the shared binary once no tool references it.
        if manifest.tools.values.allSatisfy({ !$0.installed }) {
            try? FileManager.default.removeItem(at: binaryInstaller.binaryURL)
            manifest.hookBinaryVersion = nil
        }
        try store.write(manifest)
    }

    /// Repair and install share the same reconciliation path. Both rewrite managed
    /// config from current disk state while preserving the first pristine backup.
    @discardableResult
    public func repair(tool: ToolKind, hookBinarySource: URL) throws -> ToolInstallRecord {
        try reconcile(
            tool: tool,
            hookBinarySource: hookBinarySource,
            refreshUnknownCodexOwnership: true
        )
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
        let manifest: InstallManifest
        let malformedManifestPath: String?
        do {
            manifest = try store.readStrict()
            malformedManifestPath = nil
        } catch {
            manifest = InstallManifest()
            malformedManifestPath = store.manifestURL.path
        }
        let record = manifest.tools[tool.rawValue]
        return HookHealthCheck.check(
            tool: tool,
            writer: writer,
            managedBinaryURL: binaryInstaller.binaryURL,
            recordedInstalled: record?.installed == true,
            recordedRecord: record,
            recordedBinaryVersion: manifest.hookBinaryVersion,
            expectedBinaryVersion: currentBinaryVersion,
            manifestMalformedPath: malformedManifestPath
        )
    }

    public func status(tool: ToolKind) -> InstallStatus {
        let manifest = store.read()
        guard let record = manifest.tools[tool.rawValue], record.installed else {
            return .notInstalled
        }
        guard let writer = writers[tool] else {
            return .notInstalled
        }
        if manifest.hookBinaryVersion != currentBinaryVersion
            || Set(record.writtenHooks) != Set(writer.managedHookKeys) {
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

    private func reconcile(
        tool: ToolKind,
        hookBinarySource: URL,
        refreshUnknownCodexOwnership: Bool
    ) throws -> ToolInstallRecord {
        guard let writer = writers[tool] else {
            throw InstallError.noWriter(tool)
        }

        var manifest = try store.readStrict()
        let previous = manifest.tools[tool.rawValue]
        try binaryInstaller.install(
            from: hookBinarySource,
            version: currentBinaryVersion,
            installedVersion: manifest.hookBinaryVersion
        )
        manifest.hookBinaryVersion = currentBinaryVersion

        let backupPath: String?
        if let previous {
            // A nil first-install backup is meaningful: there was no pristine user
            // config. Never back up VibePet's own generated config on a later install.
            backupPath = previous.backupPath
        } else {
            backupPath = try backUpIfPresent(writer)
        }
        let receipt = try writer.installWithReceipt(arguments: Self.arguments(for: tool))
        let observedCodexFeatureState: CodexFeatureStateBeforeInstall
        if case let .codexFeature(state) = receipt {
            observedCodexFeatureState = state
        } else {
            observedCodexFeatureState = .unknown
        }
        let codexFeatureState: CodexFeatureStateBeforeInstall
        if let previous,
           !(refreshUnknownCodexOwnership && previous.codexFeatureStateBeforeInstall == .unknown) {
            // Never reinterpret a legacy unknown receipt after VibePet may already have
            // enabled the feature during ordinary install. Explicit repair is the only
            // operation allowed to establish a new conservative ownership baseline.
            codexFeatureState = previous.codexFeatureStateBeforeInstall
        } else {
            codexFeatureState = observedCodexFeatureState
        }

        let record = ToolInstallRecord(
            installed: true,
            activationState: previous?.activationState ?? Self.defaultActivation(for: tool),
            settingsPath: writer.configURL.path,
            writtenHooks: writer.managedHookKeys,
            backupPath: backupPath,
            codexFeatureStateBeforeInstall: codexFeatureState
        )
        manifest.tools[tool.rawValue] = record
        try store.write(manifest)
        return record
    }

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

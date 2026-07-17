import Foundation

public struct HookHealthReport: Equatable, Sendable {
    public enum Severity: Equatable, Sendable {
        case error
        case info
    }

    public enum Issue: Equatable, Sendable, CustomStringConvertible {
        case binaryNotFound(path: String)
        case binaryNotExecutable(path: String)
        case binaryVersionMismatch(recorded: String?, expected: String)
        case configMalformedJSON(path: String)
        case configMalformedTOML(path: String)
        case manifestMalformed(path: String)
        case manifestSettingsPathMismatch(recorded: String?, expected: String)
        case manifestHookSetMismatch(recorded: [String], expected: [String])
        case staleCommandPath(recorded: String, configPath: String)
        case managedHooksMissing(configPath: String)
        case managedHookKeyMissing(key: String, configPath: String)
        case codexToolArgumentMissing(configPath: String)
        case orphanedInstall(configPath: String)
        case codexFeatureDisabled(configPath: String)
        case otherHooksDetected(names: [String])

        public var severity: Severity {
            switch self {
            case .otherHooksDetected: .info
            default: .error
            }
        }

        public var isAutoRepairable: Bool {
            switch self {
            case .binaryNotFound, .binaryNotExecutable, .binaryVersionMismatch,
                 .manifestSettingsPathMismatch, .manifestHookSetMismatch,
                 .staleCommandPath, .managedHooksMissing, .managedHookKeyMissing,
                 .codexToolArgumentMissing, .orphanedInstall, .codexFeatureDisabled:
                true
            case .configMalformedJSON, .configMalformedTOML, .manifestMalformed,
                 .otherHooksDetected:
                false
            }
        }

        public var description: String {
            switch self {
            case .binaryNotFound(let path):
                "Hook binary not found: \(path)"
            case .binaryNotExecutable(let path):
                "Hook binary is not executable: \(path)"
            case .binaryVersionMismatch(let recorded, let expected):
                "Hook binary version mismatch: recorded \(recorded ?? "missing"), expected \(expected)"
            case .configMalformedJSON(let path):
                "Config file is not valid JSON: \(path)"
            case .configMalformedTOML(let path):
                "Config file has unsafe TOML syntax: \(path)"
            case .manifestMalformed(let path):
                "Install manifest is not valid JSON: \(path)"
            case .manifestSettingsPathMismatch(let recorded, let expected):
                "Manifest settings path mismatch: recorded \(recorded ?? "missing"), expected \(expected)"
            case .manifestHookSetMismatch(let recorded, let expected):
                "Manifest hook set mismatch: recorded \(recorded.sorted()), expected \(expected.sorted())"
            case .staleCommandPath(let recorded, let configPath):
                "Command in \(configPath) points to \(recorded), not the managed binary"
            case .managedHooksMissing(let configPath):
                "VibePet hook entry is missing from \(configPath)"
            case .managedHookKeyMissing(let key, let configPath):
                "VibePet hook entry \(key) is missing from \(configPath)"
            case .codexToolArgumentMissing(let configPath):
                "Codex hook command in \(configPath) is missing --tool codex"
            case .orphanedInstall(let configPath):
                "Config references VibePet hooks but no install is recorded (orphaned): \(configPath)"
            case .codexFeatureDisabled(let configPath):
                "Codex [features] hooks flag is disabled in \(configPath)"
            case .otherHooksDetected(let names):
                "Other hooks also present: \(names.joined(separator: ", "))"
            }
        }
    }

    public let tool: ToolKind
    public let issues: [Issue]

    public init(tool: ToolKind, issues: [Issue]) {
        self.tool = tool
        self.issues = issues
    }

    public var isHealthy: Bool { errors.isEmpty }
    public var errors: [Issue] { issues.filter { $0.severity == .error } }
    public var notices: [Issue] { issues.filter { $0.severity == .info } }
    public var repairableIssues: [Issue] { issues.filter(\.isAutoRepairable) }
}

/// Read-only diagnosis. It never creates, repairs, or rewrites configuration files.
public enum HookHealthCheck {
    public static func check(
        tool: ToolKind,
        writer: any ToolConfigWriter,
        managedBinaryURL: URL,
        recordedInstalled: Bool,
        recordedRecord: ToolInstallRecord? = nil,
        recordedBinaryVersion: String? = nil,
        expectedBinaryVersion: String? = nil,
        manifestMalformedPath: String? = nil,
        fileManager: FileManager = .default
    ) -> HookHealthReport {
        var issues = manifestIssues(
            writer: writer,
            recordedInstalled: recordedInstalled,
            record: recordedRecord,
            recordedBinaryVersion: recordedBinaryVersion,
            expectedBinaryVersion: expectedBinaryVersion,
            manifestMalformedPath: manifestMalformedPath
        )
        let scan = scanJSONConfigs(
            tool: tool,
            writer: writer,
            expectedBinaryPath: managedBinaryURL.standardizedFileURL.path,
            fileManager: fileManager
        )
        issues.append(contentsOf: scan.issues)
        issues.append(contentsOf: recordedInstalled
            ? installedIssues(
                tool: tool,
                writer: writer,
                managedBinaryURL: managedBinaryURL,
                scan: scan,
                fileManager: fileManager
            )
            : orphanedIssues(writer: writer, scan: scan))
        if !scan.otherNames.isEmpty {
            issues.append(.otherHooksDetected(names: scan.otherNames.sorted()))
        }
        return HookHealthReport(tool: tool, issues: deduplicated(issues))
    }

    private struct ConfigScan {
        var validManagedKeys: Set<String> = []
        var foundAnyVibePetCommand = false
        var otherNames: Set<String> = []
        var isConclusive = true
        var issues: [HookHealthReport.Issue] = []
    }

    private static func manifestIssues(
        writer: any ToolConfigWriter,
        recordedInstalled: Bool,
        record: ToolInstallRecord?,
        recordedBinaryVersion: String?,
        expectedBinaryVersion: String?,
        manifestMalformedPath: String?
    ) -> [HookHealthReport.Issue] {
        var issues: [HookHealthReport.Issue] = []
        if let manifestMalformedPath { issues.append(.manifestMalformed(path: manifestMalformedPath)) }
        guard recordedInstalled else { return issues }
        if let record {
            if standardizedPath(record.settingsPath) != managedSettingsPath(writer.configURL) {
                issues.append(.manifestSettingsPathMismatch(
                    recorded: record.settingsPath,
                    expected: writer.configURL.standardizedFileURL.path
                ))
            }
            if Set(record.writtenHooks) != Set(writer.managedHookKeys) {
                issues.append(.manifestHookSetMismatch(recorded: record.writtenHooks, expected: writer.managedHookKeys))
            }
        }
        if let expectedBinaryVersion, recordedBinaryVersion != expectedBinaryVersion {
            issues.append(.binaryVersionMismatch(recorded: recordedBinaryVersion, expected: expectedBinaryVersion))
        }
        return issues
    }

    private static func scanJSONConfigs(
        tool: ToolKind,
        writer: any ToolConfigWriter,
        expectedBinaryPath: String,
        fileManager: FileManager
    ) -> ConfigScan {
        var scan = ConfigScan()
        for file in writer.managedFiles where file.pathExtension == "json" && fileManager.fileExists(atPath: file.path) {
            guard let data = try? Data(contentsOf: file),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                scan.issues.append(.configMalformedJSON(path: file.path))
                scan.isConclusive = false
                continue
            }
            guard (try? HookConfigurationJSON.validatedHooks(in: root, path: file.path)) != nil else {
                scan.issues.append(.configMalformedJSON(path: file.path))
                scan.isConclusive = false
                continue
            }
            for entry in hookCommandsByKey(in: root) {
                consume(entry, tool: tool, file: file, expectedBinaryPath: expectedBinaryPath, scan: &scan)
            }
        }
        return scan
    }

    private static func consume(
        _ entry: HookCommand,
        tool: ToolKind,
        file: URL,
        expectedBinaryPath: String,
        scan: inout ConfigScan
    ) {
        guard isVibePetCommand(entry.command),
              let recordedPath = HookCommandShell.firstArgument(in: entry.command) else {
            scan.otherNames.insert(commandName(from: entry.command))
            return
        }
        scan.foundAnyVibePetCommand = true
        guard URL(fileURLWithPath: recordedPath).standardizedFileURL.path == expectedBinaryPath else {
            scan.issues.append(.staleCommandPath(recorded: recordedPath, configPath: file.path))
            return
        }
        guard tool != .codex || hasCodexToolArgument(entry.command) else {
            scan.issues.append(.codexToolArgumentMissing(configPath: file.path))
            return
        }
        scan.validManagedKeys.insert(entry.key)
    }

    private static func installedIssues(
        tool: ToolKind,
        writer: any ToolConfigWriter,
        managedBinaryURL: URL,
        scan: ConfigScan,
        fileManager: FileManager
    ) -> [HookHealthReport.Issue] {
        var issues = binaryIssues(at: managedBinaryURL, fileManager: fileManager)
        let jsonFiles = writer.managedFiles.filter { $0.pathExtension == "json" }
        if scan.isConclusive {
            if scan.validManagedKeys.isEmpty, let hooksFile = jsonFiles.first {
                issues.append(.managedHooksMissing(configPath: hooksFile.path))
            }
            let configPath = jsonFiles.first?.path ?? writer.configURL.path
            issues += writer.managedHookKeys.compactMap { key in
                scan.validManagedKeys.contains(key) ? nil : .managedHookKeyMissing(key: key, configPath: configPath)
            }
        }
        if tool == .codex {
            issues += codexFeatureIssues(configURL: writer.configURL, fileManager: fileManager)
        }
        return issues
    }

    private static func binaryIssues(at url: URL, fileManager: FileManager) -> [HookHealthReport.Issue] {
        if !fileManager.fileExists(atPath: url.path) { return [.binaryNotFound(path: url.path)] }
        if !fileManager.isExecutableFile(atPath: url.path) { return [.binaryNotExecutable(path: url.path)] }
        return []
    }

    private static func codexFeatureIssues(configURL: URL, fileManager: FileManager) -> [HookHealthReport.Issue] {
        guard fileManager.fileExists(atPath: configURL.path) else {
            return [.codexFeatureDisabled(configPath: configURL.path)]
        }
        guard let toml = try? String(contentsOf: configURL, encoding: .utf8),
              CodexConfigWriter.featureSyntaxIsSafe(in: toml) else {
            return [.configMalformedTOML(path: configURL.path)]
        }
        return CodexConfigWriter.featureEnabled(in: toml) ? [] : [.codexFeatureDisabled(configPath: configURL.path)]
    }

    private static func orphanedIssues(writer: any ToolConfigWriter, scan: ConfigScan) -> [HookHealthReport.Issue] {
        guard scan.isConclusive, scan.foundAnyVibePetCommand,
              let hooksFile = writer.managedFiles.first(where: { $0.pathExtension == "json" }) else { return [] }
        return [.orphanedInstall(configPath: hooksFile.path)]
    }

    private struct HookCommand {
        let key: String
        let command: String
    }

    private static func hookCommandsByKey(in root: [String: Any]) -> [HookCommand] {
        guard let hooks = root["hooks"] as? [String: Any] else { return [] }
        return hooks.flatMap { key, value in
            ((value as? [[String: Any]]) ?? []).flatMap { group in
                ((group["hooks"] as? [[String: Any]]) ?? []).compactMap { hook in
                    (hook["command"] as? String).map { HookCommand(key: key, command: $0) }
                }
            }
        }
    }

    private static func isVibePetCommand(_ command: String) -> Bool {
        guard let executable = HookCommandShell.firstArgument(in: command) else { return false }
        return (executable as NSString).lastPathComponent == HooksBinaryLocator.binaryName
    }

    private static func hasCodexToolArgument(_ command: String) -> Bool {
        command.range(of: #"(?:^|\s)--tool\s+codex(?:\s|$)"#, options: .regularExpression) != nil
    }

    static func recordedBinaryPath(from command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        if (trimmed.hasPrefix("'") || trimmed.hasPrefix("\"")),
           let executable = HookCommandShell.firstArgument(in: trimmed) {
            return executable
        }
        if let range = trimmed.range(of: " --") {
            return String(trimmed[trimmed.startIndex..<range.lowerBound])
        }
        return trimmed
    }

    private static func standardizedPath(_ path: String?) -> String? {
        path.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
    }

    private static func managedSettingsPath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private static func commandName(from command: String) -> String {
        let path = HookCommandShell.firstArgument(in: command) ?? recordedBinaryPath(from: command)
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    private static func deduplicated(_ issues: [HookHealthReport.Issue]) -> [HookHealthReport.Issue] {
        issues.reduce(into: []) { result, issue in
            if !result.contains(issue) { result.append(issue) }
        }
    }
}

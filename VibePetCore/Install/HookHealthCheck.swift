import Foundation

/// A structured diagnosis of one tool's hook integration, beyond the manifest's
/// "installed?" bit. It catches config drift the simple status check misses: a moved
/// binary, hand-edited JSON, a removed hook, or (Codex) a disabled feature flag —
/// each classified so the UI/CLI can offer a one-click repair (re-run install).
public struct HookHealthReport: Equatable, Sendable {
    public enum Severity: Equatable, Sendable {
        /// A real problem that likely prevents VibePet hooks from working.
        case error
        /// Informational — hooks still work (e.g. other tools' hooks coexist).
        case info
    }

    public enum Issue: Equatable, Sendable, CustomStringConvertible {
        /// The managed `bin/VibePetHooks` is absent.
        case binaryNotFound(path: String)
        /// The managed binary exists but is not executable.
        case binaryNotExecutable(path: String)
        /// A managed JSON config file is not valid JSON (VibePet can't safely merge).
        case configMalformedJSON(path: String)
        /// A config command references a `VibePetHooks` path that no longer exists.
        case staleCommandPath(recorded: String, configPath: String)
        /// The tool is marked installed, but no VibePet hook command is in its config.
        case managedHooksMissing(configPath: String)
        /// The config still references VibePet hooks but no install is recorded — the
        /// manifest was lost or the binary was removed out from under us. Reinstall
        /// (to re-establish the manifest) or uninstall (to clean the config) repairs it.
        case orphanedInstall(configPath: String)
        /// Codex is installed but its `[features]` hooks flag is off, so hooks won't run.
        case codexFeatureDisabled(configPath: String)
        /// Other (non-VibePet) hooks coexist in the config — informational only.
        case otherHooksDetected(names: [String])

        public var severity: Severity {
            switch self {
            case .otherHooksDetected: .info
            default: .error
            }
        }

        /// Whether re-running install fixes it. Malformed user JSON and foreign hooks
        /// are not VibePet's to rewrite.
        public var isAutoRepairable: Bool {
            switch self {
            case .binaryNotFound, .binaryNotExecutable, .staleCommandPath,
                 .managedHooksMissing, .orphanedInstall, .codexFeatureDisabled:
                true
            case .configMalformedJSON, .otherHooksDetected:
                false
            }
        }

        public var description: String {
            switch self {
            case .binaryNotFound(let path):
                "Hook binary not found: \(path)"
            case .binaryNotExecutable(let path):
                "Hook binary is not executable: \(path)"
            case .configMalformedJSON(let path):
                "Config file is not valid JSON: \(path)"
            case .staleCommandPath(let recorded, let configPath):
                "Command in \(configPath) points to a missing binary: \(recorded)"
            case .managedHooksMissing(let configPath):
                "VibePet hook entry is missing from \(configPath)"
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

    /// No error-severity issues (info notices are fine).
    public var isHealthy: Bool { errors.isEmpty }
    public var errors: [Issue] { issues.filter { $0.severity == .error } }
    public var notices: [Issue] { issues.filter { $0.severity == .info } }
    public var repairableIssues: [Issue] { issues.filter(\.isAutoRepairable) }
}

/// Read-only deep health check over a tool's managed binary + config files. It never
/// writes; repair is left to the caller (re-running `HookInstaller.install`).
public enum HookHealthCheck {
    /// Diagnoses one tool. `recordedInstalled` (from the manifest/status) distinguishes
    /// "should be there but isn't" drift from "shouldn't be there but is" (orphaned)
    /// drift. The config is always scanned so a lost manifest with leftover hooks is
    /// still caught, rather than silently reported clean.
    public static func check(
        tool: ToolKind,
        writer: any ToolConfigWriter,
        managedBinaryURL: URL,
        recordedInstalled: Bool,
        fileManager: FileManager = .default
    ) -> HookHealthReport {
        var issues: [HookHealthReport.Issue] = []

        // 1. Scan JSON config files (Claude settings.json / Codex hooks.json). config.toml
        //    is not JSON and is handled separately below.
        let jsonFiles = writer.managedFiles.filter { $0.pathExtension == "json" }
        var foundManagedCommand = false
        var otherNames: Set<String> = []

        for file in jsonFiles where fileManager.fileExists(atPath: file.path) {
            guard let data = try? Data(contentsOf: file) else { continue }
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                issues.append(.configMalformedJSON(path: file.path))
                continue
            }
            for command in hookCommands(in: root) {
                if isVibePetCommand(command) {
                    foundManagedCommand = true
                    let recorded = recordedBinaryPath(from: command)
                    if !fileManager.fileExists(atPath: recorded) {
                        issues.append(.staleCommandPath(recorded: recorded, configPath: file.path))
                    }
                } else {
                    otherNames.insert(commandName(from: command))
                }
            }
        }

        // 2. Drift: manifest vs config.
        if recordedInstalled {
            // Managed binary should be present and runnable.
            let binaryPath = managedBinaryURL.path
            if !fileManager.fileExists(atPath: binaryPath) {
                issues.append(.binaryNotFound(path: binaryPath))
            } else if !fileManager.isExecutableFile(atPath: binaryPath) {
                issues.append(.binaryNotExecutable(path: binaryPath))
            }

            if !foundManagedCommand, let hooksFile = jsonFiles.first {
                issues.append(.managedHooksMissing(configPath: hooksFile.path))
            }

            // Codex feature flag (config.toml) must be on for hooks to run.
            if tool == .codex {
                let toml = (try? String(contentsOf: writer.configURL, encoding: .utf8)) ?? ""
                if !CodexConfigWriter.featureEnabled(in: toml) {
                    issues.append(.codexFeatureDisabled(configPath: writer.configURL.path))
                }
            }
        } else if foundManagedCommand, let hooksFile = jsonFiles.first {
            // Not recorded as installed, yet the config still references VibePet.
            issues.append(.orphanedInstall(configPath: hooksFile.path))
        }

        if !otherNames.isEmpty {
            issues.append(.otherHooksDetected(names: otherNames.sorted()))
        }

        return HookHealthReport(tool: tool, issues: issues)
    }

    // MARK: - JSON scanning (shared shape: root.hooks.<event>[].hooks[].command)

    private static func hookCommands(in root: [String: Any]) -> [String] {
        guard let hooks = root["hooks"] as? [String: Any] else { return [] }
        var commands: [String] = []
        for (_, value) in hooks {
            for group in (value as? [[String: Any]]) ?? [] {
                for hook in (group["hooks"] as? [[String: Any]]) ?? [] {
                    if let command = hook["command"] as? String {
                        commands.append(command)
                    }
                }
            }
        }
        return commands
    }

    private static func isVibePetCommand(_ command: String) -> Bool {
        command.contains(HooksBinaryLocator.binaryName)
    }

    /// The binary path recorded in a command, handling Codex's shell-quoting and
    /// Claude's unquoted (possibly space-containing) path with no arguments.
    static func recordedBinaryPath(from command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        for quote in ["'", "\""] where trimmed.hasPrefix(quote) {
            let body = trimmed.dropFirst()
            if let end = body.firstIndex(of: Character(quote)) {
                return String(body[body.startIndex..<end])
            }
        }
        // Unquoted: strip a trailing " --flag …" argument list if present.
        if let range = trimmed.range(of: " --") {
            return String(trimmed[trimmed.startIndex..<range.lowerBound])
        }
        return trimmed
    }

    private static func commandName(from command: String) -> String {
        let path = recordedBinaryPath(from: command)
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }
}

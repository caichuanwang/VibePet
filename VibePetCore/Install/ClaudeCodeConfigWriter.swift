import Foundation

/// Writes VibePet's hook entries into Claude Code's `settings.json` (JSON).
/// Each managed key gets one VibePet matcher-group whose command points at the stable
/// binary; user entries (and unmanaged keys / top-level settings) are preserved.
/// VibePet's entries are identified by the stable binary path in their command, so
/// install is idempotent and uninstall is precise.
public struct ClaudeCodeConfigWriter: ToolConfigWriter {
    public let tool: ToolKind = .claudeCode
    private static let legacyManagedHookKeys = ["PostToolUse"]
    public let configURL: URL
    public let managedHookKeys = [
        "PreToolUse",
        "PermissionRequest",
        "Stop",
        "Notification",
        "SessionStart",
        "UserPromptSubmit",
        "SubagentStart",
        "SubagentStop",
        "SessionEnd",
        "StopFailure",
        "PermissionDenied",
        "PreCompact",
    ]

    private let hookBinaryPath: String

    /// Seconds Claude Code waits for the blocking `PermissionRequest` hook before killing it.
    /// The native timeout is the final backstop above App and CLI deadlines.
    public static let managedDecisionTimeout = Int(
        HookDecisionBudget.nativeHookTimeout(for: .claudeCode)
    )

    public init(configURL: URL? = nil, hookBinaryPath: String? = nil) {
        self.configURL = configURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json", isDirectory: false)
        self.hookBinaryPath = hookBinaryPath ?? InstallPaths.hookBinaryURL().path
    }

    public func install(arguments: [String]) throws {
        var root = try readRootForMutation()
        var hooks = (root["hooks"] as? [String: Any]) ?? [:]
        // Quote the binary path: Claude Code runs the command via `/bin/sh -c`, so a
        // path containing spaces (e.g. `.../Application Support/...`) would split and
        // fail to launch. Mirrors CodexConfigWriter's shell-quoting.
        let command = ([HookCommandShell.quote(hookBinaryPath)] + arguments).joined(separator: " ")

        for key in managedHookKeys + Self.legacyManagedHookKeys {
            var groups = (hooks[key] as? [[String: Any]]) ?? []
            groups = removingVibePetHooks(from: groups)
            guard managedHookKeys.contains(key) else {
                if groups.isEmpty {
                    hooks.removeValue(forKey: key)
                } else {
                    hooks[key] = groups
                }
                continue
            }
            groups.append(entry(command: command, key: key))
            hooks[key] = groups
        }
        root["hooks"] = hooks
        try write(root)
    }

    /// The matcher-group VibePet writes for a hook key. Only `PermissionRequest`
    /// (the blocking approval/question round trip) carries a `timeout`; lifecycle
    /// hooks are fire-and-forget and use Claude's default.
    private func entry(command: String, key: String) -> [String: Any] {
        var hook: [String: Any] = ["type": "command", "command": command]
        if key == "PermissionRequest" {
            hook["timeout"] = Self.managedDecisionTimeout
        }
        return ["matcher": "", "hooks": [hook]]
    }

    public func uninstall() throws {
        guard configExists() else { return }
        var root = try readRootForMutation()
        guard var hooks = root["hooks"] as? [String: Any] else { return }

        for key in managedHookKeys + Self.legacyManagedHookKeys {
            guard let existingGroups = hooks[key] as? [[String: Any]] else { continue }
            let groups = removingVibePetHooks(from: existingGroups)
            if groups.isEmpty {
                hooks.removeValue(forKey: key)
            } else {
                hooks[key] = groups
            }
        }
        root["hooks"] = hooks
        try write(root)
    }

    // MARK: - Helpers

    private func removingVibePetHooks(from groups: [[String: Any]]) -> [[String: Any]] {
        groups.compactMap { group in
            guard let hooks = group["hooks"] as? [[String: Any]] else { return group }
            let remaining = hooks.filter { hook in
                guard let command = hook["command"] as? String else { return true }
                return !HookCommandShell.invokes(command, executablePath: hookBinaryPath)
            }
            guard !remaining.isEmpty else { return nil }
            var updated = group
            updated["hooks"] = remaining
            return updated
        }
    }

    private func readRootForMutation() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return [:] }
        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            throw ToolConfigMutationError.unreadable(path: configURL.path)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolConfigMutationError.malformedJSON(path: configURL.path)
        }
        _ = try HookConfigurationJSON.validatedHooks(in: object, path: configURL.path)
        return object
    }

    private func write(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: configURL, options: .atomic)
    }
}

enum HookConfigurationJSON {
    static func validatedHooks(in root: [String: Any], path: String) throws -> [String: Any] {
        guard let rawHooks = root["hooks"] else { return [:] }
        guard let hooks = rawHooks as? [String: Any] else {
            throw ToolConfigMutationError.malformedJSON(path: path)
        }
        for value in hooks.values {
            guard let groups = value as? [[String: Any]] else {
                throw ToolConfigMutationError.malformedJSON(path: path)
            }
            for group in groups where group["hooks"] as? [[String: Any]] == nil {
                throw ToolConfigMutationError.malformedJSON(path: path)
            }
        }
        return hooks
    }
}

enum HookCommandShell {
    private enum QuoteState {
        case unquoted
        case single
        case double
    }

    static func quote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func invokes(_ command: String, executablePath: String) -> Bool {
        firstArgument(in: command) == executablePath
    }

    static func firstArgument(in command: String) -> String? {
        let characters = Array(command)
        var index = 0
        while index < characters.count, characters[index].isWhitespace {
            index += 1
        }
        guard index < characters.count else { return nil }

        var state = QuoteState.unquoted
        var argument = ""
        while index < characters.count {
            let character = characters[index]
            switch state {
            case .unquoted:
                if character.isWhitespace {
                    return argument.isEmpty ? nil : argument
                }
                if character == "'" {
                    state = .single
                } else if character == "\"" {
                    state = .double
                } else if character == "\\" {
                    index += 1
                    guard index < characters.count else { return nil }
                    argument.append(characters[index])
                } else {
                    argument.append(character)
                }
            case .single:
                if character == "'" {
                    state = .unquoted
                } else {
                    argument.append(character)
                }
            case .double:
                if character == "\"" {
                    state = .unquoted
                } else if character == "\\" {
                    index += 1
                    guard index < characters.count else { return nil }
                    argument.append(characters[index])
                } else {
                    argument.append(character)
                }
            }
            index += 1
        }

        guard state == .unquoted, !argument.isEmpty else { return nil }
        return argument
    }
}

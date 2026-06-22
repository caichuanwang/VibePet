import Foundation

/// Writes VibePet's hook entries into Claude Code's `settings.json` (JSON), under
/// `hooks.PreToolUse` / `hooks.Stop` / `hooks.Notification` (technical design §4.1).
/// Each managed key gets one VibePet matcher-group whose command points at the stable
/// binary; user entries (and unmanaged keys / top-level settings) are preserved.
/// VibePet's entries are identified by the stable binary path in their command, so
/// install is idempotent and uninstall is precise.
public struct ClaudeCodeConfigWriter: ToolConfigWriter {
    public let tool: ToolKind = .claudeCode
    public let configURL: URL
    public let managedHookKeys = ["PreToolUse", "Stop", "Notification"]

    private let hookBinaryPath: String

    /// Seconds Claude Code waits for the `PreToolUse` hook before killing it. VibePet's
    /// approval window is governed by the App countdown (`decisionTimeoutSeconds`) and
    /// the CLI read deadline; Claude's per-hook `timeout` only needs to be larger than
    /// both so it never preempts them. Without it Claude's 60s default would cap any
    /// approval window set above ~55s. The CLI's connect/read deadlines remain the real
    /// fail-open backstop, so a large value here cannot cause a hang.
    static let managedDecisionTimeout = 86_400

    public init(configURL: URL? = nil, hookBinaryPath: String? = nil) {
        self.configURL = configURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json", isDirectory: false)
        self.hookBinaryPath = hookBinaryPath ?? InstallPaths.hookBinaryURL().path
    }

    public func install(arguments: [String]) throws {
        var root = readRoot()
        var hooks = (root["hooks"] as? [String: Any]) ?? [:]
        // Quote the binary path: Claude Code runs the command via `/bin/sh -c`, so a
        // path containing spaces (e.g. `.../Application Support/...`) would split and
        // fail to launch. Mirrors CodexConfigWriter's shell-quoting.
        let command = ([Self.shellQuote(hookBinaryPath)] + arguments).joined(separator: " ")

        for key in managedHookKeys {
            var groups = (hooks[key] as? [[String: Any]]) ?? []
            groups.removeAll { isVibePetGroup($0) } // drop any prior VibePet entry (idempotent)
            groups.append(entry(command: command, key: key))
            hooks[key] = groups
        }
        root["hooks"] = hooks
        try write(root)
    }

    /// The matcher-group VibePet writes for a hook key. Only `PreToolUse` (the blocking
    /// approval/question round trip) carries a `timeout`; `Stop`/`Notification` are
    /// fire-and-forget and use Claude's default.
    private func entry(command: String, key: String) -> [String: Any] {
        var hook: [String: Any] = ["type": "command", "command": command]
        if key == "PreToolUse" {
            hook["timeout"] = Self.managedDecisionTimeout
        }
        return ["matcher": "", "hooks": [hook]]
    }

    public func uninstall() throws {
        guard configExists() else { return }
        var root = readRoot()
        guard var hooks = root["hooks"] as? [String: Any] else { return }

        for key in managedHookKeys {
            guard var groups = hooks[key] as? [[String: Any]] else { continue }
            groups.removeAll { isVibePetGroup($0) }
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

    /// A matcher-group is VibePet's when any of its command hooks references the
    /// stable binary path.
    private func isVibePetGroup(_ group: [String: Any]) -> Bool {
        let innerHooks = (group["hooks"] as? [[String: Any]]) ?? []
        return innerHooks.contains { ($0["command"] as? String)?.contains(hookBinaryPath) == true }
    }

    /// Wraps a path in single quotes so `/bin/sh -c` treats it as one argument even
    /// when it contains spaces.
    private static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func readRoot() -> [String: Any] {
        guard
            let data = try? Data(contentsOf: configURL),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
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

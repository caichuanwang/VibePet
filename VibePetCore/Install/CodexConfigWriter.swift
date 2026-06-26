import Foundation

/// Writes VibePet's Codex integration the way open-vibe-island does (clean-room
/// reimplementation of the *approach*, not its GPL source): hook entries go into
/// `~/.codex/hooks.json` (JSON), and `config.toml` only gets a `[features]`
/// `hooks = true` flag toggled via line-based editing. This sidesteps TOML's
/// "root keys must precede tables" hazard (a naive `notify = [...]` append would be
/// invalid TOML) and keeps writes precise and reversible.
///
/// Managed groups are tagged with a `statusMessage` marker so uninstall removes only
/// VibePet's entries. Completion arrives via the registered `Stop` hook (not the
/// `notify` program). The hook command carries `--tool codex` so the CLI selects
/// `CodexAdapter` (technical design §4.2; see `Tests/Fixtures/codex/codex-spike-notes.md`).
public struct CodexConfigWriter: ToolConfigWriter {
    public let tool: ToolKind = .codex
    public let configURL: URL
    public let hooksURL: URL
    public var managedHookKeys: [String] { ["PermissionRequest", "Stop", "SessionStart", "UserPromptSubmit", "PostToolUse"] }
    public var managedFiles: [URL] { [configURL, hooksURL] }

    private let hookBinaryPath: String

    static let managedStatusMessage = "Managed by VibePet"
    /// Feature flag Codex ≥ 0.130 uses to enable hooks.
    static let featureKey = "hooks"
    /// Legacy flag older Codex builds (< 0.130) use for the same feature. We recognize
    /// it for status, remove it on uninstall, and keep writing to it when the user's
    /// existing config already uses it (so we don't break an older Codex).
    static let legacyFeatureKey = "codex_hooks"
    public static let permissionTimeout = 3600
    public static let stopTimeout = 45

    public init(codexDirectory: URL? = nil, hookBinaryPath: String? = nil) {
        let directory = codexDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        self.configURL = directory.appendingPathComponent("config.toml", isDirectory: false)
        self.hooksURL = directory.appendingPathComponent("hooks.json", isDirectory: false)
        self.hookBinaryPath = hookBinaryPath ?? InstallPaths.hookBinaryURL().path
    }

    public func install(arguments: [String]) throws {
        let command = Self.shellQuote(hookBinaryPath) + (arguments.isEmpty ? "" : " " + arguments.joined(separator: " "))
        try writeHooks(command: command)
        try setFeatureEnabled(true)
    }

    public func uninstall() throws {
        try removeManagedHooks()
        // Only switch the shared `[features]` flag off when nothing else needs it.
        // If the user has their own Codex hooks in hooks.json, disabling the flag
        // would silently break them — VibePet must touch only its own footprint.
        if !hooksRemain() {
            try setFeatureEnabled(false)
        }
    }

    /// Whether any hook entry (VibePet's or the user's) is still registered.
    private func hooksRemain() -> Bool {
        guard let hooks = readHooksRoot()["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            ((value as? [[String: Any]]) ?? []).contains { group in
                !(((group["hooks"] as? [[String: Any]]) ?? []).isEmpty)
            }
        }
    }

    // MARK: - hooks.json

    private func writeHooks(command: String) throws {
        var root = readHooksRoot()
        var hooks = (root["hooks"] as? [String: Any]) ?? [:]
        let timeouts = ["PermissionRequest": Self.permissionTimeout, "Stop": Self.stopTimeout]

        for event in managedHookKeys {
            var groups = (hooks[event] as? [[String: Any]]) ?? []
            groups.removeAll { isManagedGroup($0) } // idempotent
            groups.append(managedGroup(command: command, timeout: timeouts[event] ?? Self.stopTimeout))
            hooks[event] = groups
        }
        root["hooks"] = hooks
        try writeHooksRoot(root)
    }

    private func removeManagedHooks() throws {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else { return }
        var root = readHooksRoot()
        guard var hooks = root["hooks"] as? [String: Any] else { return }

        for event in managedHookKeys {
            guard var groups = hooks[event] as? [[String: Any]] else { continue }
            groups.removeAll { isManagedGroup($0) }
            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = groups
            }
        }

        if hooks.isEmpty {
            try? FileManager.default.removeItem(at: hooksURL)
            return
        }
        root["hooks"] = hooks
        try writeHooksRoot(root)
    }

    private func managedGroup(command: String, timeout: Int) -> [String: Any] {
        [
            "hooks": [[
                "type": "command",
                "command": command,
                "timeout": timeout,
                "statusMessage": Self.managedStatusMessage,
            ]],
        ]
    }

    private func isManagedGroup(_ group: [String: Any]) -> Bool {
        let inner = (group["hooks"] as? [[String: Any]]) ?? []
        return inner.contains { hook in
            (hook["statusMessage"] as? String) == Self.managedStatusMessage
                || (hook["command"] as? String)?.contains(hookBinaryPath) == true
        }
    }

    private func readHooksRoot() -> [String: Any] {
        guard
            let data = try? Data(contentsOf: hooksURL),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object
    }

    private func writeHooksRoot(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: hooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: hooksURL, options: .atomic)
    }

    // MARK: - config.toml [features] flag (line-based; table-safe)

    private func setFeatureEnabled(_ enabled: Bool) throws {
        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let updated: String
        if enabled {
            // Respect an older Codex that already uses the legacy key; otherwise the
            // modern key. No process probing — grounded in the user's existing file.
            let key = Self.featureKeyToWrite(in: existing)
            let alternate = key == Self.featureKey ? Self.legacyFeatureKey : Self.featureKey
            // Migrate: enable the chosen key and drop the alternate so the file never
            // carries both flags at once.
            updated = Self.disableFeature(in: Self.enableFeature(in: existing, key: key), key: alternate)
        } else {
            // Clear both managed flags so neither key lingers after uninstall.
            updated = Self.disableFeature(
                in: Self.disableFeature(in: existing, key: Self.featureKey),
                key: Self.legacyFeatureKey
            )
        }
        guard updated != existing else { return }
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(updated.utf8).write(to: configURL, options: .atomic)
    }

    /// The flag key to write: the legacy key when the config already declares it under
    /// `[features]` and not the modern key (an older Codex); otherwise the modern key.
    static func featureKeyToWrite(in contents: String) -> String {
        let lines = contents.isEmpty ? [] : contents.components(separatedBy: "\n")
        guard let header = featuresHeaderIndex(in: lines) else { return featureKey }
        let end = sectionEnd(after: header, in: lines)
        let hasLegacy = (header + 1..<end).contains { isKeyLine(lines[$0], key: legacyFeatureKey) }
        let hasModern = (header + 1..<end).contains { isKeyLine(lines[$0], key: featureKey) }
        return (hasLegacy && !hasModern) ? legacyFeatureKey : featureKey
    }

    /// Whether hooks are enabled via either the modern or legacy `[features]` flag set
    /// to `true`. Used by `HookHealthCheck` to verify Codex's config-side activation.
    static func featureEnabled(in contents: String) -> Bool {
        let lines = contents.isEmpty ? [] : contents.components(separatedBy: "\n")
        guard let header = featuresHeaderIndex(in: lines) else { return false }
        let end = sectionEnd(after: header, in: lines)
        return (header + 1..<end).contains { index in
            (isKeyLine(lines[index], key: featureKey) || isKeyLine(lines[index], key: legacyFeatureKey))
                && lineValueIsTrue(lines[index])
        }
    }

    /// Whether a `key = true` line's value parses as the boolean `true`.
    private static func lineValueIsTrue(_ line: String) -> Bool {
        guard let equals = line.firstIndex(of: "=") else { return false }
        let value = line[line.index(after: equals)...]
            .trimmingCharacters(in: .whitespaces)
        // Strip a trailing inline comment, if any.
        let withoutComment = value.split(separator: "#", maxSplits: 1).first.map(String.init) ?? value
        return withoutComment.trimmingCharacters(in: .whitespaces) == "true"
    }

    /// Sets `<key> = true` under `[features]`, creating the table if needed. Only
    /// adds keys to a table (never a root key after a table), so the file stays valid.
    static func enableFeature(in contents: String, key: String) -> String {
        var lines = contents.isEmpty ? [] : contents.components(separatedBy: "\n")
        if let header = featuresHeaderIndex(in: lines) {
            let end = sectionEnd(after: header, in: lines)
            if let keyIndex = (header + 1..<end).first(where: { isKeyLine(lines[$0], key: key) }) {
                lines[keyIndex] = "\(key) = true"
            } else {
                lines.insert("\(key) = true", at: header + 1)
            }
            return lines.joined(separator: "\n")
        }
        if !lines.isEmpty, lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == false {
            lines.append("")
        }
        lines.append("[features]")
        lines.append("\(key) = true")
        return lines.joined(separator: "\n")
    }

    /// Removes the managed `<key>` line under `[features]`, preserving everything else.
    static func disableFeature(in contents: String, key: String) -> String {
        guard !contents.isEmpty else { return contents }
        var lines = contents.components(separatedBy: "\n")
        guard let header = featuresHeaderIndex(in: lines) else { return contents }
        let end = sectionEnd(after: header, in: lines)
        let toRemove = (header + 1..<end).filter { isKeyLine(lines[$0], key: key) }
        for index in toRemove.reversed() {
            lines.remove(at: index)
        }
        return lines.joined(separator: "\n")
    }

    private static func featuresHeaderIndex(in lines: [String]) -> Int? {
        lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "[features]" }
    }

    /// Index just past the last line of the section starting at `header` (i.e. the
    /// next table header, or end of file).
    private static func sectionEnd(after header: Int, in lines: [String]) -> Int {
        var index = header + 1
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                break
            }
            index += 1
        }
        return index
    }

    private static func isKeyLine(_ line: String, key: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else {
            return false
        }
        return trimmed[..<equals].trimmingCharacters(in: .whitespaces) == key
    }

    private static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

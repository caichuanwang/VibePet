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
    public var managedHookKeys: [String] { ["PermissionRequest", "Stop", "SessionStart", "UserPromptSubmit"] }
    public var managedFiles: [URL] { [configURL, hooksURL] }

    private let hookBinaryPath: String

    private static let legacyManagedHookKeys = ["PostToolUse"]
    static let managedStatusMessage = "Managed by VibePet"
    /// Feature flag Codex ≥ 0.130 uses to enable hooks.
    static let featureKey = "hooks"
    /// Legacy flag older Codex builds (< 0.130) use for the same feature. We recognize
    /// it for status, remove it on uninstall, and keep writing to it when the user's
    /// existing config already uses it (so we don't break an older Codex).
    static let legacyFeatureKey = "codex_hooks"
    public static let permissionTimeout = Int(
        HookDecisionBudget.nativeHookTimeout(for: .codex)
    )
    public static let stopTimeout = 45

    public init(codexDirectory: URL? = nil, hookBinaryPath: String? = nil) {
        let directory = codexDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        self.configURL = directory.appendingPathComponent("config.toml", isDirectory: false)
        self.hooksURL = directory.appendingPathComponent("hooks.json", isDirectory: false)
        self.hookBinaryPath = hookBinaryPath ?? InstallPaths.hookBinaryURL().path
    }

    public func install(arguments: [String]) throws {
        _ = try installWithReceipt(arguments: arguments)
    }

    public func installWithReceipt(arguments: [String]) throws -> ToolConfigInstallReceipt {
        let featureState = try featureStateBeforeInstall()
        let command = HookCommandShell.quote(hookBinaryPath) + (arguments.isEmpty ? "" : " " + arguments.joined(separator: " "))
        try writeHooks(command: command)
        try setFeatureEnabled(true)
        return .codexFeature(featureState)
    }

    public func uninstall() throws {
        try uninstall(receipt: .codexFeature(.unknown))
    }

    public func uninstall(receipt: ToolConfigInstallReceipt) throws {
        // Both managed files form one logical configuration. Validate both before
        // mutating either so malformed TOML cannot leave hooks.json half-uninstalled.
        _ = try readHooksRootForMutation()
        _ = try readConfigForMutation()
        try removeManagedHooks()
        let featureState: CodexFeatureStateBeforeInstall
        if case let .codexFeature(state) = receipt {
            featureState = state
        } else {
            featureState = .unknown
        }
        // Only an explicit first-install receipt proving both flags were disabled
        // authorizes VibePet to turn the shared feature back off.
        if featureState == .disabled, !hooksRemain() {
            try setFeatureEnabled(false)
        }
    }

    /// Whether any hook entry (VibePet's or the user's) is still registered.
    private func hooksRemain() -> Bool {
        guard let root = try? readHooksRootForMutation(),
              let hooks = root["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            ((value as? [[String: Any]]) ?? []).contains { group in
                !(((group["hooks"] as? [[String: Any]]) ?? []).isEmpty)
            }
        }
    }

    // MARK: - hooks.json

    private func writeHooks(command: String) throws {
        var root = try readHooksRootForMutation()
        var hooks = (root["hooks"] as? [String: Any]) ?? [:]
        let timeouts = ["PermissionRequest": Self.permissionTimeout, "Stop": Self.stopTimeout]

        for event in managedHookKeys + Self.legacyManagedHookKeys {
            var groups = (hooks[event] as? [[String: Any]]) ?? []
            groups = removingManagedHooks(from: groups)
            guard managedHookKeys.contains(event) else {
                if groups.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = groups
                }
                continue
            }
            groups.append(managedGroup(command: command, timeout: timeouts[event] ?? Self.stopTimeout))
            hooks[event] = groups
        }
        root["hooks"] = hooks
        try writeHooksRoot(root)
    }

    private func removeManagedHooks() throws {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else { return }
        var root = try readHooksRootForMutation()
        guard var hooks = root["hooks"] as? [String: Any] else { return }

        for event in managedHookKeys + Self.legacyManagedHookKeys {
            guard let existingGroups = hooks[event] as? [[String: Any]] else { continue }
            let groups = removingManagedHooks(from: existingGroups)
            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = groups
            }
        }

        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
            if root.isEmpty {
                try FileManager.default.removeItem(at: hooksURL)
            } else {
                try writeHooksRoot(root)
            }
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

    private func removingManagedHooks(from groups: [[String: Any]]) -> [[String: Any]] {
        groups.compactMap { group in
            guard let hooks = group["hooks"] as? [[String: Any]] else { return group }
            let remaining = hooks.filter { hook in
                if (hook["statusMessage"] as? String) == Self.managedStatusMessage {
                    return false
                }
                guard let command = hook["command"] as? String else { return true }
                return !HookCommandShell.invokes(command, executablePath: hookBinaryPath)
            }
            guard !remaining.isEmpty else { return nil }
            var updated = group
            updated["hooks"] = remaining
            return updated
        }
    }

    private func readHooksRootForMutation() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else { return [:] }
        let data: Data
        do {
            data = try Data(contentsOf: hooksURL)
        } catch {
            throw ToolConfigMutationError.unreadable(path: hooksURL.path)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolConfigMutationError.malformedJSON(path: hooksURL.path)
        }
        _ = try HookConfigurationJSON.validatedHooks(in: object, path: hooksURL.path)
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
        let existing = try readConfigForMutation()
        let updated: String
        if enabled {
            // A pre-enabled modern, legacy, or mixed configuration is user-owned.
            // Leave it byte-for-byte intact instead of migrating keys across Codex
            // generations. When neither key is active, enable the key already declared
            // by the file (legacy-only for older Codex, modern otherwise).
            updated = Self.featureEnabled(in: existing)
                ? existing
                : Self.enableFeature(in: existing, key: Self.featureKeyToWrite(in: existing))
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

    private func featureStateBeforeInstall() throws -> CodexFeatureStateBeforeInstall {
        let contents = try readConfigForMutation()
        let lines = contents.isEmpty ? [] : contents.components(separatedBy: "\n")
        guard let header = Self.featuresHeaderIndex(in: lines) else { return .disabled }
        let end = Self.sectionEnd(after: header, in: lines)
        let modernEnabled = (header + 1..<end).contains {
            Self.isKeyLine(lines[$0], key: Self.featureKey) && Self.lineValueIsTrue(lines[$0])
        }
        let legacyEnabled = (header + 1..<end).contains {
            Self.isKeyLine(lines[$0], key: Self.legacyFeatureKey) && Self.lineValueIsTrue(lines[$0])
        }
        if modernEnabled { return .enabledModern }
        if legacyEnabled { return .enabledLegacy }
        return .disabled
    }

    private func readConfigForMutation() throws -> String {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return "" }
        let contents: String
        do {
            contents = try String(contentsOf: configURL, encoding: .utf8)
        } catch {
            throw ToolConfigMutationError.unreadable(path: configURL.path)
        }
        guard Self.featureSyntaxIsSafe(in: contents) else {
            throw ToolConfigMutationError.malformedTOML(path: configURL.path)
        }
        return contents
    }

    static func featureSyntaxIsSafe(in contents: String) -> Bool {
        guard let structure = tomlStructureIfSafe(in: contents) else { return false }
        let tableHeaders = structure.tableHeaders
        let lines = contents.isEmpty ? [] : contents.components(separatedBy: "\n")
        let featureHeaders = tableHeaders.filter { _, identity in
            !identity.isArray && identity.keys == ["features"]
        }
        guard !tableHeaders.values.contains(where: {
            $0.isArray && $0.keys == ["features"]
        }) else { return false }
        guard featureHeaders.count <= 1 else { return false }
        let firstTableHeader = tableHeaders.keys.min() ?? lines.count
        guard !structure.assignments.contains(where: { lineNumber, assignment in
            lineNumber < firstTableHeader && assignment.keys.first == "features"
        }) else { return false }
        if featureHeaders.isEmpty,
           tableHeaders.values.contains(where: { $0.keys.first == "features" }) {
            return false
        }
        let supportedKeys = Set([featureKey, legacyFeatureKey])
        guard !tableHeaders.values.contains(where: { identity in
            identity.keys.count > 1
                && identity.keys.first == "features"
                && supportedKeys.contains(identity.keys[1])
        }) else { return false }
        guard let header = featureHeaders.keys.first else { return true }
        let end = sectionEnd(after: header, in: lines)
        var seenSupportedKeys: Set<String> = []
        for index in header + 1..<end {
            guard let assignment = structure.assignments[index],
                  let key = assignment.keys.first,
                  supportedKeys.contains(key) else { continue }
            guard assignment.keys.count == 1,
                  seenSupportedKeys.insert(key).inserted else { return false }
            let value = assignment.value.split(separator: "#", maxSplits: 1).first
                .map(String.init) ?? assignment.value
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed == "true" || trimmed == "false" else { return false }
        }
        return true
    }

    private enum TOMLStringState {
        case none
        case basic
        case literal
        case multilineBasic
        case multilineLiteral
    }

    private struct TableHeaderIdentity: Hashable {
        var isArray: Bool
        var keys: [String]
    }

    private struct TOMLAssignment {
        var keys: [String]
        var value: String
    }

    private struct TOMLStructure {
        var tableHeaders: [Int: TableHeaderIdentity]
        var assignments: [Int: TOMLAssignment]
    }

    private static func tomlStructureIfSafe(
        in contents: String
    ) -> TOMLStructure? {
        let characters = Array(contents)
        var state = TOMLStringState.none
        var escaped = false
        var inComment = false
        var squareDepth = 0
        var braceDepth = 0
        var delimiterStack: [Character] = []
        var index = 0
        var lineNumber = 0
        var topLevelLineNumbers: Set<Int> = [0]

        while index < characters.count {
            let character = characters[index]
            let hasTripleQuote = index + 2 < characters.count
                && characters[index + 1] == character
                && characters[index + 2] == character

            if inComment {
                if character == "\n" {
                    inComment = false
                    lineNumber += 1
                    if state == .none, squareDepth == 0, braceDepth == 0 {
                        topLevelLineNumbers.insert(lineNumber)
                    }
                }
                index += 1
                continue
            }

            switch state {
            case .basic:
                if character == "\n" { return nil }
                if escaped {
                    guard basicEscapeIsValid(at: index, in: characters, allowsNewline: false) else {
                        return nil
                    }
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    state = .none
                }
            case .literal:
                if character == "\n" { return nil }
                if character == "'" { state = .none }
            case .multilineBasic:
                if escaped {
                    guard basicEscapeIsValid(at: index, in: characters, allowsNewline: true) else {
                        return nil
                    }
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"", hasTripleQuote {
                    state = .none
                    index += 2
                }
            case .multilineLiteral:
                if character == "'", hasTripleQuote {
                    state = .none
                    index += 2
                }
            case .none:
                switch character {
                case "#":
                    inComment = true
                case "\"":
                    state = hasTripleQuote ? .multilineBasic : .basic
                    if hasTripleQuote { index += 2 }
                case "'":
                    state = hasTripleQuote ? .multilineLiteral : .literal
                    if hasTripleQuote { index += 2 }
                case "[":
                    delimiterStack.append("]")
                    squareDepth += 1
                case "]":
                    guard delimiterStack.last == "]", squareDepth > 0 else { return nil }
                    delimiterStack.removeLast()
                    squareDepth -= 1
                case "{":
                    delimiterStack.append("}")
                    braceDepth += 1
                case "}":
                    guard delimiterStack.last == "}", braceDepth > 0 else { return nil }
                    delimiterStack.removeLast()
                    braceDepth -= 1
                default:
                    break
                }
            }
            if character == "\n" {
                lineNumber += 1
                if state == .none, squareDepth == 0, braceDepth == 0 {
                    topLevelLineNumbers.insert(lineNumber)
                }
            }
            index += 1
        }

        guard state == .none,
              squareDepth == 0,
              braceDepth == 0,
              delimiterStack.isEmpty else { return nil }

        let lines = contents.components(separatedBy: "\n")
        var tableHeaders: [Int: TableHeaderIdentity] = [:]
        var assignments: [Int: TOMLAssignment] = [:]
        var ordinaryTableNames: Set<[String]> = []
        var arrayTableNames: Set<[String]> = []
        for lineNumber in topLevelLineNumbers.sorted() where lineNumber < lines.count {
            let line = lines[lineNumber]
            if tableHeader(in: line) != nil {
                guard let identity = tableHeaderIdentity(in: line) else { return nil }
                tableHeaders[lineNumber] = identity
                if identity.isArray {
                    guard !ordinaryTableNames.contains(identity.keys) else { return nil }
                    arrayTableNames.insert(identity.keys)
                } else {
                    guard !arrayTableNames.contains(identity.keys),
                          ordinaryTableNames.insert(identity.keys).inserted else { return nil }
                }
            } else if let assignment = tomlAssignment(in: line) {
                assignments[lineNumber] = assignment
            }
        }
        return TOMLStructure(tableHeaders: tableHeaders, assignments: assignments)
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
        guard let assignment = tomlAssignment(in: line) else { return false }
        let value = assignment.value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip a trailing inline comment, if any.
        let withoutComment = value.split(separator: "#", maxSplits: 1).first.map(String.init) ?? value
        return withoutComment.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
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
        guard let structure = tomlStructureIfSafe(
            in: lines.joined(separator: "\n")
        ) else { return nil }
        let headers = structure.tableHeaders
        return headers.keys.sorted().first { index in
            guard let identity = headers[index] else { return false }
            return !identity.isArray && identity.keys == ["features"]
        }
    }

    /// Index just past the last line of the section starting at `header` (i.e. the
    /// next table header, or end of file).
    private static func sectionEnd(after header: Int, in lines: [String]) -> Int {
        guard let structure = tomlStructureIfSafe(
            in: lines.joined(separator: "\n")
        ) else { return lines.count }
        let headers = structure.tableHeaders
        return headers.keys.filter { $0 > header }.min() ?? lines.count
    }

    private static func tableHeader(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") else { return nil }

        var candidate = ""
        var quote: Character?
        var escaped = false
        for character in trimmed {
            if let activeQuote = quote {
                candidate.append(character)
                if activeQuote == "\"", escaped {
                    escaped = false
                } else if activeQuote == "\"", character == "\\" {
                    escaped = true
                } else if character == activeQuote {
                    quote = nil
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                candidate.append(character)
            } else if character == "#" {
                break
            } else {
                candidate.append(character)
            }
        }

        candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard quote == nil, candidate.hasSuffix("]") else { return nil }
        if candidate.hasPrefix("[[") {
            return candidate.hasSuffix("]]") ? candidate : nil
        }
        return candidate
    }

    private static func tableHeaderIdentity(in line: String) -> TableHeaderIdentity? {
        guard let header = tableHeader(in: line) else { return nil }
        let isArray = header.hasPrefix("[[")
        let bracketCount = isArray ? 2 : 1
        let keyText = String(header.dropFirst(bracketCount).dropLast(bracketCount))
        guard let keys = parseDottedKey(keyText), !keys.isEmpty else { return nil }
        return TableHeaderIdentity(isArray: isArray, keys: keys)
    }

    private static func tomlAssignment(in line: String) -> TOMLAssignment? {
        let characters = Array(line)
        var quote: Character?
        var escaped = false

        for index in characters.indices {
            let character = characters[index]
            if let activeQuote = quote {
                if activeQuote == "\"", escaped {
                    escaped = false
                } else if activeQuote == "\"", character == "\\" {
                    escaped = true
                } else if character == activeQuote {
                    quote = nil
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
            } else if character == "#" {
                return nil
            } else if character == "=" {
                let lhs = String(characters[..<index])
                let value = String(characters[(index + 1)...])
                guard let keys = parseDottedKey(lhs), !keys.isEmpty else { return nil }
                return TOMLAssignment(keys: keys, value: value)
            }
        }
        return nil
    }

    private static func parseDottedKey(_ source: String) -> [String]? {
        let characters = Array(source)
        var index = 0
        var keys: [String] = []

        func skipWhitespace() {
            while index < characters.count,
                  characters[index] == " " || characters[index] == "\t" {
                index += 1
            }
        }

        while true {
            skipWhitespace()
            guard index < characters.count else { return nil }

            let key: String
            if characters[index] == "'" {
                index += 1
                let start = index
                while index < characters.count, characters[index] != "'" {
                    index += 1
                }
                guard index < characters.count else { return nil }
                key = String(characters[start..<index])
                index += 1
            } else if characters[index] == "\"" {
                let start = index
                index += 1
                var escaped = false
                var closed = false
                while index < characters.count {
                    let character = characters[index]
                    if escaped {
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == "\"" {
                        index += 1
                        closed = true
                        break
                    }
                    index += 1
                }
                guard closed else { return nil }
                let literal = String(characters[start..<index])
                guard basicStringEscapesAreValid(in: literal) else { return nil }
                guard let decoded = try? JSONDecoder().decode(String.self, from: Data(literal.utf8)) else {
                    return nil
                }
                key = decoded
            } else {
                let start = index
                while index < characters.count, isBareKeyCharacter(characters[index]) {
                    index += 1
                }
                guard index > start else { return nil }
                key = String(characters[start..<index])
            }

            keys.append(key)
            skipWhitespace()
            if index == characters.count { return keys }
            guard characters[index] == "." else { return nil }
            index += 1
        }
    }

    private static func isBareKeyCharacter(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let value = character.unicodeScalars.first?.value else { return false }
        return (48...57).contains(value)
            || (65...90).contains(value)
            || (97...122).contains(value)
            || value == 45
            || value == 95
    }

    private static func basicStringEscapesAreValid(in literal: String) -> Bool {
        let characters = Array(literal)
        guard characters.count >= 2 else { return false }
        var index = 1
        while index < characters.count - 1 {
            if characters[index] == "\\" {
                index += 1
                guard index < characters.count - 1,
                      basicEscapeIsValid(at: index, in: characters, allowsNewline: false) else {
                    return false
                }
            }
            index += 1
        }
        return true
    }

    private static func basicEscapeIsValid(
        at index: Int,
        in characters: [Character],
        allowsNewline: Bool
    ) -> Bool {
        guard index < characters.count else { return false }
        let character = characters[index]
        if allowsNewline, character == "\n" { return true }
        if ["b", "t", "n", "f", "r", "\"", "\\"].contains(character) {
            return true
        }
        let digitCount: Int
        if character == "u" {
            digitCount = 4
        } else if character == "U" {
            digitCount = 8
        } else {
            return false
        }
        guard index + digitCount < characters.count else { return false }
        let digitRange = index + 1...index + digitCount
        guard digitRange.allSatisfy({ isHexDigit(characters[$0]) }),
              let scalar = UInt32(String(characters[digitRange]), radix: 16) else { return false }
        return scalar <= 0x10_FFFF && !(0xD800...0xDFFF).contains(scalar)
    }

    private static func isHexDigit(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let value = character.unicodeScalars.first?.value else { return false }
        return (48...57).contains(value)
            || (65...70).contains(value)
            || (97...102).contains(value)
    }

    private static func isKeyLine(_ line: String, key: String) -> Bool {
        tomlAssignment(in: line)?.keys == [key]
    }

}

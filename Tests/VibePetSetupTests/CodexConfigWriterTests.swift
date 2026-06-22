import XCTest
@testable import VibePetCore

/// M6-5: `CodexConfigWriter` follows the open-vibe-island pattern — VibePet's hooks
/// go into `~/.codex/hooks.json` (JSON, managed groups marked `statusMessage`), and
/// `config.toml` only gets a `[features]` `hooks = true` flag toggled (line-based, so
/// no TOML root-key reordering). Install preserves the user's config/hooks and is
/// idempotent; uninstall removes only VibePet's entries and the managed feature flag.
final class CodexConfigWriterTests: XCTestCase {
    private let binaryPath = "/Users/dev/Library/Application Support/VibePet/bin/VibePetHooks"
    private let managedHookKeys = ["PermissionRequest", "Stop", "SessionStart", "UserPromptSubmit"]

    func testInstallWritesManagedHooksWithMarkerAndToolArg() throws {
        let dir = try tempCodexDir()
        let writer = CodexConfigWriter(codexDirectory: dir, hookBinaryPath: binaryPath)

        try writer.install(arguments: ["--tool", "codex"])

        let hooks = try hooksObject(dir)
        XCTAssertEqual(writer.managedHookKeys, managedHookKeys)
        for event in managedHookKeys {
            let groupHooks = innerHooks(in: hooks, event: event)
            XCTAssertEqual(groupHooks.count, 1, "one managed group for \(event)")
            let hook = try XCTUnwrap(groupHooks.first)
            XCTAssertEqual(hook["statusMessage"] as? String, "Managed by VibePet")
            let command = try XCTUnwrap(hook["command"] as? String)
            XCTAssertTrue(command.contains(binaryPath))
            XCTAssertTrue(command.contains("--tool codex"), "command must select CodexAdapter")
        }
    }

    func testQuotesBinaryPathForEveryManagedHook() throws {
        let dir = try tempCodexDir()
        let writer = CodexConfigWriter(codexDirectory: dir, hookBinaryPath: binaryPath)

        try writer.install(arguments: ["--tool", "codex"])

        let hooks = try hooksObject(dir)
        for event in managedHookKeys {
            let hook = try XCTUnwrap(innerHooks(in: hooks, event: event).first)
            let command = try XCTUnwrap(hook["command"] as? String)
            XCTAssertTrue(command.contains("'\(binaryPath)'"), "binary path must be single-quoted for \(event); got: \(command)")
        }
    }

    func testInstallEnablesFeatureFlag() throws {
        let dir = try tempCodexDir()
        let writer = CodexConfigWriter(codexDirectory: dir, hookBinaryPath: binaryPath)

        try writer.install(arguments: ["--tool", "codex"])

        let toml = try String(contentsOf: dir.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(featureEnabled(toml, key: "hooks"), "config.toml must enable [features] hooks = true")
    }

    func testPreservesUserConfigAndHooks() throws {
        let dir = try tempCodexDir(configFixture: "config.toml", hooksFixture: "hooks-with-user.json")
        let writer = CodexConfigWriter(codexDirectory: dir, hookBinaryPath: binaryPath)

        try writer.install(arguments: ["--tool", "codex"])

        let toml = try String(contentsOf: dir.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(toml.contains("web_search = true"), "user feature flag preserved")
        XCTAssertTrue(toml.contains("[mcp_servers.example]"), "user table preserved")
        XCTAssertTrue(featureEnabled(toml, key: "hooks"))

        let hooks = try hooksObject(dir)
        // User's PreToolUse hook survives; VibePet's managed events are added.
        XCTAssertEqual(innerHooks(in: hooks, event: "PreToolUse").first?["command"] as? String, "/usr/local/bin/user-codex-hook")
        for event in managedHookKeys {
            XCTAssertFalse(innerHooks(in: hooks, event: event).isEmpty, "\(event) managed hook added")
        }
    }

    func testInstallIsIdempotent() throws {
        let dir = try tempCodexDir()
        let writer = CodexConfigWriter(codexDirectory: dir, hookBinaryPath: binaryPath)

        try writer.install(arguments: ["--tool", "codex"])
        try writer.install(arguments: ["--tool", "codex"])

        let hooks = try hooksObject(dir)
        for event in managedHookKeys {
            XCTAssertEqual(innerHooks(in: hooks, event: event).count, 1, "no duplicate managed group for \(event)")
        }
        let toml = try String(contentsOf: dir.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertEqual(toml.components(separatedBy: "hooks = true").count - 1, 1, "feature flag not duplicated")
    }

    func testUninstallPreservesFeatureFlagWhenUserHooksRemain() throws {
        // The user has their own Codex hook; disabling the shared [features] flag on
        // uninstall would silently break it, so VibePet must leave the flag enabled.
        let dir = try tempCodexDir(configFixture: "config.toml", hooksFixture: "hooks-with-user.json")
        let writer = CodexConfigWriter(codexDirectory: dir, hookBinaryPath: binaryPath)
        try writer.install(arguments: ["--tool", "codex"])

        try writer.uninstall()

        let hooks = try hooksObject(dir)
        for event in managedHookKeys {
            XCTAssertTrue(innerHooks(in: hooks, event: event).isEmpty, "managed hook removed: \(event)")
        }
        XCTAssertEqual(innerHooks(in: hooks, event: "PreToolUse").first?["command"] as? String, "/usr/local/bin/user-codex-hook", "user hook preserved")

        let toml = try String(contentsOf: dir.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(featureEnabled(toml, key: "hooks"), "flag kept — the user's hook still needs it")
        XCTAssertTrue(toml.contains("web_search = true"), "user feature flag preserved")
        XCTAssertTrue(toml.contains("[mcp_servers.example]"))
    }

    func testUninstallRemovesFeatureFlagWhenNoHooksRemain() throws {
        // VibePet is the only hook present → uninstall fully cleans up, flag included.
        let dir = try tempCodexDir()
        let writer = CodexConfigWriter(codexDirectory: dir, hookBinaryPath: binaryPath)
        try writer.install(arguments: ["--tool", "codex"])

        try writer.uninstall()

        let toml = try String(contentsOf: dir.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertFalse(featureEnabled(toml, key: "hooks"), "managed feature flag removed when nothing else needs it")
    }

    func testInstallMigratesLegacyKeyForwardWhenBothCouldExist() throws {
        // A config already on the modern key must not accumulate the legacy one, and
        // vice versa — only one flag should ever be present after install.
        let dir = try tempCodexDir()
        try "[features]\ncodex_hooks = true\nhooks = true\n".write(
            to: dir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8
        )
        let writer = CodexConfigWriter(codexDirectory: dir, hookBinaryPath: binaryPath)

        try writer.install(arguments: ["--tool", "codex"])

        let lines = try String(contentsOf: dir.appendingPathComponent("config.toml"), encoding: .utf8)
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertTrue(lines.contains("hooks = true"), "modern key enabled")
        XCTAssertFalse(lines.contains { $0.hasPrefix("codex_hooks") }, "legacy key migrated away")
    }

    func testInstallWritesLegacyKeyWhenExistingConfigUsesIt() throws {
        // An older Codex's config declares the legacy flag; VibePet must keep using it
        // rather than write the modern key the old Codex doesn't understand.
        let dir = try tempCodexDir()
        try "[features]\ncodex_hooks = false\n".write(
            to: dir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8
        )
        let writer = CodexConfigWriter(codexDirectory: dir, hookBinaryPath: binaryPath)

        try writer.install(arguments: ["--tool", "codex"])

        let toml = try String(contentsOf: dir.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(featureEnabled(toml, key: "codex_hooks"), "legacy key must be enabled")
        // Exact-line check: "codex_hooks = true" must not be mistaken for the modern key.
        let lines = toml.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertFalse(lines.contains("hooks = true"), "must not introduce the modern key for an old Codex")
    }

    func testUninstallRemovesBothModernAndLegacyKeys() throws {
        // A config carrying both keys (e.g. after a Codex upgrade) must end up clean.
        let dir = try tempCodexDir()
        try "[features]\nhooks = true\ncodex_hooks = true\n".write(
            to: dir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8
        )
        let writer = CodexConfigWriter(codexDirectory: dir, hookBinaryPath: binaryPath)
        try writer.install(arguments: ["--tool", "codex"])

        try writer.uninstall()

        let toml = try String(contentsOf: dir.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertFalse(toml.contains("hooks = true"), "modern key removed")
        XCTAssertFalse(toml.contains("codex_hooks = true"), "legacy key removed")
    }

    func testFeatureEnabledRecognizesEitherKey() {
        XCTAssertTrue(CodexConfigWriter.featureEnabled(in: "[features]\nhooks = true\n"))
        XCTAssertTrue(CodexConfigWriter.featureEnabled(in: "[features]\ncodex_hooks = true\n"))
        XCTAssertTrue(CodexConfigWriter.featureEnabled(in: "[features]\nhooks = true # managed\n"))
        XCTAssertFalse(CodexConfigWriter.featureEnabled(in: "[features]\nhooks = false\n"))
        XCTAssertFalse(CodexConfigWriter.featureEnabled(in: "[other]\nhooks = true\n"))
        XCTAssertFalse(CodexConfigWriter.featureEnabled(in: ""))
    }

    // MARK: - Helpers

    private func tempCodexDir(configFixture: String? = nil, hooksFixture: String? = nil) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vp-codex-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let configFixture {
            try FileManager.default.copyItem(at: fixture(configFixture), to: dir.appendingPathComponent("config.toml"))
        }
        if let hooksFixture {
            try FileManager.default.copyItem(at: fixture(hooksFixture), to: dir.appendingPathComponent("hooks.json"))
        }
        return dir
    }

    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/codex/\(name)")
    }

    private func hooksObject(_ dir: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: dir.appendingPathComponent("hooks.json"))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (root["hooks"] as? [String: Any]) ?? [:]
    }

    private func innerHooks(in hooks: [String: Any], event: String) -> [[String: Any]] {
        let groups = (hooks[event] as? [[String: Any]]) ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
    }

    private func featureEnabled(_ toml: String, key: String) -> Bool {
        // crude but sufficient: a `key = true` line exists after the [features] header
        guard let featuresRange = toml.range(of: "[features]") else { return false }
        return toml[featuresRange.upperBound...].contains("\(key) = true")
    }
}

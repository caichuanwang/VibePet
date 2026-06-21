import XCTest
@testable import VibePetCore

/// M6-5: `ClaudeCodeConfigWriter` injects VibePet's `PreToolUse`/`Stop`/`Notification`
/// hook entries into `settings.json` pointing at the stable binary, preserving the
/// user's own hooks and other settings, idempotently; uninstall removes only what it
/// wrote.
final class ClaudeCodeConfigWriterTests: XCTestCase {
    private let binaryPath = "/Users/dev/Library/Application Support/VibePet/bin/VibePetHooks"

    func testInjectsManagedHookKeys() throws {
        let url = try emptyConfig()
        let writer = ClaudeCodeConfigWriter(configURL: url, hookBinaryPath: binaryPath)

        try writer.install(arguments: [])

        let hooks = try hooksObject(url)
        for key in ["PreToolUse", "Stop", "Notification"] {
            XCTAssertTrue(commands(in: hooks, key: key).contains { $0.contains(binaryPath) }, "missing VibePet entry for \(key)")
        }
    }

    func testPreservesUserHooksAndSettings() throws {
        let url = try fixtureConfig()
        let writer = ClaudeCodeConfigWriter(configURL: url, hookBinaryPath: binaryPath)

        try writer.install(arguments: [])

        let root = try object(url)
        XCTAssertEqual(root["model"] as? String, "claude-opus-4-8", "non-hook settings must be preserved")
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        // User's PreToolUse entry survives alongside VibePet's.
        XCTAssertTrue(commands(in: hooks, key: "PreToolUse").contains("/usr/local/bin/user-audit"))
        XCTAssertTrue(commands(in: hooks, key: "PreToolUse").contains { $0.contains(binaryPath) })
        // A hook key VibePet does not manage is untouched.
        XCTAssertEqual(commands(in: hooks, key: "PostToolUse"), ["/usr/local/bin/user-postlog"])
    }

    func testInstallIsIdempotent() throws {
        let url = try emptyConfig()
        let writer = ClaudeCodeConfigWriter(configURL: url, hookBinaryPath: binaryPath)

        try writer.install(arguments: [])
        try writer.install(arguments: [])

        let hooks = try hooksObject(url)
        let vibePetEntries = commands(in: hooks, key: "PreToolUse").filter { $0.contains(binaryPath) }
        XCTAssertEqual(vibePetEntries.count, 1, "re-install must not duplicate the VibePet entry")
    }

    func testPreToolUseCarriesDecisionTimeoutButOthersDoNot() throws {
        let url = try emptyConfig()
        let writer = ClaudeCodeConfigWriter(configURL: url, hookBinaryPath: binaryPath)

        try writer.install(arguments: [])

        let hooks = try hooksObject(url)
        XCTAssertEqual(
            vibePetTimeout(in: hooks, key: "PreToolUse"),
            ClaudeCodeConfigWriter.managedDecisionTimeout,
            "PreToolUse must set a timeout larger than the App countdown so Claude doesn't preempt approval"
        )
        XCTAssertNil(vibePetTimeout(in: hooks, key: "Stop"), "fire-and-forget hooks need no timeout")
        XCTAssertNil(vibePetTimeout(in: hooks, key: "Notification"))
    }

    func testUninstallRemovesOnlyVibePetEntries() throws {
        let url = try fixtureConfig()
        let writer = ClaudeCodeConfigWriter(configURL: url, hookBinaryPath: binaryPath)
        try writer.install(arguments: [])

        try writer.uninstall()

        let root = try object(url)
        XCTAssertEqual(root["model"] as? String, "claude-opus-4-8")
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertEqual(commands(in: hooks, key: "PreToolUse"), ["/usr/local/bin/user-audit"], "user hook must remain")
        XCTAssertEqual(commands(in: hooks, key: "PostToolUse"), ["/usr/local/bin/user-postlog"])
        XCTAssertTrue(commands(in: hooks, key: "Stop").isEmpty, "VibePet-only key is cleared")
        XCTAssertTrue(commands(in: hooks, key: "Notification").isEmpty)
    }

    // MARK: - Helpers

    private func emptyConfig() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vp-claude-\(UUID().uuidString.prefix(8))", isDirectory: true)
            .appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }

    private func fixtureConfig() throws -> URL {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/claude/settings-with-user-hooks.json")
        let url = try emptyConfig() // creates the parent dir; no file yet
        try FileManager.default.copyItem(at: source, to: url)
        return url
    }

    private func object(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func hooksObject(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(try object(url)["hooks"] as? [String: Any])
    }

    /// All `command` strings registered under a hook key.
    private func commands(in hooks: [String: Any], key: String) -> [String] {
        let groups = (hooks[key] as? [[String: Any]]) ?? []
        return groups.flatMap { group in
            ((group["hooks"] as? [[String: Any]]) ?? []).compactMap { $0["command"] as? String }
        }
    }

    /// The `timeout` on VibePet's command hook under a key, or nil if absent.
    private func vibePetTimeout(in hooks: [String: Any], key: String) -> Int? {
        let groups = (hooks[key] as? [[String: Any]]) ?? []
        for group in groups {
            for hook in (group["hooks"] as? [[String: Any]]) ?? [] where (hook["command"] as? String)?.contains(binaryPath) == true {
                return hook["timeout"] as? Int
            }
        }
        return nil
    }
}

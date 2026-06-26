import XCTest
@testable import VibePetCore

/// M6-5: `ClaudeCodeConfigWriter` injects VibePet's decision and lifecycle hook
/// entries into `settings.json` pointing at the stable binary, preserving the user's
/// own hooks and other settings, idempotently; uninstall removes only what it wrote.
final class ClaudeCodeConfigWriterTests: XCTestCase {
    private let binaryPath = "/Users/dev/Library/Application Support/VibePet/bin/VibePetHooks"
    private let managedHookKeys = [
        "PreToolUse",
        "Stop",
        "Notification",
        "SessionStart",
        "UserPromptSubmit",
        "PostToolUse",
        "SubagentStart",
        "SubagentStop",
        "SessionEnd",
        "StopFailure",
        "PermissionDenied",
        "PreCompact",
    ]

    func testInjectsManagedHookKeys() throws {
        let url = try emptyConfig()
        let writer = ClaudeCodeConfigWriter(configURL: url, hookBinaryPath: binaryPath)

        try writer.install(arguments: [])

        let hooks = try hooksObject(url)
        XCTAssertEqual(writer.managedHookKeys, managedHookKeys)
        for key in managedHookKeys {
            XCTAssertTrue(commands(in: hooks, key: key).contains { $0.contains(binaryPath) }, "missing VibePet entry for \(key)")
        }
    }

    func testQuotesBinaryPathSoSpacesSurviveShellExecution() throws {
        // Claude Code runs each command via `/bin/sh -c`; an unquoted path containing
        // spaces (`Application Support`) would split and fail with "No such file".
        let url = try emptyConfig()
        let writer = ClaudeCodeConfigWriter(configURL: url, hookBinaryPath: binaryPath)

        try writer.install(arguments: [])

        let hooks = try hooksObject(url)
        for key in managedHookKeys {
            let command = try XCTUnwrap(commands(in: hooks, key: key).first { $0.contains(binaryPath) })
            XCTAssertTrue(command.contains("'\(binaryPath)'"), "binary path must be single-quoted for \(key); got: \(command)")
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
        // User's PostToolUse survives alongside the new lifecycle entry.
        let postToolUseCommands = commands(in: hooks, key: "PostToolUse")
        XCTAssertEqual(postToolUseCommands.count, 2)
        XCTAssertEqual(postToolUseCommands.first, "/usr/local/bin/user-postlog")
        XCTAssertTrue(postToolUseCommands[1].contains(binaryPath))
    }

    func testInstallIsIdempotent() throws {
        let url = try emptyConfig()
        let writer = ClaudeCodeConfigWriter(configURL: url, hookBinaryPath: binaryPath)

        try writer.install(arguments: [])
        try writer.install(arguments: [])

        let hooks = try hooksObject(url)
        for key in managedHookKeys {
            let vibePetEntries = commands(in: hooks, key: key).filter { $0.contains(binaryPath) }
            XCTAssertEqual(vibePetEntries.count, 1, "re-install must not duplicate the VibePet entry for \(key)")
        }
    }

    func testPreToolUseCarriesFiniteDecisionTimeoutButOthersDoNot() throws {
        let url = try emptyConfig()
        let writer = ClaudeCodeConfigWriter(configURL: url, hookBinaryPath: binaryPath)

        try writer.install(arguments: [])

        let hooks = try hooksObject(url)
        let preToolUseTimeout = try XCTUnwrap(vibePetTimeout(in: hooks, key: "PreToolUse"))
        XCTAssertEqual(preToolUseTimeout, ClaudeCodeConfigWriter.managedDecisionTimeout)
        XCTAssertGreaterThan(preToolUseTimeout, 0, "PreToolUse timeout is the finite tool-side fail-open backstop")
        for key in managedHookKeys where key != "PreToolUse" {
            XCTAssertNil(vibePetTimeout(in: hooks, key: key), "\(key) is fire-and-forget and should not set a timeout")
        }
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
        for key in managedHookKeys where key != "PreToolUse" && key != "PostToolUse" {
            XCTAssertTrue(commands(in: hooks, key: key).isEmpty, "VibePet-only key is cleared: \(key)")
        }
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

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

    func testInstallDoesNotWritePostToolUseHook() throws {
        let dir = try tempCodexDir()
        let writer = CodexConfigWriter(codexDirectory: dir, hookBinaryPath: binaryPath)

        try writer.install(arguments: ["--tool", "codex"])

        let hooks = try hooksObject(dir)
        XCTAssertTrue(innerHooks(in: hooks, event: "PostToolUse").isEmpty)
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
        XCTAssertTrue(innerHooks(in: hooks, event: "PostToolUse").isEmpty, "PostToolUse should not be registered for status-only bubbles")
    }

    func testInstallRemovesLegacyManagedPostToolUseHook() throws {
        let dir = try tempCodexDir()
        let hooksURL = dir.appendingPathComponent("hooks.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("""
        {
          "hooks": {
            "PostToolUse": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "'\(binaryPath)' --tool codex",
                    "timeout": 45,
                    "statusMessage": "Managed by VibePet"
                  }
                ]
              }
            ]
          }
        }
        """.utf8).write(to: hooksURL)
        let writer = CodexConfigWriter(codexDirectory: dir, hookBinaryPath: binaryPath)

        try writer.install(arguments: ["--tool", "codex"])

        let hooks = try hooksObject(dir)
        XCTAssertTrue(innerHooks(in: hooks, event: "PostToolUse").isEmpty)
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

    func testInstallAndUninstallPreserveUserHookSharingManagedMatcherGroup() throws {
        let dir = try tempCodexDir()
        let hooksURL = dir.appendingPathComponent("hooks.json")
        try Data("""
        {
          "hooks": {
            "PermissionRequest": [
              {
                "matcher": "shared",
                "hooks": [
                  {
                    "type": "command",
                    "command": "'\(binaryPath)' --tool codex",
                    "statusMessage": "Managed by VibePet"
                  },
                  {
                    "type": "command",
                    "command": "/usr/local/bin/user-codex-hook"
                  }
                ]
              }
            ]
          }
        }
        """.utf8).write(to: hooksURL)
        let writer = CodexConfigWriter(codexDirectory: dir, hookBinaryPath: binaryPath)

        try writer.install(arguments: ["--tool", "codex"])
        var hooks = try hooksObject(dir)
        XCTAssertTrue(innerHooks(in: hooks, event: "PermissionRequest").contains {
            ($0["command"] as? String) == "/usr/local/bin/user-codex-hook"
        })

        try writer.uninstall()
        hooks = try hooksObject(dir)
        XCTAssertEqual(
            innerHooks(in: hooks, event: "PermissionRequest").compactMap { $0["command"] as? String },
            ["/usr/local/bin/user-codex-hook"]
        )
    }

    func testMutationRejectsUncertainHookShapesWithoutChangingBytes() throws {
        let payloads = [
            #"{"hooks":"custom"}"#,
            #"{"hooks":{"PermissionRequest":{"hooks":[]}}}"#,
            #"{"hooks":{"PermissionRequest":[{"hooks":"custom"}]}}"#,
        ]

        for payload in payloads {
            for mutate in [
                { (writer: CodexConfigWriter) in try writer.install(arguments: ["--tool", "codex"]) },
                { (writer: CodexConfigWriter) in try writer.uninstall() },
            ] {
                let dir = try tempCodexDir()
                let hooksURL = dir.appendingPathComponent("hooks.json")
                let configURL = dir.appendingPathComponent("config.toml")
                let originalHooks = Data(payload.utf8)
                let originalConfig = Data("[features]\nhooks = true\n".utf8)
                try originalHooks.write(to: hooksURL)
                try originalConfig.write(to: configURL)
                let writer = CodexConfigWriter(codexDirectory: dir, hookBinaryPath: binaryPath)

                XCTAssertThrowsError(try mutate(writer), "payload: \(payload)")
                XCTAssertEqual(try Data(contentsOf: hooksURL), originalHooks, "payload: \(payload)")
                XCTAssertEqual(try Data(contentsOf: configURL), originalConfig, "payload: \(payload)")
            }
        }
    }

    func testUninstallPreservesUnrelatedTopLevelHooksFileFields() throws {
        let dir = try tempCodexDir()
        let writer = CodexConfigWriter(codexDirectory: dir, hookBinaryPath: binaryPath)
        try writer.install(arguments: ["--tool", "codex"])
        let hooksURL = dir.appendingPathComponent("hooks.json")
        var root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: hooksURL)) as? [String: Any]
        )
        root["version"] = 1
        try JSONSerialization.data(withJSONObject: root).write(to: hooksURL)

        try writer.uninstall()

        XCTAssertTrue(FileManager.default.fileExists(atPath: hooksURL.path))
        let remaining = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: hooksURL)) as? [String: Any]
        )
        XCTAssertEqual(remaining["version"] as? Int, 1)
        XCTAssertNil(remaining["hooks"])
    }

    func testExactExecutableOwnershipHandlesApostropheAndPreservesWrapper() throws {
        let apostrophePath = "/Users/O'Brien/Library/Application Support/VibePet/bin/VibePetHooks"
        let dir = try tempCodexDir()
        let hooksURL = dir.appendingPathComponent("hooks.json")
        let wrapper = "/usr/local/bin/wrapper '\(apostrophePath)'"
        try Data("""
        {
          "hooks": {
            "PermissionRequest": [
              { "hooks": [ { "type": "command", "command": "\(wrapper)" } ] }
            ]
          }
        }
        """.utf8).write(to: hooksURL)
        let writer = CodexConfigWriter(codexDirectory: dir, hookBinaryPath: apostrophePath)

        try writer.install(arguments: ["--tool", "codex"])
        try writer.install(arguments: ["--tool", "codex"])

        var hooks = try hooksObject(dir)
        let installedCommands = innerHooks(in: hooks, event: "PermissionRequest")
            .compactMap { $0["command"] as? String }
        XCTAssertEqual(installedCommands.filter { $0 == wrapper }, [wrapper])
        XCTAssertEqual(installedCommands.filter { $0 != wrapper }.count, 1)

        try writer.uninstall()

        hooks = try hooksObject(dir)
        XCTAssertEqual(
            innerHooks(in: hooks, event: "PermissionRequest").compactMap { $0["command"] as? String },
            [wrapper]
        )
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

    func testUninstallWithoutOwnershipReceiptPreservesSharedFeatureFlag() throws {
        let dir = try tempCodexDir()
        let writer = CodexConfigWriter(codexDirectory: dir, hookBinaryPath: binaryPath)
        try writer.install(arguments: ["--tool", "codex"])

        try writer.uninstall()

        let toml = try String(contentsOf: dir.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(featureEnabled(toml, key: "hooks"), "unknown ownership must preserve the shared feature")
    }

    func testInstallPreservesMixedPreexistingFeatureKeys() throws {
        let dir = try tempCodexDir()
        try "[features]\ncodex_hooks = true\nhooks = true\n".write(
            to: dir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8
        )
        let writer = CodexConfigWriter(codexDirectory: dir, hookBinaryPath: binaryPath)

        try writer.install(arguments: ["--tool", "codex"])

        let lines = try String(contentsOf: dir.appendingPathComponent("config.toml"), encoding: .utf8)
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertTrue(lines.contains("hooks = true"), "modern key enabled")
        XCTAssertTrue(lines.contains("codex_hooks = true"), "user-owned legacy key preserved")
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

    func testUninstallPreservesPreexistingMixedFeatureKeys() throws {
        let dir = try tempCodexDir()
        try "[features]\nhooks = true\ncodex_hooks = true\n".write(
            to: dir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8
        )
        let writer = CodexConfigWriter(codexDirectory: dir, hookBinaryPath: binaryPath)
        let receipt = try writer.installWithReceipt(arguments: ["--tool", "codex"])

        try writer.uninstall(receipt: receipt)

        let toml = try String(contentsOf: dir.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(featureEnabled(toml, key: "hooks"), "preexisting modern feature is user-owned")
        XCTAssertTrue(featureEnabled(toml, key: "codex_hooks"), "preexisting legacy feature is user-owned")
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

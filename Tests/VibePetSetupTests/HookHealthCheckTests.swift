import XCTest
@testable import VibePetCore

/// Deep, read-only config-drift diagnosis for a tool's hook integration: missing /
/// non-executable binary, malformed JSON, stale command path, removed hook, disabled
/// Codex feature flag, and coexisting third-party hooks (info).
final class HookHealthCheckTests: XCTestCase {
    func testHealthyClaudeInstall() throws {
        let env = try Env()
        try env.installManagedBinary()
        try env.claudeWriter.install(arguments: [])

        let report = env.checkClaude()

        XCTAssertTrue(report.isHealthy, "freshly installed Claude hooks should be healthy: \(report.issues)")
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testDetectsMissingBinary() throws {
        let env = try Env()
        // Install config (records the managed binary path) but never create the binary.
        try env.claudeWriter.install(arguments: [])

        let report = env.checkClaude()

        XCTAssertFalse(report.isHealthy)
        XCTAssertTrue(report.issues.contains { if case .binaryNotFound = $0 { return true } else { return false } })
        // A staleCommandPath is also expected since the recorded path doesn't exist.
        XCTAssertTrue(report.repairableIssues.allSatisfy(\.isAutoRepairable))
    }

    func testDetectsMalformedJSON() throws {
        let env = try Env()
        try env.installManagedBinary()
        try Data("{ not json".utf8).write(to: env.claudeConfig)

        let report = env.checkClaude()

        XCTAssertTrue(report.issues.contains { if case .configMalformedJSON = $0 { return true } else { return false } })
        XCTAssertTrue(report.errors.contains { !$0.isAutoRepairable }, "malformed user JSON is not auto-repairable")
    }

    func testDetectsStructurallyInvalidClaudeHooksAsNonRepairable() throws {
        let env = try Env()
        try env.installManagedBinary()
        try Data(#"{"hooks":"custom"}"#.utf8).write(to: env.claudeConfig)

        let report = env.checkClaude()

        XCTAssertTrue(report.issues.contains { if case .configMalformedJSON = $0 { return true } else { return false } })
        XCTAssertFalse(report.issues.contains { if case .managedHooksMissing = $0 { return true } else { return false } })
        XCTAssertFalse(report.issues.contains { if case .managedHookKeyMissing = $0 { return true } else { return false } })
        XCTAssertTrue(report.errors.allSatisfy { !$0.isAutoRepairable })
    }

    func testDetectsStructurallyInvalidCodexHooksAsNonRepairable() throws {
        let env = try Env()
        try env.installManagedBinary()
        try FileManager.default.createDirectory(at: env.codexDir, withIntermediateDirectories: true)
        try "[features]\nhooks = true\n".write(to: env.codexConfig, atomically: true, encoding: .utf8)
        try Data(#"{"hooks":{"PermissionRequest":{"hooks":[]}}}"#.utf8)
            .write(to: env.codexDir.appendingPathComponent("hooks.json"))

        let report = HookHealthCheck.check(
            tool: .codex,
            writer: env.codexWriter,
            managedBinaryURL: env.managedBinary,
            recordedInstalled: true
        )

        XCTAssertTrue(report.issues.contains { if case .configMalformedJSON = $0 { return true } else { return false } })
        XCTAssertFalse(report.issues.contains { if case .managedHooksMissing = $0 { return true } else { return false } })
        XCTAssertFalse(report.issues.contains { if case .managedHookKeyMissing = $0 { return true } else { return false } })
        XCTAssertTrue(report.errors.allSatisfy { !$0.isAutoRepairable })
    }

    func testDetectsMissingManagedBinaryWithoutMisclassifyingCommandPath() throws {
        let env = try Env()
        try env.installManagedBinary()
        try env.claudeWriter.install(arguments: [])
        try FileManager.default.removeItem(at: env.managedBinary)

        let report = env.checkClaude()

        XCTAssertTrue(report.issues.contains { if case .binaryNotFound = $0 { return true } else { return false } })
        XCTAssertFalse(report.issues.contains { if case .staleCommandPath = $0 { return true } else { return false } })
    }

    func testDetectsManagedHooksMissing() throws {
        let env = try Env()
        try env.installManagedBinary()
        // Config exists with only a user hook — VibePet's entry was removed by hand.
        try Data(#"{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"/usr/local/bin/audit"}]}]}}"#.utf8)
            .write(to: env.claudeConfig)

        let report = env.checkClaude()

        XCTAssertTrue(report.issues.contains { if case .managedHooksMissing = $0 { return true } else { return false } })
        XCTAssertTrue(report.issues.contains { if case .otherHooksDetected(let names) = $0 { return names.contains("audit") } else { return false } })
    }

    func testDetectsOrphanedInstall() throws {
        // Manifest is gone (recordedInstalled = false) but the config still references
        // VibePet's hook — a lost-manifest drift that must not read as "clean".
        let env = try Env()
        try env.installManagedBinary()
        try env.claudeWriter.install(arguments: [])

        let report = HookHealthCheck.check(
            tool: .claudeCode,
            writer: env.claudeWriter,
            managedBinaryURL: env.managedBinary,
            recordedInstalled: false
        )

        XCTAssertFalse(report.isHealthy)
        XCTAssertTrue(report.issues.contains { if case .orphanedInstall = $0 { return true } else { return false } })
        XCTAssertTrue(report.repairableIssues.contains { if case .orphanedInstall = $0 { return true } else { return false } })
    }

    func testTrulyUninstalledWithNoConfigIsClean() throws {
        // recordedInstalled = false AND no VibePet hook in config → genuinely clean.
        let env = try Env()
        let report = HookHealthCheck.check(
            tool: .claudeCode,
            writer: env.claudeWriter,
            managedBinaryURL: env.managedBinary,
            recordedInstalled: false
        )
        XCTAssertTrue(report.isHealthy)
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testDetectsCodexFeatureDisabled() throws {
        let env = try Env()
        try env.installManagedBinary()
        try env.codexWriter.install(arguments: ["--tool", "codex"])
        // Turn the feature flag off as a hand-edit would.
        try "[features]\nhooks = false\n".write(to: env.codexConfig, atomically: true, encoding: .utf8)

        let report = HookHealthCheck.check(
            tool: .codex,
            writer: env.codexWriter,
            managedBinaryURL: env.managedBinary,
            recordedInstalled: true
        )

        XCTAssertTrue(report.issues.contains { if case .codexFeatureDisabled = $0 { return true } else { return false } })
    }

    func testDetectsMissingCodexConfigAsDisabledFeature() throws {
        let env = try Env()
        try env.installManagedBinary()
        try env.codexWriter.install(arguments: ["--tool", "codex"])
        try FileManager.default.removeItem(at: env.codexConfig)

        let report = HookHealthCheck.check(
            tool: .codex,
            writer: env.codexWriter,
            managedBinaryURL: env.managedBinary,
            recordedInstalled: true
        )

        XCTAssertTrue(report.issues.contains {
            if case .codexFeatureDisabled(configPath: env.codexConfig.path) = $0 { return true }
            return false
        })
    }

    func testRecordedBinaryPathHandlesQuotingAndSpaces() {
        // Codex: shell-quoted path + args.
        XCTAssertEqual(
            HookHealthCheck.recordedBinaryPath(from: "'/Applications/App Support/VibePetHooks' --tool codex"),
            "/Applications/App Support/VibePetHooks"
        )
        // Claude: unquoted, space-containing path, no args.
        XCTAssertEqual(
            HookHealthCheck.recordedBinaryPath(from: "/Users/dev/Library/Application Support/VibePet/bin/VibePetHooks"),
            "/Users/dev/Library/Application Support/VibePet/bin/VibePetHooks"
        )
        XCTAssertEqual(
            HookHealthCheck.recordedBinaryPath(
                from: #"'/Users/O'\''Brien/Library/Application Support/VibePet/bin/VibePetHooks' --tool codex"#
            ),
            "/Users/O'Brien/Library/Application Support/VibePet/bin/VibePetHooks"
        )
    }

    func testWrapperReferencingManagedPathIsNotClassifiedAsVibePetCommand() throws {
        let env = try Env()
        try env.installManagedBinary()
        let wrapper = "/usr/local/bin/wrapper '\(env.managedBinary.path)'"
        try Data("""
        {"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"\(wrapper)"}]}]}}
        """.utf8).write(to: env.claudeConfig)

        let report = HookHealthCheck.check(
            tool: .claudeCode,
            writer: env.claudeWriter,
            managedBinaryURL: env.managedBinary,
            recordedInstalled: false
        )

        XCTAssertFalse(report.issues.contains { if case .orphanedInstall = $0 { return true } else { return false } })
        XCTAssertFalse(report.issues.contains { if case .staleCommandPath = $0 { return true } else { return false } })
        XCTAssertTrue(report.notices.contains {
            if case .otherHooksDetected(let names) = $0 { return names.contains("wrapper") }
            return false
        })
    }

    // MARK: - Harness

    private struct Env {
        let root: URL
        let managedBinary: URL
        let claudeConfig: URL
        let codexDir: URL
        let claudeWriter: ClaudeCodeConfigWriter
        let codexWriter: CodexConfigWriter

        var codexConfig: URL { codexDir.appendingPathComponent("config.toml") }

        init() throws {
            root = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("vp-health-\(UUID().uuidString.prefix(8))", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            managedBinary = root.appendingPathComponent("bin/VibePetHooks", isDirectory: false)
            claudeConfig = root.appendingPathComponent("claude/settings.json", isDirectory: false)
            codexDir = root.appendingPathComponent("codex", isDirectory: true)
            claudeWriter = ClaudeCodeConfigWriter(configURL: claudeConfig, hookBinaryPath: managedBinary.path)
            codexWriter = CodexConfigWriter(codexDirectory: codexDir, hookBinaryPath: managedBinary.path)
            // Tests that hand-write the config (bypassing writer.install) need the dir.
            try FileManager.default.createDirectory(at: claudeConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        func installManagedBinary() throws {
            try FileManager.default.createDirectory(at: managedBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("#!/bin/sh\n".utf8).write(to: managedBinary)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: managedBinary.path)
        }

        func checkClaude() -> HookHealthReport {
            HookHealthCheck.check(
                tool: .claudeCode,
                writer: claudeWriter,
                managedBinaryURL: managedBinary,
                recordedInstalled: true
            )
        }
    }
}

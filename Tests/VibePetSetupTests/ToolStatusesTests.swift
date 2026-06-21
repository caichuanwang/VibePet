import XCTest
@testable import VibePetCore

/// M6-6: the settings page and onboarding step ③ list tools with their detection and
/// install status. `HookInstaller.toolStatuses()` is the pure backbone — detection is
/// "the tool's config/dir is present", status comes from the manifest.
final class ToolStatusesTests: XCTestCase {
    func testReportsDetectionAndStatusPerTool() throws {
        let root = try TempRoot()
        // Claude detected (settings.json present); Codex not detected.
        let claudeConfig = root.url.appendingPathComponent("claude/settings.json")
        try FileManager.default.createDirectory(at: claudeConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: claudeConfig)
        let codexDir = root.url.appendingPathComponent("codex-not-present")

        let installer = HookInstaller(applicationSupportRoot: root.url, writers: [
            ClaudeCodeConfigWriter(configURL: claudeConfig, hookBinaryPath: InstallPaths.hookBinaryURL(applicationSupportRoot: root.url).path),
            CodexConfigWriter(codexDirectory: codexDir, hookBinaryPath: InstallPaths.hookBinaryURL(applicationSupportRoot: root.url).path),
        ])

        let rows = installer.toolStatuses()

        let claude = try XCTUnwrap(rows.first { $0.tool == .claudeCode })
        let codex = try XCTUnwrap(rows.first { $0.tool == .codex })
        XCTAssertTrue(claude.detected, "Claude settings.json present → detected")
        XCTAssertFalse(codex.detected, "Codex dir absent → not detected")
        XCTAssertEqual(claude.status, .notInstalled)
        XCTAssertEqual(codex.status, .notInstalled)
    }

    func testStatusReflectsInstall() throws {
        let root = try TempRoot()
        let claudeConfig = root.url.appendingPathComponent("claude/settings.json")
        let installer = HookInstaller(applicationSupportRoot: root.url, writers: [
            ClaudeCodeConfigWriter(configURL: claudeConfig, hookBinaryPath: InstallPaths.hookBinaryURL(applicationSupportRoot: root.url).path),
        ])
        _ = try installer.install(tool: .claudeCode, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))

        let claude = try XCTUnwrap(installer.toolStatuses().first { $0.tool == .claudeCode })
        XCTAssertTrue(claude.detected)
        XCTAssertEqual(claude.status, .enabled)
    }
}

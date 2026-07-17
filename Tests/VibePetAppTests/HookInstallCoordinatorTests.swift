import XCTest
@testable import VibePetApp
@testable import VibePetCore

/// M6-6: the settings page and onboarding step ③ are backed by `HookInstallCoordinator`.
/// It must report per-tool detection/status, install/uninstall through the Core engine,
/// and surface the Codex `/hooks` trust notice. All writers are path-injected to temp
/// dirs, so this never touches the real ~/.claude or ~/.codex.
@MainActor
final class HookInstallCoordinatorTests: XCTestCase {
    func testRowsReflectDetectionAndInstall() throws {
        let root = try tempDir()
        let claudeConfig = root.appendingPathComponent("claude/settings.json")
        try FileManager.default.createDirectory(at: claudeConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: claudeConfig)
        let codexDir = root.appendingPathComponent("codex-absent")

        let binaryPath = InstallPaths.hookBinaryURL(applicationSupportRoot: root).path
        let installer = HookInstaller(applicationSupportRoot: root, writers: [
            ClaudeCodeConfigWriter(configURL: claudeConfig, hookBinaryPath: binaryPath),
            CodexConfigWriter(codexDirectory: codexDir, hookBinaryPath: binaryPath),
        ])
        let coordinator = HookInstallCoordinator(installer: installer, hookBinarySource: try sourceBinary(in: root))

        XCTAssertEqual(coordinator.rows.first { $0.tool == .claudeCode }?.detected, true)
        XCTAssertEqual(coordinator.rows.first { $0.tool == .codex }?.detected, false)

        coordinator.install(.claudeCode)
        XCTAssertEqual(coordinator.rows.first { $0.tool == .claudeCode }?.status, .enabled)
        XCTAssertNil(coordinator.lastError)
    }

    func testCodexInstallSurfacesHooksTrustNotice() throws {
        let root = try tempDir()
        let codexDir = root.appendingPathComponent("codex")
        let binaryPath = InstallPaths.hookBinaryURL(applicationSupportRoot: root).path
        let installer = HookInstaller(applicationSupportRoot: root, writers: [
            CodexConfigWriter(codexDirectory: codexDir, hookBinaryPath: binaryPath),
        ])
        let coordinator = HookInstallCoordinator(installer: installer, hookBinarySource: try sourceBinary(in: root))

        coordinator.install(.codex)

        let codexRow = try XCTUnwrap(coordinator.rows.first { $0.tool == .codex })
        XCTAssertEqual(codexRow.status, .installedNeedsTrust)
        let notice = try XCTUnwrap(coordinator.notice(for: codexRow))
        XCTAssertTrue((notice.suggestedAction ?? notice.message).contains("/hooks"))
    }

    func testHealthReportAndRepairThroughCoordinator() throws {
        let root = try tempDir()
        let claudeConfig = root.appendingPathComponent("claude/settings.json")
        try FileManager.default.createDirectory(at: claudeConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: claudeConfig)
        let binaryPath = InstallPaths.hookBinaryURL(applicationSupportRoot: root).path
        let installer = HookInstaller(applicationSupportRoot: root, writers: [
            ClaudeCodeConfigWriter(configURL: claudeConfig, hookBinaryPath: binaryPath),
        ])
        let coordinator = HookInstallCoordinator(installer: installer, hookBinarySource: try sourceBinary(in: root))

        coordinator.install(.claudeCode)
        XCTAssertNil(coordinator.healthReport(for: .claudeCode), "healthy install surfaces no diagnostics")

        // Drift: VibePet's hook is hand-removed from settings.json.
        try Data("{}".utf8).write(to: claudeConfig)
        coordinator.refresh()
        let report = try XCTUnwrap(coordinator.healthReport(for: .claudeCode))
        XCTAssertFalse(report.isHealthy)
        XCTAssertFalse(report.repairableIssues.isEmpty)

        coordinator.repair(.claudeCode)
        XCTAssertNil(coordinator.healthReport(for: .claudeCode), "repair clears the drift")
        XCTAssertNil(coordinator.lastError)
    }

    func testRepairableDriftHintPredicate() throws {
        let root = try tempDir()
        let claudeConfig = root.appendingPathComponent("claude/settings.json")
        try FileManager.default.createDirectory(at: claudeConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: claudeConfig)
        let binaryPath = InstallPaths.hookBinaryURL(applicationSupportRoot: root).path
        let installer = HookInstaller(applicationSupportRoot: root, writers: [
            ClaudeCodeConfigWriter(configURL: claudeConfig, hookBinaryPath: binaryPath),
        ])
        let coordinator = HookInstallCoordinator(installer: installer, hookBinarySource: try sourceBinary(in: root))

        coordinator.install(.claudeCode)
        XCTAssertFalse(coordinator.hasRepairableDriftAmongDetected(), "no hint when healthy")

        // Drift: hand-remove VibePet's hook from a detected tool.
        try Data("{}".utf8).write(to: claudeConfig)
        coordinator.refresh()
        XCTAssertTrue(coordinator.hasRepairableDriftAmongDetected(), "hint shows for a detected, repairable drift")

        coordinator.repair(.claudeCode)
        XCTAssertFalse(coordinator.hasRepairableDriftAmongDetected(), "hint clears after repair")
    }

    func testInvalidExplicitBinaryOverrideDoesNotInstallFallback() throws {
        let root = try tempDir()
        let claudeConfig = root.appendingPathComponent("claude/settings.json")
        try FileManager.default.createDirectory(
            at: claudeConfig.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: claudeConfig)
        let stableBinary = InstallPaths.hookBinaryURL(applicationSupportRoot: root)
        let installer = HookInstaller(applicationSupportRoot: root, writers: [
            ClaudeCodeConfigWriter(configURL: claudeConfig, hookBinaryPath: stableBinary.path),
        ])
        let invalidOverride = root.appendingPathComponent("invalid-override")
        try Data("not executable".utf8).write(to: invalidOverride)
        let coordinator = HookInstallCoordinator(
            installer: installer,
            hookBinaryLocation: .invalidExplicitOverride(invalidOverride)
        )

        coordinator.install(.claudeCode)

        XCTAssertNotNil(coordinator.lastError)
        XCTAssertTrue(coordinator.lastError?.message.contains(HooksBinaryLocator.environmentKey) == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stableBinary.path))
    }

    // MARK: - Helpers

    private func tempDir() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vp-coord-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sourceBinary(in root: URL) throws -> URL {
        let url = root.appendingPathComponent("VibePetHooks-src", isDirectory: false)
        try Data("hooks".utf8).write(to: url)
        return url
    }
}

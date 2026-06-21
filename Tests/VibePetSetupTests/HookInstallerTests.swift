import XCTest
@testable import VibePetCore

/// M6-5: `HookInstaller` orchestrates binary copy + backup + config write + manifest
/// for each tool, idempotently and reversibly. Status distinguishes notInstalled /
/// installedNeedsTrust / enabled / outdated. Codex starts needs-trust; Claude is
/// active once written.
final class HookInstallerTests: XCTestCase {
    func testInstallWritesBinaryConfigAndManifest() throws {
        let root = try TempRoot()
        let configURL = root.url.appendingPathComponent("claude/settings.json")
        let installer = HookInstaller(applicationSupportRoot: root.url, writers: [
            ClaudeCodeConfigWriter(configURL: configURL, hookBinaryPath: InstallPaths.hookBinaryURL(applicationSupportRoot: root.url).path),
        ])

        let record = try installer.install(tool: .claudeCode, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))

        XCTAssertTrue(record.installed)
        XCTAssertEqual(record.activationState, .trustedActive)
        XCTAssertEqual(record.writtenHooks, ["PreToolUse", "Stop", "Notification"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: InstallPaths.hookBinaryURL(applicationSupportRoot: root.url).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
        XCTAssertEqual(installer.status(tool: .claudeCode), .enabled)
    }

    func testInstallIsIdempotent() throws {
        let root = try TempRoot()
        let configURL = root.url.appendingPathComponent("claude/settings.json")
        let installer = HookInstaller(applicationSupportRoot: root.url, writers: [
            ClaudeCodeConfigWriter(configURL: configURL, hookBinaryPath: InstallPaths.hookBinaryURL(applicationSupportRoot: root.url).path),
        ])

        _ = try installer.install(tool: .claudeCode, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))
        _ = try installer.install(tool: .claudeCode, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))

        let manifest = InstallManifestStore(applicationSupportRoot: root.url).read()
        XCTAssertEqual(manifest.tools.count, 1)
        XCTAssertEqual(installer.status(tool: .claudeCode), .enabled)
    }

    func testInstallBacksUpExistingConfig() throws {
        let root = try TempRoot()
        let configURL = root.url.appendingPathComponent("claude/settings.json")
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"model":"x"}"#.data(using: .utf8)!.write(to: configURL)

        let installer = HookInstaller(applicationSupportRoot: root.url, writers: [
            ClaudeCodeConfigWriter(configURL: configURL, hookBinaryPath: InstallPaths.hookBinaryURL(applicationSupportRoot: root.url).path),
        ])
        let record = try installer.install(tool: .claudeCode, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))

        let backupPath = try XCTUnwrap(record.backupPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupPath))
        XCTAssertEqual(try String(contentsOfFile: backupPath, encoding: .utf8), #"{"model":"x"}"#)
    }

    func testUninstallRemovesEntriesBinaryAndManifest() throws {
        let root = try TempRoot()
        let configURL = root.url.appendingPathComponent("claude/settings.json")
        let installer = HookInstaller(applicationSupportRoot: root.url, writers: [
            ClaudeCodeConfigWriter(configURL: configURL, hookBinaryPath: InstallPaths.hookBinaryURL(applicationSupportRoot: root.url).path),
        ])
        _ = try installer.install(tool: .claudeCode, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))

        try installer.uninstall(tool: .claudeCode)

        XCTAssertEqual(installer.status(tool: .claudeCode), .notInstalled)
        XCTAssertTrue(InstallManifestStore(applicationSupportRoot: root.url).read().tools.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: InstallPaths.hookBinaryURL(applicationSupportRoot: root.url).path), "binary removed when no tools remain")
    }

    func testStatusOutdatedWhenBinaryBehind() throws {
        let root = try TempRoot()
        let configURL = root.url.appendingPathComponent("claude/settings.json")
        let writer = ClaudeCodeConfigWriter(configURL: configURL, hookBinaryPath: InstallPaths.hookBinaryURL(applicationSupportRoot: root.url).path)
        let installer = HookInstaller(applicationSupportRoot: root.url, writers: [writer], currentBinaryVersion: "0.1.0")
        _ = try installer.install(tool: .claudeCode, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))

        // A newer app build sees the older installed binary as outdated.
        let newer = HookInstaller(applicationSupportRoot: root.url, writers: [writer], currentBinaryVersion: "0.2.0")
        XCTAssertEqual(newer.status(tool: .claudeCode), .outdated)
    }

    func testRepairFixesDriftThatIdempotentInstallCannot() throws {
        let root = try TempRoot()
        let configURL = root.url.appendingPathComponent("claude/settings.json")
        let installer = HookInstaller(applicationSupportRoot: root.url, writers: [
            ClaudeCodeConfigWriter(configURL: configURL, hookBinaryPath: InstallPaths.hookBinaryURL(applicationSupportRoot: root.url).path),
        ])
        _ = try installer.install(tool: .claudeCode, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))
        XCTAssertEqual(installer.health(tool: .claudeCode)?.isHealthy, true)

        // Drift: the user hand-edits VibePet's hook out of settings.json.
        try Data("{}".utf8).write(to: configURL)
        XCTAssertEqual(installer.health(tool: .claudeCode)?.isHealthy, false)

        // Idempotent install can't fix it — the manifest still says "installed".
        _ = try installer.install(tool: .claudeCode, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))
        XCTAssertEqual(installer.health(tool: .claudeCode)?.isHealthy, false, "install short-circuits on a recorded install")

        // Repair forces the rewrite.
        _ = try installer.repair(tool: .claudeCode, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))
        XCTAssertEqual(installer.health(tool: .claudeCode)?.isHealthy, true)
        XCTAssertEqual(installer.status(tool: .claudeCode), .enabled)
    }

    func testRepairPreservesActivationState() throws {
        let root = try TempRoot()
        let installer = HookInstaller(applicationSupportRoot: root.url, writers: [
            FakeConfigWriter(tool: .codex, configURL: root.url.appendingPathComponent("codex.marker")),
        ])
        _ = try installer.install(tool: .codex, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))
        XCTAssertTrue(InstallManifestStore(applicationSupportRoot: root.url).markTrustedActive(tool: .codex))
        XCTAssertEqual(installer.status(tool: .codex), .enabled)

        _ = try installer.repair(tool: .codex, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))

        XCTAssertEqual(installer.status(tool: .codex), .enabled, "repair must not push a trusted Codex back to needs-trust")
    }

    func testCodexInstallStartsNeedsTrust() throws {
        let root = try TempRoot()
        let installer = HookInstaller(applicationSupportRoot: root.url, writers: [
            FakeConfigWriter(tool: .codex, configURL: root.url.appendingPathComponent("codex.marker")),
        ])

        let record = try installer.install(tool: .codex, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))

        XCTAssertEqual(record.activationState, .installedNeedsTrust)
        XCTAssertEqual(installer.status(tool: .codex), .installedNeedsTrust)
    }
}

/// A minimal `ToolConfigWriter` for engine tests (stands in for the real Codex TOML
/// writer): records install/uninstall by touching a marker file.
struct FakeConfigWriter: ToolConfigWriter {
    let tool: ToolKind
    let configURL: URL
    var managedHookKeys: [String] { ["PermissionRequest"] }

    func install(arguments: [String]) throws {
        try Data("installed \(arguments.joined(separator: " "))".utf8).write(to: configURL)
    }

    func uninstall() throws {
        try? FileManager.default.removeItem(at: configURL)
    }
}

import XCTest
@testable import VibePetCore

/// M6-5: `HookInstaller` orchestrates binary copy + backup + config write + manifest
/// for each tool, idempotently and reversibly. Status distinguishes notInstalled /
/// installedNeedsTrust / enabled / outdated. Codex starts needs-trust; Claude is
/// active once written.
final class HookInstallerTests: XCTestCase {
    private let claudeManagedHookKeys = [
        "PreToolUse",
        "PermissionRequest",
        "Stop",
        "Notification",
        "SessionStart",
        "UserPromptSubmit",
        "SubagentStart",
        "SubagentStop",
        "SessionEnd",
        "StopFailure",
        "PermissionDenied",
        "PreCompact",
    ]

    func testInstallWritesBinaryConfigAndManifest() throws {
        let root = try TempRoot()
        let configURL = root.url.appendingPathComponent("claude/settings.json")
        let installer = HookInstaller(applicationSupportRoot: root.url, writers: [
            ClaudeCodeConfigWriter(configURL: configURL, hookBinaryPath: InstallPaths.hookBinaryURL(applicationSupportRoot: root.url).path),
        ])

        let record = try installer.install(tool: .claudeCode, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))

        XCTAssertTrue(record.installed)
        XCTAssertEqual(record.activationState, .trustedActive)
        XCTAssertEqual(record.writtenHooks, claudeManagedHookKeys)
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
        let manifestURL = InstallManifestStore(applicationSupportRoot: root.url).manifestURL

        _ = try installer.install(tool: .claudeCode, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))
        let configAfterFirstInstall = try Data(contentsOf: configURL)
        let manifestAfterFirstInstall = try Data(contentsOf: manifestURL)
        _ = try installer.install(tool: .claudeCode, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))

        let manifest = InstallManifestStore(applicationSupportRoot: root.url).read()
        XCTAssertEqual(manifest.tools.count, 1)
        XCTAssertEqual(installer.status(tool: .claudeCode), .enabled)
        XCTAssertEqual(try Data(contentsOf: configURL), configAfterFirstInstall)
        XCTAssertEqual(try Data(contentsOf: manifestURL), manifestAfterFirstInstall)
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

    func testStatusOutdatedWhenManagedHookSetChangedAndInstallRewrites() throws {
        let root = try TempRoot()
        let codexDir = root.url.appendingPathComponent("codex", isDirectory: true)
        let binaryPath = InstallPaths.hookBinaryURL(applicationSupportRoot: root.url).path
        let writer = CodexConfigWriter(codexDirectory: codexDir, hookBinaryPath: binaryPath)
        let installer = HookInstaller(applicationSupportRoot: root.url, writers: [writer])

        _ = try installer.install(tool: .codex, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))

        let store = InstallManifestStore(applicationSupportRoot: root.url)
        var manifest = store.read()
        manifest.tools[ToolKind.codex.rawValue]?.writtenHooks = ["PermissionRequest", "Stop", "SessionStart", "UserPromptSubmit", "PostToolUse"]
        try store.write(manifest)

        XCTAssertEqual(installer.status(tool: .codex), .outdated)

        let record = try installer.install(tool: .codex, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))
        XCTAssertEqual(record.writtenHooks, writer.managedHookKeys)

        let hooksData = try Data(contentsOf: codexDir.appendingPathComponent("hooks.json"))
        let rootObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: hooksData) as? [String: Any])
        let hooks = try XCTUnwrap(rootObject["hooks"] as? [String: Any])
        XCTAssertNil(hooks["PostToolUse"])
        XCTAssertEqual(installer.status(tool: .codex), .installedNeedsTrust)
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

        // Reinstall reconciles drift even when the manifest still says installed.
        _ = try installer.install(tool: .claudeCode, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))
        XCTAssertEqual(installer.health(tool: .claudeCode)?.isHealthy, true, "install reconciles current disk state")

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

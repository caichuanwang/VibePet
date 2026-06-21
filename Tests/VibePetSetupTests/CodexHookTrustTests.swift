import XCTest
@testable import VibePetCore

/// M6-5a: Codex hooks are written as `installedNeedsTrust` and only become
/// `trustedActive` once VibePet receives a real Codex hook event (the runtime
/// evidence the user trusted them in `/hooks`). Without that evidence VibePet must
/// not claim "enabled". Claude Code has no trust gate.
final class CodexHookTrustTests: XCTestCase {
    func testCodexTransitionsToTrustedActiveOnRealEvent() throws {
        let root = try TempRoot()
        let installer = HookInstaller(applicationSupportRoot: root.url, writers: [
            FakeConfigWriter(tool: .codex, configURL: root.url.appendingPathComponent("codex.marker")),
        ])
        _ = try installer.install(tool: .codex, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))
        XCTAssertEqual(installer.status(tool: .codex), .installedNeedsTrust)

        let store = InstallManifestStore(applicationSupportRoot: root.url)
        XCTAssertTrue(store.markTrustedActive(tool: .codex), "first real event activates trust")

        XCTAssertEqual(installer.status(tool: .codex), .enabled)
    }

    func testMarkTrustedActiveIsIdempotent() throws {
        let root = try TempRoot()
        let installer = HookInstaller(applicationSupportRoot: root.url, writers: [
            FakeConfigWriter(tool: .codex, configURL: root.url.appendingPathComponent("codex.marker")),
        ])
        _ = try installer.install(tool: .codex, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))
        let store = InstallManifestStore(applicationSupportRoot: root.url)

        XCTAssertTrue(store.markTrustedActive(tool: .codex))
        XCTAssertFalse(store.markTrustedActive(tool: .codex), "already active → no change")
    }

    func testMarkTrustedActiveNoOpWhenNotInstalled() throws {
        let root = try TempRoot()
        let store = InstallManifestStore(applicationSupportRoot: root.url)
        XCTAssertFalse(store.markTrustedActive(tool: .codex))
    }

    func testClaudeIsActiveWithoutTrustStep() throws {
        let root = try TempRoot()
        let configURL = root.url.appendingPathComponent("claude/settings.json")
        let installer = HookInstaller(applicationSupportRoot: root.url, writers: [
            ClaudeCodeConfigWriter(configURL: configURL, hookBinaryPath: InstallPaths.hookBinaryURL(applicationSupportRoot: root.url).path),
        ])
        _ = try installer.install(tool: .claudeCode, hookBinarySource: try root.makeSourceBinary(contents: "hooks"))
        XCTAssertEqual(installer.status(tool: .claudeCode), .enabled)
    }
}

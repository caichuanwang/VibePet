import XCTest
@testable import VibePetCore

/// M6-5: the install manifest is the single source of truth for what VibePet wrote
/// to each tool (so uninstall is precise and install is idempotent). It round-trips
/// as JSON and returns an empty default when absent.
final class InstallManifestTests: XCTestCase {
    private let claudeManagedHookKeys = [
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

    func testDefaultWhenMissing() throws {
        let root = try TempRoot()
        let store = InstallManifestStore(applicationSupportRoot: root.url)
        let manifest = store.read()
        XCTAssertEqual(manifest.version, 1)
        XCTAssertNil(manifest.hookBinaryVersion)
        XCTAssertTrue(manifest.tools.isEmpty)
    }

    func testRoundTrips() throws {
        let root = try TempRoot()
        let store = InstallManifestStore(applicationSupportRoot: root.url)
        var manifest = InstallManifest()
        manifest.hookBinaryVersion = "0.1.0"
        manifest.tools[ToolKind.claudeCode.rawValue] = ToolInstallRecord(
            installed: true,
            activationState: .trustedActive,
            settingsPath: "~/.claude/settings.json",
            writtenHooks: claudeManagedHookKeys,
            backupPath: "backups/settings.json.bak"
        )

        try store.write(manifest)
        let reloaded = store.read()

        XCTAssertEqual(reloaded, manifest)
        XCTAssertEqual(reloaded.tools[ToolKind.claudeCode.rawValue]?.writtenHooks, claudeManagedHookKeys)
    }
}

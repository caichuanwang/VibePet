import XCTest
@testable import VibePetCore

/// M6-7: `ErrorPresenter` maps import / install / trust conditions to a readable
/// message + suggested action (technical design §7). Pure (no AppKit/SwiftUI) so it is
/// unit-testable and shared by the import panel, settings page, and bubbles.
final class ErrorPresenterTests: XCTestCase {
    func testInvalidPetPackageKeepsReadableReason() {
        let presented = ErrorPresenter.present(petAssetError: .invalidPackage("spritesheet must be 1536x1872"))

        XCTAssertFalse(presented.message.isEmpty)
        XCTAssertTrue(presented.message.contains("1536x1872"))
        XCTAssertTrue((presented.suggestedAction ?? "").contains("Codex"))
    }

    func testPetPackageWriteFailureMentionsRetry() {
        let presented = ErrorPresenter.present(petAssetError: .writeFailed("disk full"))

        XCTAssertTrue(presented.message.contains("disk full"))
        XCTAssertTrue((presented.suggestedAction ?? "").contains("重试"))
    }

    func testCodexNeedsTrustGuidesToHooks() throws {
        let presented = try XCTUnwrap(ErrorPresenter.present(installStatus: .installedNeedsTrust, tool: .codex))
        let text = presented.message + " " + (presented.suggestedAction ?? "")
        XCTAssertTrue(text.contains("/hooks"), "should guide the user to Codex /hooks")
    }

    func testEnabledStatusHasNoError() {
        XCTAssertNil(ErrorPresenter.present(installStatus: .enabled, tool: .codex))
        XCTAssertNil(ErrorPresenter.present(installStatus: .notInstalled, tool: .claudeCode))
    }

    func testInstallFailureYieldsCauseAndRollbackHint() {
        struct Boom: Error {}
        let presented = ErrorPresenter.presentInstallFailure(Boom(), tool: .claudeCode)
        XCTAssertFalse(presented.message.isEmpty)
        let action = presented.suggestedAction ?? ""
        XCTAssertTrue(action.contains("备份"), "should mention the config was backed up / can be restored")
    }
}

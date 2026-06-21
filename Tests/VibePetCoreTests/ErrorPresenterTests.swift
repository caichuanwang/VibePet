import XCTest
@testable import VibePetCore

/// M6-7: `ErrorPresenter` maps generation / install / trust conditions to a readable
/// message + suggested action (technical design §7). Pure (no AppKit/SwiftUI) so it is
/// unit-testable and shared by the import panel, settings page, and bubbles.
final class ErrorPresenterTests: XCTestCase {
    func testNoSubjectSuggestsAnotherPhoto() {
        let presented = ErrorPresenter.present(generationError: .noSubject)
        XCTAssertFalse(presented.message.isEmpty)
        let action = presented.suggestedAction ?? ""
        XCTAssertTrue(action.contains("换一张") || action.contains("重试"), "should suggest another photo / retry")
    }

    func testOtherGenerationErrorsHaveReadableMessage() {
        for error in [GenError.encodingFailed, .writeFailed("disk full"), .defaultGeneratorUnavailable("x")] {
            XCTAssertFalse(ErrorPresenter.present(generationError: error).message.isEmpty)
        }
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

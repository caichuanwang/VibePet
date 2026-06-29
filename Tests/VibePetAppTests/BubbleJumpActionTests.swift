import XCTest
@testable import VibePetApp
import VibePetCore

@MainActor
final class BubbleJumpActionTests: XCTestCase {
    func testSpeechBubbleJumpBackInvokesActionOnceWhenTargetExists() {
        let target = JumpTarget(terminalApp: "Terminal", terminalTTY: "/dev/ttys001")
        var jumped: [JumpTarget] = []

        SpeechBubble.jumpBack(from: source(jumpTarget: target)) {
            jumped.append($0)
        }

        XCTAssertEqual(jumped, [target])
    }

    func testApprovalCardJumpBackNoopsWithoutTarget() {
        var jumped: [JumpTarget] = []

        ApprovalCard.jumpBack(from: source(jumpTarget: nil)) {
            jumped.append($0)
        }

        XCTAssertTrue(jumped.isEmpty)
    }

    func testApprovalCardJumpBackInvokesActionOnceWhenTargetExists() {
        let target = JumpTarget(terminalApp: "iTerm", terminalSessionID: "session-1")
        var jumped: [JumpTarget] = []

        ApprovalCard.jumpBack(from: source(jumpTarget: target)) {
            jumped.append($0)
        }

        XCTAssertEqual(jumped, [target])
    }

    func testApprovalBackToTerminalJumpsWithoutResolvingNormalApproval() {
        let target = JumpTarget(terminalApp: "iTerm", terminalSessionID: "session-1")
        var jumped: [JumpTarget] = []

        let response = ApprovalCard.activateBackToTerminal(
            for: approval(requiresTerminal: false),
            source: source(jumpTarget: target)
        ) {
            jumped.append($0)
        }

        XCTAssertEqual(jumped, [target])
        XCTAssertNil(response)
    }

    func testQuestionCardJumpBackInvokesActionOnceWhenTargetExists() {
        let target = JumpTarget(terminalApp: "Ghostty", terminalSessionID: "ghostty-1")
        var jumped: [JumpTarget] = []

        QuestionCard.jumpBack(from: source(jumpTarget: target)) {
            jumped.append($0)
        }

        XCTAssertEqual(jumped, [target])
    }

    func testQuestionBackToTerminalJumpsWithoutResolving() {
        let target = JumpTarget(terminalApp: "Ghostty", terminalSessionID: "ghostty-1")
        var jumped: [JumpTarget] = []

        let response = QuestionCard.activateBackToTerminal(from: source(jumpTarget: target)) {
            jumped.append($0)
        }

        XCTAssertEqual(jumped, [target])
        XCTAssertNil(response)
    }

    func testQuestionSubmitProjectionDoesNotInvokeJump() {
        let target = JumpTarget(terminalApp: "Ghostty", terminalSessionID: "ghostty-1")
        var jumped: [JumpTarget] = []
        var responses: [BridgeResponse] = []

        QuestionCard.activateSubmit(
            answer: QuestionAnswer(answers: ["Database": "SQLite"]),
            onAnswer: { responses.append($0) }
        )
        QuestionCard.jumpBack(from: source(jumpTarget: nil)) {
            jumped.append($0)
        }
        _ = target

        XCTAssertTrue(jumped.isEmpty)
        XCTAssertEqual(responses, [.question(QuestionAnswer(answers: ["Database": "SQLite"]))])
    }

    func testDashboardJumpBackNoopsWithoutTarget() {
        var jumped: [JumpTarget] = []

        SessionDashboardView.jumpBack(to: nil) {
            jumped.append($0)
        }

        XCTAssertTrue(jumped.isEmpty)
    }

    func testDashboardJumpBackInvokesActionOnceWhenTargetExists() {
        let target = JumpTarget(terminalApp: "Ghostty", terminalSessionID: "ghostty-1")
        var jumped: [JumpTarget] = []

        SessionDashboardView.jumpBack(to: target) {
            jumped.append($0)
        }

        XCTAssertEqual(jumped, [target])
    }

    private func source(jumpTarget: JumpTarget?) -> SourceInfo {
        SourceInfo(
            tool: .claudeCode,
            projectName: "VibePet",
            sessionShortId: "a1b2c3",
            cwd: "/tmp/VibePet",
            jumpTarget: jumpTarget
        )
    }

    private func approval(requiresTerminal: Bool) -> ApprovalContent {
        ApprovalContent(
            title: "运行命令",
            risk: .medium,
            preview: .command(text: "swift test"),
            alwaysAllow: nil,
            requiresTerminalApproval: requiresTerminal
        )
    }
}

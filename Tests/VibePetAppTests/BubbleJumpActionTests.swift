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

    func testQuestionCardJumpBackInvokesActionOnceWhenTargetExists() {
        let target = JumpTarget(terminalApp: "Ghostty", terminalSessionID: "ghostty-1")
        var jumped: [JumpTarget] = []

        QuestionCard.jumpBack(from: source(jumpTarget: target)) {
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
}

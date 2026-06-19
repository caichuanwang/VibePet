import XCTest
@testable import VibePetCore

final class PetStateMachineTests: XCTestCase {
    func testCompletionEntersNotify() {
        var machine = PetStateMachine()
        let accepted = machine.receive(.completion(CompletionContent(markdownSummary: "done", isError: false)))

        XCTAssertTrue(accepted)
        XCTAssertEqual(machine.state, .notify)
    }

    func testStatusEntersNotify() {
        var machine = PetStateMachine()
        let accepted = machine.receive(.status(StatusContent(text: "waiting")))

        XCTAssertTrue(accepted)
        XCTAssertEqual(machine.state, .notify)
    }

    func testNotifyReturnsToIdleAfterDismiss() {
        var machine = PetStateMachine()
        machine.receive(.status(StatusContent(text: "waiting")))
        machine.bubbleDismissed()

        XCTAssertEqual(machine.state, .idle)
    }

    func testGreetReturnsToIdleAfterDismiss() {
        var machine = PetStateMachine()
        machine.greet()
        XCTAssertEqual(machine.state, .greet)

        machine.bubbleDismissed()
        XCTAssertEqual(machine.state, .idle)
    }

    func testGreetFinishedReturnsToIdle() {
        var machine = PetStateMachine()
        machine.greet()

        machine.greetFinished()
        XCTAssertEqual(machine.state, .idle)
    }

    func testGreetFinishedDoesNotClobberNotify() {
        var machine = PetStateMachine()
        machine.greet()
        machine.receive(.status(StatusContent(text: "waiting"))) // notification mid-greet

        machine.greetFinished() // late greeting timer firing must not undo notify
        XCTAssertEqual(machine.state, .notify)
    }

    func testResponseBearingContentIsNotHandled() {
        var machine = PetStateMachine()
        let approval = BubbleContent.approval(ApprovalContent(
            title: "run command",
            risk: .high,
            preview: .command(text: "rm -rf build/"),
            alwaysAllow: nil,
            requiresTerminalApproval: false
        ))

        let accepted = machine.receive(approval)

        XCTAssertFalse(accepted)
        XCTAssertEqual(machine.state, .idle)
    }
}

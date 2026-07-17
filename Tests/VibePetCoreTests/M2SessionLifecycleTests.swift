import XCTest
@testable import VibePetCore

final class M2SessionLifecycleTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testDuplicateSessionStartReturnsFalseAndLeavesStateUnchanged() {
        var state = SessionState()
        let event = started(at: base)

        XCTAssertTrue(state.apply(event))
        let once = state
        XCTAssertFalse(state.apply(event))
        XCTAssertEqual(state, once)
    }

    func testStaleStartDoesNotDowngradeWaitingStateButMayEnrichJumpMetadata() {
        var state = SessionState()
        XCTAssertTrue(state.apply(started(
            at: base,
            jumpTarget: JumpTarget(
                terminalApp: "iTerm",
                workingDirectory: "/tmp/project",
                terminalSessionID: "precise-session",
                terminalTTY: "/dev/ttys001"
            )
        )))
        XCTAssertTrue(state.apply(.permissionRequested(
            sessionID: "session",
            timestamp: time(2),
            summary: "Approve command"
        )))

        XCTAssertTrue(state.apply(started(
            at: time(1),
            title: "Stale title",
            summary: "Stale start",
            jumpTarget: JumpTarget(
                terminalApp: "iTerm",
                workspaceName: "workspace",
                paneTitle: "pane",
                workingDirectory: "/different",
                terminalSessionID: "less-authoritative",
                terminalTTY: "/dev/ttys999"
            )
        )))

        let session = tryUnwrap(state.sessionsByID["session"])
        XCTAssertEqual(session.phase, .waitingForApproval)
        XCTAssertEqual(session.summary, "Approve command")
        XCTAssertEqual(session.updatedAt, time(2))
        XCTAssertEqual(session.title, "Project")
        XCTAssertEqual(session.jumpTarget?.workspaceName, "workspace")
        XCTAssertEqual(session.jumpTarget?.paneTitle, "pane")
        XCTAssertEqual(session.jumpTarget?.workingDirectory, "/tmp/project")
        XCTAssertEqual(session.jumpTarget?.terminalSessionID, "precise-session")
        XCTAssertEqual(session.jumpTarget?.terminalTTY, "/dev/ttys001")

        let enriched = state
        XCTAssertFalse(state.apply(started(at: time(1), title: "Still stale", summary: "Ignored")))
        XCTAssertEqual(state, enriched)
    }

    func testNewerDuplicateStartDoesNotDowngradeWaitingOrCompletedState() {
        let transitions: [AgentEvent] = [
            .permissionRequested(sessionID: "session", timestamp: time(1), summary: "Approval"),
            .questionAsked(sessionID: "session", timestamp: time(1), summary: "Question"),
            .sessionCompleted(
                sessionID: "session",
                timestamp: time(1),
                summary: "Turn complete",
                isError: false,
                isSessionEnd: false
            ),
        ]

        for transition in transitions {
            var state = SessionState()
            XCTAssertTrue(state.apply(started(at: base)))
            XCTAssertTrue(state.apply(transition))
            let current = state

            XCTAssertFalse(state.apply(started(
                at: time(2),
                title: "Duplicate start",
                summary: "Must not reset lifecycle"
            )))
            XCTAssertEqual(state, current)
        }
    }

    func testStaleActivityIsNoOpAndDoesNotMoveUpdatedAtBackwards() {
        var state = SessionState()
        XCTAssertTrue(state.apply(started(at: base)))
        XCTAssertTrue(state.apply(.activityUpdated(
            sessionID: "session",
            timestamp: time(3),
            summary: "Newest activity"
        )))
        let newest = state

        XCTAssertFalse(state.apply(.activityUpdated(
            sessionID: "session",
            timestamp: time(2),
            summary: "Stale activity"
        )))
        XCTAssertEqual(state, newest)
        XCTAssertEqual(state.sessionsByID["session"]?.updatedAt, time(3))
        XCTAssertEqual(state.sessionsByID["session"]?.summary, "Newest activity")
    }

    func testNewActivityReopensTurnLevelCompletedSession() {
        var state = SessionState()
        XCTAssertTrue(state.apply(started(at: base)))
        XCTAssertTrue(state.apply(.sessionCompleted(
            sessionID: "session",
            timestamp: time(1),
            summary: "Turn done",
            isError: true,
            isSessionEnd: false
        )))

        XCTAssertTrue(state.apply(.activityUpdated(
            sessionID: "session",
            timestamp: time(2),
            summary: "Next turn"
        )))

        let session = tryUnwrap(state.sessionsByID["session"])
        XCTAssertEqual(session.phase, .running)
        XCTAssertEqual(session.summary, "Next turn")
        XCTAssertFalse(session.isError)
        XCTAssertFalse(session.isSessionEnded)
        XCTAssertEqual(session.updatedAt, time(2))
    }

    func testLateNativeSessionEndMergesTerminalBitsWithoutOverwritingNewerContent() {
        var state = SessionState()
        XCTAssertTrue(state.apply(started(at: base)))
        XCTAssertTrue(state.apply(.sessionCompleted(
            sessionID: "session",
            timestamp: time(4),
            summary: "Newer failed turn",
            isError: true,
            isSessionEnd: false
        )))

        XCTAssertTrue(state.apply(.sessionCompleted(
            sessionID: "session",
            timestamp: time(2),
            summary: "Late native end",
            isError: false,
            isSessionEnd: true
        )))

        let session = tryUnwrap(state.sessionsByID["session"])
        XCTAssertEqual(session.phase, .completed)
        XCTAssertTrue(session.isSessionEnded)
        XCTAssertFalse(session.isProcessAlive)
        XCTAssertEqual(session.processNotSeenCount, 2)
        XCTAssertEqual(session.summary, "Newer failed turn")
        XCTAssertTrue(session.isError)
        XCTAssertEqual(session.updatedAt, time(4))
    }

    func testEndedSessionCannotBeRevivedByActivityOrStart() {
        var state = SessionState()
        XCTAssertTrue(state.apply(started(at: base)))
        XCTAssertTrue(state.apply(.sessionCompleted(
            sessionID: "session",
            timestamp: time(1),
            summary: "Ended",
            isError: false,
            isSessionEnd: true
        )))
        let ended = state

        XCTAssertFalse(state.apply(.activityUpdated(
            sessionID: "session",
            timestamp: time(2),
            summary: "Should not revive"
        )))
        XCTAssertFalse(state.apply(started(
            at: time(3),
            title: "Restarted",
            summary: "Should not restart"
        )))
        XCTAssertEqual(state, ended)
        XCTAssertEqual(state.sessionsByID["session"]?.phase, .completed)
        XCTAssertTrue(state.sessionsByID["session"]?.isSessionEnded == true)
    }

    func testEqualTimestampPhasePriorityIsDeterministic() {
        let timestamp = time(1)
        let events: [AgentEvent] = [
            .sessionCompleted(
                sessionID: "session",
                timestamp: timestamp,
                summary: "Completed",
                isError: false,
                isSessionEnd: false
            ),
            .permissionRequested(
                sessionID: "session",
                timestamp: timestamp,
                summary: "Approval"
            ),
            .questionAsked(
                sessionID: "session",
                timestamp: timestamp,
                summary: "Question"
            ),
        ]

        var forward = SessionState()
        XCTAssertTrue(forward.apply(started(at: base)))
        for event in events {
            _ = forward.apply(event)
        }

        var reverse = SessionState()
        XCTAssertTrue(reverse.apply(started(at: base)))
        for event in events.reversed() {
            _ = reverse.apply(event)
        }

        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(forward.sessionsByID["session"]?.phase, .waitingForAnswer)
        XCTAssertEqual(forward.sessionsByID["session"]?.summary, "Question")
        XCTAssertEqual(forward.sessionsByID["session"]?.updatedAt, timestamp)
    }

    func testDuplicateActionableAndResolutionEventsAreNoOps() {
        var state = SessionState()
        XCTAssertTrue(state.apply(started(at: base)))
        let actionable = AgentEvent.permissionRequested(
            sessionID: "session",
            timestamp: time(1),
            summary: "Approval"
        )
        XCTAssertTrue(state.apply(actionable))
        let waiting = state
        XCTAssertFalse(state.apply(actionable))
        XCTAssertEqual(state, waiting)

        let resolution = AgentEvent.actionableStateResolved(
            sessionID: "session",
            timestamp: time(2),
            summary: "Resolved"
        )
        XCTAssertTrue(state.apply(resolution))
        let resolved = state
        XCTAssertFalse(state.apply(resolution))
        XCTAssertEqual(state, resolved)
    }

    func testJumpTargetMergeFillsMissingFieldsWithoutReplacingPreciseIdentifiersOrTimestamp() {
        var state = SessionState()
        XCTAssertTrue(state.apply(started(
            at: base,
            jumpTarget: JumpTarget(
                terminalApp: "iTerm",
                workingDirectory: "/tmp/project",
                terminalSessionID: "session-id",
                terminalTTY: "/dev/ttys001"
            )
        )))
        let lifecycleTimestamp = state.sessionsByID["session"]?.updatedAt

        XCTAssertTrue(state.apply(.jumpTargetUpdated(
            sessionID: "session",
            timestamp: time(10),
            jumpTarget: JumpTarget(
                terminalApp: "Terminal",
                workspaceName: "workspace",
                paneTitle: "pane",
                workingDirectory: "/different",
                terminalSessionID: "replacement-id",
                terminalTTY: "/dev/ttys999"
            )
        )))

        let session = tryUnwrap(state.sessionsByID["session"])
        XCTAssertEqual(session.updatedAt, lifecycleTimestamp)
        XCTAssertEqual(session.jumpTarget?.terminalApp, "iTerm")
        XCTAssertEqual(session.jumpTarget?.workspaceName, "workspace")
        XCTAssertEqual(session.jumpTarget?.paneTitle, "pane")
        XCTAssertEqual(session.jumpTarget?.workingDirectory, "/tmp/project")
        XCTAssertEqual(session.jumpTarget?.terminalSessionID, "session-id")
        XCTAssertEqual(session.jumpTarget?.terminalTTY, "/dev/ttys001")

        let merged = state
        XCTAssertFalse(state.apply(.jumpTargetUpdated(
            sessionID: "session",
            timestamp: time(11),
            jumpTarget: tryUnwrap(session.jumpTarget)
        )))
        XCTAssertEqual(state, merged)
    }

    func testLivenessFirstMissDebouncesSecondMissReapsAndEndedSessionCannotRevive() {
        var state = SessionState()
        XCTAssertTrue(state.apply(started(at: base)))
        let initiallyAlive = state

        XCTAssertTrue(state.markProcessLiveness(aliveSessionIDs: ["session"]).isEmpty)
        XCTAssertEqual(state, initiallyAlive)

        XCTAssertTrue(state.markProcessLiveness(aliveSessionIDs: []).isEmpty)
        XCTAssertEqual(state.sessionsByID["session"]?.processNotSeenCount, 1)
        XCTAssertTrue(state.sessionsByID["session"]?.isProcessAlive == true)
        XCTAssertFalse(state.sessionsByID["session"]?.isSessionEnded == true)

        XCTAssertEqual(state.markProcessLiveness(aliveSessionIDs: []), ["session"])
        let ended = state
        XCTAssertEqual(state.sessionsByID["session"]?.processNotSeenCount, 2)
        XCTAssertFalse(state.sessionsByID["session"]?.isProcessAlive == true)
        XCTAssertTrue(state.sessionsByID["session"]?.isSessionEnded == true)
        XCTAssertEqual(state.sessionsByID["session"]?.phase, .completed)

        XCTAssertTrue(state.markProcessLiveness(aliveSessionIDs: ["session"]).isEmpty)
        XCTAssertEqual(state, ended)
    }

    func testUpsertDiscoveredSessionWithSameIDIsNoOp() {
        let original = discoveredSession(id: "discovered-1", summary: "Original")
        var state = SessionState()

        XCTAssertTrue(state.upsertDiscoveredSession(original))
        let once = state
        XCTAssertFalse(state.upsertDiscoveredSession(discoveredSession(
            id: "discovered-1",
            summary: "Replacement"
        )))
        XCTAssertEqual(state, once)
        XCTAssertEqual(state.sessionsByID["discovered-1"]?.summary, "Original")
    }

    func testReplaceDiscoveredSessionPreservesFirstSeenAndPreciseJumpMetadata() {
        let firstSeen = base.addingTimeInterval(-20)
        let placeholder = AgentSession(
            id: "discovered-1",
            title: "Discovered",
            tool: .codex,
            phase: .completed,
            summary: "Discovered",
            updatedAt: base,
            firstSeenAt: firstSeen,
            jumpTarget: JumpTarget(
                terminalApp: "iTerm",
                workingDirectory: "/tmp/project",
                terminalSessionID: "precise-session",
                terminalTTY: "/dev/ttys001"
            ),
            isProcessAlive: true
        )
        var state = SessionState(sessions: [placeholder])
        let hookStart = AgentEvent.sessionStarted(
            sessionID: "hook-session",
            timestamp: time(3),
            title: "Hook",
            tool: .codex,
            summary: "Started",
            jumpTarget: JumpTarget(
                terminalApp: "iTerm",
                workspaceName: "workspace",
                paneTitle: "pane",
                workingDirectory: "/other",
                terminalSessionID: "weaker-session",
                terminalTTY: "/dev/ttys999"
            )
        )

        XCTAssertTrue(state.replaceDiscoveredSession(sessionID: "discovered-1", with: hookStart))
        XCTAssertNil(state.sessionsByID["discovered-1"])
        let replacement = tryUnwrap(state.sessionsByID["hook-session"])
        XCTAssertEqual(replacement.firstSeenAt, firstSeen)
        XCTAssertEqual(replacement.phase, .running)
        XCTAssertEqual(replacement.updatedAt, time(3))
        XCTAssertEqual(replacement.jumpTarget?.workspaceName, "workspace")
        XCTAssertEqual(replacement.jumpTarget?.paneTitle, "pane")
        XCTAssertEqual(replacement.jumpTarget?.workingDirectory, "/tmp/project")
        XCTAssertEqual(replacement.jumpTarget?.terminalSessionID, "precise-session")
        XCTAssertEqual(replacement.jumpTarget?.terminalTTY, "/dev/ttys001")
    }

}

private extension M2SessionLifecycleTests {
    func started(
        at timestamp: Date,
        title: String = "Project",
        summary: String = "Started",
        jumpTarget: JumpTarget? = nil
    ) -> AgentEvent {
        .sessionStarted(
            sessionID: "session",
            timestamp: timestamp,
            title: title,
            tool: .codex,
            summary: summary,
            jumpTarget: jumpTarget
        )
    }

    private func discoveredSession(id: String, summary: String) -> AgentSession {
        AgentSession(
            id: id,
            title: "Discovered",
            tool: .codex,
            phase: .completed,
            summary: summary,
            updatedAt: base,
            jumpTarget: JumpTarget(
                terminalApp: "Terminal",
                workingDirectory: "/tmp/project",
                terminalTTY: "/dev/ttys001"
            ),
            isProcessAlive: true
        )
    }

    private func time(_ offset: TimeInterval) -> Date {
        base.addingTimeInterval(offset)
    }

    private func tryUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) -> T {
        guard let value else {
            XCTFail("Expected non-nil value", file: file, line: line)
            fatalError("Expected non-nil value")
        }
        return value
    }
}

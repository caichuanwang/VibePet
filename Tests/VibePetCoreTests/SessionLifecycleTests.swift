import XCTest
@testable import VibePetCore

final class SessionLifecycleTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testExactEventReplayReturnsFalseAndPreservesState() {
        var state = SessionState()
        let event = started("s1", at: base)
        XCTAssertTrue(state.apply(event))
        let snapshot = state

        XCTAssertFalse(state.apply(event))
        XCTAssertEqual(state, snapshot)
    }

    func testStaleStartActivityAndTurnCompletionDoNotMoveStateBackward() {
        var state = applying([
            started("s1", at: base),
            .activityUpdated(sessionID: "s1", timestamp: base.addingTimeInterval(10), summary: "Newest"),
        ])
        let snapshot = state.sessionsByID["s1"]

        XCTAssertFalse(state.apply(started("s1", at: base.addingTimeInterval(5))))
        XCTAssertFalse(state.apply(.activityUpdated(
            sessionID: "s1",
            timestamp: base.addingTimeInterval(5),
            summary: "Stale activity"
        )))
        XCTAssertFalse(state.apply(.sessionCompleted(
            sessionID: "s1",
            timestamp: base.addingTimeInterval(5),
            summary: "Stale completion",
            isError: true,
            isSessionEnd: false
        )))
        XCTAssertEqual(state.sessionsByID["s1"], snapshot)
    }

    func testLateSessionEndMergesTerminalBitsWithoutOverwritingNewerContent() {
        var state = applying([
            started("s1", at: base),
            .activityUpdated(sessionID: "s1", timestamp: base.addingTimeInterval(10), summary: "Newest"),
        ])

        XCTAssertTrue(state.apply(.sessionCompleted(
            sessionID: "s1",
            timestamp: base.addingTimeInterval(5),
            summary: "Old failure",
            isError: true,
            isSessionEnd: true
        )))

        let session = state.sessionsByID["s1"]
        XCTAssertEqual(session?.phase, .completed)
        XCTAssertEqual(session?.isSessionEnded, true)
        XCTAssertEqual(session?.isProcessAlive, false)
        XCTAssertEqual(session?.summary, "Newest")
        XCTAssertEqual(session?.isError, false)
        XCTAssertEqual(session?.updatedAt, base.addingTimeInterval(10))
    }

    func testEndedSessionCannotBeRevivedByNewerStartActivityOrLiveness() {
        var state = applying([
            started("s1", at: base),
            .sessionCompleted(
                sessionID: "s1",
                timestamp: base.addingTimeInterval(1),
                summary: "Ended",
                isError: false,
                isSessionEnd: true
            ),
        ])
        let ended = state.sessionsByID["s1"]

        XCTAssertFalse(state.apply(started("s1", at: base.addingTimeInterval(2))))
        XCTAssertFalse(state.apply(.activityUpdated(
            sessionID: "s1",
            timestamp: base.addingTimeInterval(3),
            summary: "Late activity"
        )))
        XCTAssertTrue(state.markProcessLiveness(aliveSessionIDs: ["s1"]).isEmpty)
        XCTAssertEqual(state.sessionsByID["s1"], ended)
    }

    func testNewerActivityReopensTurnLevelCompletion() {
        var state = applying([
            started("s1", at: base),
            .sessionCompleted(
                sessionID: "s1",
                timestamp: base.addingTimeInterval(1),
                summary: "Turn done",
                isError: true,
                isSessionEnd: false
            ),
        ])

        XCTAssertTrue(state.apply(.activityUpdated(
            sessionID: "s1",
            timestamp: base.addingTimeInterval(2),
            summary: "Next turn"
        )))
        XCTAssertEqual(state.sessionsByID["s1"]?.phase, .running)
        XCTAssertEqual(state.sessionsByID["s1"]?.isError, false)
        XCTAssertEqual(state.sessionsByID["s1"]?.isSessionEnded, false)
    }

    func testJumpTargetMergeFillsMissingPreciseFieldsWithoutOverwritingExistingValues() {
        let original = JumpTarget(
            terminalApp: "Terminal",
            workspaceName: "Existing workspace",
            workingDirectory: "/existing",
            terminalSessionID: "exact-session"
        )
        var state = applying([.sessionStarted(
            sessionID: "s1",
            timestamp: base,
            title: "Session",
            tool: .claudeCode,
            summary: "Started",
            jumpTarget: original
        )])

        XCTAssertTrue(state.apply(.jumpTargetUpdated(
            sessionID: "s1",
            timestamp: base.addingTimeInterval(-10),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "Incoming workspace",
                paneTitle: "new title",
                workingDirectory: "/incoming",
                terminalSessionID: "ambiguous-replacement",
                terminalTTY: "/dev/ttys001"
            )
        )))
        let merged = state.sessionsByID["s1"]?.jumpTarget
        XCTAssertEqual(merged?.terminalApp, "Terminal")
        XCTAssertEqual(merged?.workspaceName, "Existing workspace")
        XCTAssertEqual(merged?.workingDirectory, "/existing")
        XCTAssertEqual(merged?.terminalSessionID, "exact-session")
        XCTAssertEqual(merged?.paneTitle, "new title")
        XCTAssertEqual(merged?.terminalTTY, "/dev/ttys001")
        XCTAssertEqual(state.sessionsByID["s1"]?.updatedAt, base)

        let snapshot = state
        XCTAssertFalse(state.apply(.jumpTargetUpdated(
            sessionID: "s1",
            timestamp: base.addingTimeInterval(20),
            jumpTarget: JumpTarget(terminalApp: "Terminal")
        )))
        XCTAssertEqual(state, snapshot)
    }

    func testJumpTargetMergeTreatsUnknownTerminalAppAsMissing() {
        var state = applying([.sessionStarted(
            sessionID: "s1",
            timestamp: base,
            title: "Session",
            tool: .claudeCode,
            summary: "Started",
            jumpTarget: JumpTarget(terminalApp: "Unknown", workingDirectory: "/work/VibePet")
        )])

        XCTAssertTrue(state.apply(.jumpTargetUpdated(
            sessionID: "s1",
            timestamp: base.addingTimeInterval(1),
            jumpTarget: JumpTarget(terminalApp: "Ghostty", terminalSessionID: "ghostty-session")
        )))
        XCTAssertEqual(state.sessionsByID["s1"]?.jumpTarget?.terminalApp, "Ghostty")
        XCTAssertEqual(state.sessionsByID["s1"]?.jumpTarget?.workingDirectory, "/work/VibePet")
        XCTAssertEqual(state.sessionsByID["s1"]?.jumpTarget?.terminalSessionID, "ghostty-session")
    }

    func testActionableEventsRejectStaleAndDuplicateUpdates() {
        var state = applying([started("s1", at: base)])
        let request = AgentEvent.permissionRequested(
            sessionID: "s1",
            timestamp: base.addingTimeInterval(2),
            summary: "Approve"
        )
        XCTAssertTrue(state.apply(request))
        XCTAssertFalse(state.apply(request))
        XCTAssertFalse(state.apply(.questionAsked(
            sessionID: "s1",
            timestamp: base.addingTimeInterval(1),
            summary: "Stale question"
        )))
        XCTAssertTrue(state.apply(.actionableStateResolved(
            sessionID: "s1",
            timestamp: base.addingTimeInterval(1),
            summary: "Resolved by request causality"
        )))
        XCTAssertEqual(state.sessionsByID["s1"]?.phase, .running)
        XCTAssertFalse(state.apply(request), "the resolved request timestamp is watermarked")
    }

    func testEqualTimestampActionablePriorityIsArrivalOrderIndependent() {
        let approval = AgentEvent.permissionRequested(sessionID: "s1", timestamp: base, summary: "Approve")
        let question = AgentEvent.questionAsked(sessionID: "s1", timestamp: base, summary: "Question")
        var first = applying([started("s1", at: base.addingTimeInterval(-1)), approval, question])
        var second = applying([started("s1", at: base.addingTimeInterval(-1)), question, approval])

        XCTAssertEqual(first.sessionsByID["s1"], second.sessionsByID["s1"])
        XCTAssertEqual(first.sessionsByID["s1"]?.phase, .waitingForAnswer)
        XCTAssertFalse(first.apply(question))
        XCTAssertFalse(second.apply(approval))
    }

    func testDiscoveredSessionUpsertReturnsChangeOnlyForNewID() {
        let discovered = AgentSession(
            id: "discovered-1",
            title: "Codex",
            tool: .codex,
            phase: .completed,
            summary: "Discovered",
            updatedAt: base
        )
        var state = SessionState()

        XCTAssertTrue(state.upsertDiscoveredSession(discovered))
        XCTAssertFalse(state.upsertDiscoveredSession(discovered))
        XCTAssertEqual(state.sessionsByID[discovered.id], discovered)
    }

    private func started(_ id: String, at timestamp: Date) -> AgentEvent {
        .sessionStarted(
            sessionID: id,
            timestamp: timestamp,
            title: "Session \(id)",
            tool: .claudeCode,
            summary: "Started",
            jumpTarget: nil
        )
    }

    private func applying(_ events: [AgentEvent]) -> SessionState {
        var state = SessionState()
        for event in events {
            state.apply(event)
        }
        return state
    }
}

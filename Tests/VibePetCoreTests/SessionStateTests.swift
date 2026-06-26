import XCTest
@testable import VibePetCore

final class SessionStateTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testSessionPhaseRequiresAttentionOnlyForWaitingPhases() {
        XCTAssertTrue(SessionPhase.waitingForApproval.requiresAttention)
        XCTAssertTrue(SessionPhase.waitingForAnswer.requiresAttention)
        XCTAssertFalse(SessionPhase.running.requiresAttention)
        XCTAssertFalse(SessionPhase.completed.requiresAttention)
        XCTAssertEqual(Set(SessionPhase.allCases), [.running, .waitingForApproval, .waitingForAnswer, .completed])
    }

    func testJumpTargetRoundTripsThroughCodable() throws {
        let target = JumpTarget(
            terminalApp: "Terminal",
            workspaceName: "VibePet",
            paneTitle: "swift test",
            workingDirectory: "/tmp/VibePet",
            terminalSessionID: "session-123",
            terminalTTY: "/dev/ttys001"
        )

        let decoded = try roundTrip(target)

        XCTAssertEqual(decoded, target)
    }

    func testJumpTargetDecodesLegacyUnsupportedKeys() throws {
        let data = Data(
            """
            {
              "terminalApp": "Terminal",
              "workspaceName": "VibePet",
              "paneTitle": "swift test",
              "workingDirectory": "/tmp/VibePet",
              "terminalTTY": "/dev/ttys001",
              "codexThreadID": "thread-123",
              "tmuxTarget": "session:1.2",
              "tmuxSocketPath": "/tmp/tmux.sock",
              "warpPaneUUID": "warp-pane"
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(JumpTarget.self, from: data)

        XCTAssertEqual(decoded.terminalApp, "Terminal")
        XCTAssertEqual(decoded.workspaceName, "VibePet")
        XCTAssertEqual(decoded.paneTitle, "swift test")
        XCTAssertEqual(decoded.workingDirectory, "/tmp/VibePet")
        XCTAssertNil(decoded.terminalSessionID)
        XCTAssertEqual(decoded.terminalTTY, "/dev/ttys001")
    }

    func testAgentSessionRoundTripsThroughCodable() throws {
        let session = AgentSession(
            id: "session-1",
            title: "VibePet",
            tool: .claudeCode,
            phase: .waitingForApproval,
            summary: "Needs approval",
            updatedAt: base,
            firstSeenAt: base.addingTimeInterval(-10),
            jumpTarget: JumpTarget(terminalApp: "Terminal", workspaceName: "VibePet"),
            isError: true,
            isSessionEnded: false,
            isProcessAlive: false,
            processNotSeenCount: 1
        )

        let decoded = try roundTrip(session)

        XCTAssertEqual(decoded, session)
    }

    func testAttentionRequiringSessionIsVisibleRegardlessOfLiveness() {
        let session = AgentSession(
            id: "session-1",
            title: "VibePet",
            tool: .claudeCode,
            phase: .waitingForAnswer,
            summary: "Needs answer",
            updatedAt: base,
            isSessionEnded: true,
            isProcessAlive: false,
            processNotSeenCount: 2
        )

        XCTAssertTrue(session.isVisible)
    }

    func testAgentEventCasesExposeSessionIdentityAndTimestamp() {
        let events: [AgentEvent] = [
            .sessionStarted(sessionID: "s", timestamp: base, title: "T", tool: .claudeCode, summary: "Started", jumpTarget: nil),
            .activityUpdated(sessionID: "s", timestamp: base, summary: "Activity"),
            .permissionRequested(sessionID: "s", timestamp: base, summary: "Permission"),
            .questionAsked(sessionID: "s", timestamp: base, summary: "Question"),
            .sessionCompleted(sessionID: "s", timestamp: base, summary: "Done", isError: false, isSessionEnd: true),
            .jumpTargetUpdated(sessionID: "s", timestamp: base, jumpTarget: JumpTarget(terminalApp: "Terminal")),
            .actionableStateResolved(sessionID: "s", timestamp: base, summary: "Resolved"),
        ]

        for event in events {
            XCTAssertEqual(event.sessionID, "s")
            XCTAssertEqual(event.timestamp, base)
        }
    }

    func testAgentEventRoundTripsThroughCodable() throws {
        let event = AgentEvent.sessionCompleted(
            sessionID: "session-1",
            timestamp: base,
            summary: "Failed",
            isError: true,
            isSessionEnd: false
        )

        let decoded = try roundTrip(event)

        XCTAssertEqual(decoded, event)
    }

    func testEventSequenceProducesDeterministicState() {
        let events = [
            started("s1", at: base),
            AgentEvent.activityUpdated(sessionID: "s1", timestamp: base.addingTimeInterval(1), summary: "Working"),
            AgentEvent.permissionRequested(sessionID: "s1", timestamp: base.addingTimeInterval(2), summary: "Approve"),
        ]

        XCTAssertEqual(state(applying: events), state(applying: events))
    }

    func testSessionStartedPreservesExistingFirstSeenAt() {
        var state = SessionState()
        state.apply(started("s1", at: base))
        state.apply(.sessionStarted(
            sessionID: "s1",
            timestamp: base.addingTimeInterval(20),
            title: "Renamed",
            tool: .codex,
            summary: "Restarted",
            jumpTarget: nil
        ))

        let session = state.sessionsByID["s1"]
        XCTAssertEqual(session?.firstSeenAt, base)
        XCTAssertEqual(session?.updatedAt, base.addingTimeInterval(20))
        XCTAssertEqual(session?.phase, .running)
        XCTAssertEqual(session?.title, "Renamed")
    }

    func testActivityUpdatedDoesNotClearPendingDecision() {
        var state = state(applying: [
            started("s1", at: base),
            .permissionRequested(sessionID: "s1", timestamp: base.addingTimeInterval(1), summary: "Approve"),
        ])

        state.apply(.activityUpdated(sessionID: "s1", timestamp: base.addingTimeInterval(2), summary: "Still working"))

        XCTAssertEqual(state.sessionsByID["s1"]?.phase, .waitingForApproval)
        XCTAssertEqual(state.sessionsByID["s1"]?.summary, "Still working")
    }

    func testActivityUpdatedAdvancesRunningSessionRecency() {
        var state = state(applying: [started("s1", at: base)])

        state.apply(.activityUpdated(
            sessionID: "s1",
            timestamp: base.addingTimeInterval(30),
            summary: "Codex PostToolUse: Bash"
        ))

        XCTAssertEqual(state.sessionsByID["s1"]?.phase, .running)
        XCTAssertEqual(state.sessionsByID["s1"]?.summary, "Codex PostToolUse: Bash")
        XCTAssertEqual(state.sessionsByID["s1"]?.updatedAt, base.addingTimeInterval(30))
    }

    func testJumpTargetUpdatedChangesOnlyJumpTargetAndTimestamp() {
        var state = state(applying: [
            started("s1", at: base),
            .permissionRequested(sessionID: "s1", timestamp: base.addingTimeInterval(1), summary: "Approve"),
        ])
        state.apply(.jumpTargetUpdated(
            sessionID: "s1",
            timestamp: base.addingTimeInterval(2),
            jumpTarget: JumpTarget(
                terminalApp: "Terminal",
                terminalSessionID: "session-1",
                terminalTTY: "/dev/ttys001"
            )
        ))

        let session = state.sessionsByID["s1"]
        XCTAssertEqual(session?.jumpTarget?.terminalSessionID, "session-1")
        XCTAssertEqual(session?.jumpTarget?.terminalTTY, "/dev/ttys001")
        XCTAssertEqual(session?.phase, .waitingForApproval)
        XCTAssertTrue(session?.isProcessAlive == true)
        XCTAssertFalse(session?.isSessionEnded == true)
        XCTAssertEqual(session?.processNotSeenCount, 0)
        XCTAssertEqual(session?.updatedAt, base.addingTimeInterval(2))
    }

    func testUnknownSessionNonStartEventsAreIgnored() {
        var state = SessionState()

        state.apply(.activityUpdated(sessionID: "unknown", timestamp: base, summary: "Activity"))
        state.apply(.permissionRequested(sessionID: "unknown", timestamp: base, summary: "Approve"))
        state.apply(.sessionCompleted(sessionID: "unknown", timestamp: base, summary: "Done", isError: false, isSessionEnd: false))

        XCTAssertTrue(state.sessionsByID.isEmpty)
    }

    func testSessionCompletedFlagsCompletionErrorAndSessionEnd() {
        var state = state(applying: [started("s1", at: base)])

        state.apply(.sessionCompleted(
            sessionID: "s1",
            timestamp: base.addingTimeInterval(1),
            summary: "Failed",
            isError: true,
            isSessionEnd: true
        ))

        let session = state.sessionsByID["s1"]
        XCTAssertEqual(session?.phase, .completed)
        XCTAssertEqual(session?.isError, true)
        XCTAssertEqual(session?.isSessionEnded, true)
    }

    func testStopCompletionDoesNotMarkEndedOrError() {
        var state = state(applying: [started("s1", at: base)])

        state.apply(.sessionCompleted(
            sessionID: "s1",
            timestamp: base.addingTimeInterval(1),
            summary: "Done",
            isError: false,
            isSessionEnd: false
        ))

        let session = state.sessionsByID["s1"]
        XCTAssertEqual(session?.phase, .completed)
        XCTAssertEqual(session?.isError, false)
        XCTAssertEqual(session?.isSessionEnded, false)
    }

    func testDecisionResolutionTransitions() {
        var state = state(applying: [
            started("approval", at: base),
            .permissionRequested(sessionID: "approval", timestamp: base.addingTimeInterval(1), summary: "Approve"),
            started("question", at: base),
            .questionAsked(sessionID: "question", timestamp: base.addingTimeInterval(1), summary: "Answer"),
            started("deny", at: base),
            .permissionRequested(sessionID: "deny", timestamp: base.addingTimeInterval(1), summary: "Approve"),
        ])

        state.resolvePermission(sessionID: "approval", approved: true, at: base.addingTimeInterval(2))
        state.answerQuestion(sessionID: "question", summary: "Answered", at: base.addingTimeInterval(2))
        state.resolvePermission(sessionID: "deny", approved: false, at: base.addingTimeInterval(2))

        XCTAssertEqual(state.sessionsByID["approval"]?.phase, .running)
        XCTAssertEqual(state.sessionsByID["question"]?.phase, .running)
        XCTAssertEqual(state.sessionsByID["question"]?.summary, "Answered")
        XCTAssertEqual(state.sessionsByID["deny"]?.phase, .completed)
    }

    func testActionableStateResolvedOnlyAffectsWaitingSessions() {
        var state = state(applying: [
            started("running", at: base),
            started("waiting", at: base),
            .questionAsked(sessionID: "waiting", timestamp: base.addingTimeInterval(1), summary: "Answer"),
        ])
        let runningBefore = state.sessionsByID["running"]

        state.apply(.actionableStateResolved(sessionID: "running", timestamp: base.addingTimeInterval(2), summary: "Resolved"))
        state.apply(.actionableStateResolved(sessionID: "waiting", timestamp: base.addingTimeInterval(2), summary: "Resolved"))

        XCTAssertEqual(state.sessionsByID["running"], runningBefore)
        XCTAssertEqual(state.sessionsByID["waiting"]?.phase, .running)
    }

    func testTwoConsecutiveLivenessMissesReapSession() {
        var state = state(applying: [started("s1", at: base)])

        XCTAssertTrue(state.markProcessLiveness(aliveSessionIDs: []).isEmpty)
        let reaped = state.markProcessLiveness(aliveSessionIDs: [])

        XCTAssertEqual(reaped, ["s1"])
        XCTAssertEqual(state.sessionsByID["s1"]?.phase, .completed)
        XCTAssertEqual(state.sessionsByID["s1"]?.isSessionEnded, true)
        XCTAssertEqual(state.sessionsByID["s1"]?.isProcessAlive, false)
        XCTAssertFalse(state.visibleSessions.contains { $0.id == "s1" })
    }

    func testReapedSessionIsNotReportedRepeatedly() {
        var state = state(applying: [started("s1", at: base)])

        state.markProcessLiveness(aliveSessionIDs: [])
        XCTAssertEqual(state.markProcessLiveness(aliveSessionIDs: []), ["s1"])
        XCTAssertTrue(state.markProcessLiveness(aliveSessionIDs: []).isEmpty)
    }

    func testRemoveInvisibleSessionsEvictsCompletedEndedSessions() {
        var state = state(applying: [started("s1", at: base)])

        state.markProcessLiveness(aliveSessionIDs: [])
        state.markProcessLiveness(aliveSessionIDs: [])
        let removed = state.removeInvisibleSessions()

        XCTAssertEqual(removed, ["s1"])
        XCTAssertNil(state.sessionsByID["s1"])
        XCTAssertTrue(state.visibleSessions.isEmpty)
    }

    func testLivenessResetsWhenProcessIsSeenAgain() {
        var state = state(applying: [started("s1", at: base)])

        state.markProcessLiveness(aliveSessionIDs: [])
        state.markProcessLiveness(aliveSessionIDs: ["s1"])

        XCTAssertEqual(state.sessionsByID["s1"]?.processNotSeenCount, 0)
        XCTAssertEqual(state.sessionsByID["s1"]?.isProcessAlive, true)
    }

    func testAggregatesAndDerivedActivity() {
        var state = state(applying: [
            started("running", at: base),
            started("waiting", at: base.addingTimeInterval(1)),
            .permissionRequested(sessionID: "waiting", timestamp: base.addingTimeInterval(2), summary: "Approve"),
            started("reaped", at: base.addingTimeInterval(3)),
        ])
        state.markProcessLiveness(aliveSessionIDs: ["running", "waiting"])
        state.markProcessLiveness(aliveSessionIDs: ["running", "waiting"])

        XCTAssertEqual(state.attentionCount, 1)
        XCTAssertEqual(state.runningCount, 1)
        XCTAssertEqual(Set(state.visibleSessions.map(\.id)), ["running", "waiting"])
        XCTAssertEqual(state.activeActionableSession?.id, "waiting")
        XCTAssertEqual(state.derivedPetActivity, .deciding)
    }

    func testStartedSessionDrivesGreetingOnce() {
        var state = state(applying: [started("s1", at: base)])

        XCTAssertEqual(state.derivedPetActivity, .greeting)

        state.markGreetingShown(for: "s1")

        XCTAssertEqual(state.derivedPetActivity, .idle)
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

    private func state(applying events: [AgentEvent]) -> SessionState {
        var state = SessionState()
        for event in events {
            state.apply(event)
        }
        return state
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(value)
        return try decoder.decode(T.self, from: data)
    }
}

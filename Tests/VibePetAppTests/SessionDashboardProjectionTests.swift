import XCTest
@testable import VibePetApp
@testable import VibePetCore

final class SessionDashboardProjectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_120)
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testHomeProjectionUsesSessionStateCountsAndOrdering() {
        let state = SessionState(sessions: [
            session(id: "old", title: "Old", tool: .claudeCode, phase: .running, updatedOffset: 10),
            session(id: "waiting", title: "Waiting", tool: .codex, phase: .waitingForApproval, updatedOffset: 30, jumpTarget: JumpTarget(terminalApp: "Terminal")),
            session(id: "new", title: "New", tool: .claudeCode, phase: .running, updatedOffset: 40)
        ])

        let projection = SessionDashboardProjection(state: state, activePetName: "Pixel", now: now)

        XCTAssertEqual(projection.totalCount, 3)
        XCTAssertEqual(projection.runningCount, 2)
        XCTAssertEqual(projection.attentionCount, 1)
        XCTAssertEqual(projection.rows.map(\.id), ["waiting", "new", "old"])
        XCTAssertEqual(projection.rows[0].status, .attention)
        XCTAssertEqual(projection.rows[0].toolTag, "codex")
        XCTAssertEqual(projection.rows[0].terminalTag, "Terminal")
    }

    func testHomeProjectionMapsErrorCompletionToErrorStatus() {
        let state = SessionState(sessions: [
            session(id: "failed", title: "Failed", tool: .codex, phase: .completed, isError: true, isSessionEnded: false)
        ])

        let projection = SessionDashboardProjection(state: state, activePetName: "Pixel", now: now)

        XCTAssertEqual(projection.rows.first?.status, .error)
    }

    func testDiscoveredCompletedLiveSessionDisplaysIdleButNotRunning() {
        let state = SessionState(sessions: [
            session(
                id: "idle",
                title: "VibePet",
                tool: .codex,
                phase: .completed,
                jumpTarget: JumpTarget(terminalApp: "Ghostty"),
                isSessionEnded: false
            )
        ])

        let projection = SessionDashboardProjection(state: state, activePetName: "Pixel", now: now)

        XCTAssertEqual(projection.totalCount, 1)
        XCTAssertEqual(projection.runningCount, 0)
        XCTAssertEqual(projection.rows.first?.status, .idle)
    }

    func testElapsedTimeFormattingUsesFirstSeenAt() {
        let state = SessionState(sessions: [
            session(id: "long", title: "Long", tool: .claudeCode, phase: .running, firstSeenOffset: -125)
        ])

        let projection = SessionDashboardProjection(state: state, activePetName: "Pixel", now: now)

        XCTAssertEqual(projection.rows.first?.elapsed, "4m")
    }

    func testEmptyStateCarriesActivePetName() {
        let projection = SessionDashboardProjection(state: SessionState(), activePetName: "Pixel", now: now)

        XCTAssertTrue(projection.isEmpty)
        XCTAssertEqual(projection.emptyPetName, "Pixel")
    }

    func testSelectionResolutionKeepsUserSelectionUntilItDisappears() {
        let projection = SessionDashboardProjection(
            state: SessionState(sessions: [
                session(id: "running", title: "Running", tool: .claudeCode, phase: .running, updatedOffset: 20),
                session(id: "waiting", title: "Waiting", tool: .codex, phase: .waitingForApproval, updatedOffset: 10)
            ]),
            activePetName: "Pixel",
            now: now
        )

        XCTAssertEqual(projection.resolvedSelection(current: nil), "waiting")
        XCTAssertEqual(projection.resolvedSelection(current: "running"), "running")

        let nextProjection = SessionDashboardProjection(
            state: SessionState(sessions: [
                session(id: "waiting", title: "Waiting", tool: .codex, phase: .waitingForApproval, updatedOffset: 10)
            ]),
            activePetName: "Pixel",
            now: now
        )

        XCTAssertEqual(nextProjection.resolvedSelection(current: "running"), "waiting")
        XCTAssertNil(SessionDashboardProjection(state: SessionState(), activePetName: "Pixel", now: now).resolvedSelection(current: "running"))
    }

    private func session(
        id: String,
        title: String,
        tool: ToolKind,
        phase: SessionPhase,
        firstSeenOffset: TimeInterval = 0,
        updatedOffset: TimeInterval = 0,
        jumpTarget: JumpTarget? = nil,
        isError: Bool = false,
        isSessionEnded: Bool = false
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: title,
            tool: tool,
            phase: phase,
            summary: title,
            updatedAt: base.addingTimeInterval(updatedOffset),
            firstSeenAt: base.addingTimeInterval(firstSeenOffset),
            jumpTarget: jumpTarget,
            isError: isError,
            isSessionEnded: isSessionEnded,
            isProcessAlive: true
        )
    }
}

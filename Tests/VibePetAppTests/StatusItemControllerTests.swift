import XCTest
@testable import VibePetApp
@testable import VibePetCore

final class StatusItemControllerTests: XCTestCase {
    func testSessionMenuSummaryReflectsSessionStateCounts() {
        var state = SessionState()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        state.apply(.sessionStarted(
            sessionID: "running",
            timestamp: now,
            title: "Running",
            tool: .claudeCode,
            summary: "Running",
            jumpTarget: nil
        ))
        state.apply(.sessionStarted(
            sessionID: "waiting",
            timestamp: now.addingTimeInterval(1),
            title: "Waiting",
            tool: .codex,
            summary: "Waiting",
            jumpTarget: nil
        ))
        state.apply(.permissionRequested(
            sessionID: "waiting",
            timestamp: now.addingTimeInterval(2),
            summary: "Approve"
        ))
        state.apply(.sessionStarted(
            sessionID: "reaped",
            timestamp: now.addingTimeInterval(3),
            title: "Reaped",
            tool: .claudeCode,
            summary: "Reaped",
            jumpTarget: nil
        ))
        state.markProcessLiveness(aliveSessionIDs: ["running", "waiting"])
        state.markProcessLiveness(aliveSessionIDs: ["running", "waiting"])

        let summary = SessionMenuSummary.derive(from: state)

        XCTAssertEqual(summary, SessionMenuSummary(activeCount: 2, attentionCount: 1))
        XCTAssertEqual(summary.title, "会话：2 个活跃，1 个待处理")
    }
}

import XCTest
@testable import VibePetCore

/// Approval decision → Claude Code `PermissionRequest` hook output. Asserts the
/// JSON structure and the defer "no output" semantics. JSON key ordering is not
/// stable, so we decode and assert fields rather than compare raw bytes.
final class ClaudeCodeEncodeTests: XCTestCase {
    private let adapter = ClaudeCodeAdapter()

    func testDenyEmitsDenyDecisionWithReason() throws {
        let data = adapter.encodeResponse(
            .approval(.deny(reason: "用户拒绝")),
            for: sampleEnvelope()
        )
        let output = try hookSpecificOutput(data)
        XCTAssertEqual(output["hookEventName"] as? String, "PermissionRequest")
        let decision = try XCTUnwrap(output["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "deny")
        XCTAssertEqual(decision["message"] as? String, "用户拒绝")
    }

    func testDenyWithoutReasonOmitsReasonKey() throws {
        let data = adapter.encodeResponse(.approval(.deny(reason: nil)), for: sampleEnvelope())
        let output = try hookSpecificOutput(data)
        let decision = try XCTUnwrap(output["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "deny")
        XCTAssertNil(decision["message"])
    }

    func testAllowOnceEmitsAllowDecision() throws {
        let data = adapter.encodeResponse(.approval(.allowOnce), for: sampleEnvelope())
        let output = try hookSpecificOutput(data)
        XCTAssertEqual(output["hookEventName"] as? String, "PermissionRequest")
        let decision = try XCTUnwrap(output["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "allow")
        XCTAssertNil(decision["message"])
    }

    func testDeferEmitsNoJSON() {
        // Defer == empty stdout; the CLI then exits 0 → native permission flow.
        let data = adapter.encodeResponse(.defer, for: sampleEnvelope())
        XCTAssertTrue(data.isEmpty)
    }

    // Question (`AskUserQuestion`) encoding lands in M5 and is covered by
    // ClaudeCodeQuestionEncodeTests (allow + updatedInput, and defer on no answer).

    // MARK: - Helpers

    private func hookSpecificOutput(_ data: Data) throws -> [String: Any] {
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
    }

    private func sampleEnvelope() -> BridgeEnvelope {
        BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .claudeCode, projectName: "VibePet", sessionShortId: "a1b2c3", cwd: nil),
            content: .approval(ApprovalContent(
                title: "运行命令",
                risk: .medium,
                preview: .command(text: "swift test"),
                alwaysAllow: nil,
                requiresTerminalApproval: false
            ))
        )
    }
}

import XCTest
@testable import VibePetCore

/// M4-3: approval decision → Claude Code `PreToolUse` hook output. Asserts the
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
        XCTAssertEqual(output["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(output["permissionDecision"] as? String, "deny")
        XCTAssertEqual(output["permissionDecisionReason"] as? String, "用户拒绝")
    }

    func testDenyWithoutReasonOmitsReasonKey() throws {
        let data = adapter.encodeResponse(.approval(.deny(reason: nil)), for: sampleEnvelope())
        let output = try hookSpecificOutput(data)
        XCTAssertEqual(output["permissionDecision"] as? String, "deny")
        XCTAssertNil(output["permissionDecisionReason"])
    }

    func testAllowOnceEmitsAllowDecision() throws {
        let data = adapter.encodeResponse(.approval(.allowOnce), for: sampleEnvelope())
        let output = try hookSpecificOutput(data)
        XCTAssertEqual(output["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(output["permissionDecision"] as? String, "allow")
        XCTAssertNil(output["permissionDecisionReason"])
    }

    func testDeferEmitsNoJSON() {
        // Defer == empty stdout; the CLI then exits 0 → native permission flow.
        let data = adapter.encodeResponse(.defer, for: sampleEnvelope())
        XCTAssertTrue(data.isEmpty)
    }

    func testQuestionEncodingIsEmptyUntilM5() {
        let data = adapter.encodeResponse(
            .question(QuestionAnswer(answers: [:], freeform: [:])),
            for: sampleEnvelope()
        )
        XCTAssertTrue(data.isEmpty)
    }

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

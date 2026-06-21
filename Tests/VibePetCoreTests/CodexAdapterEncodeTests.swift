import XCTest
@testable import VibePetCore

/// M6-2: `CodexAdapter.encodeResponse` maps decisions to Codex `PermissionRequest`
/// hook output — allow / deny carry `hookSpecificOutput.decision.behavior`;
/// `question` and `defer` decline by emitting NO output (Codex then uses its
/// native approval flow). Encoding is deterministic/idempotent and never embeds
/// `requestId`.
final class CodexAdapterEncodeTests: XCTestCase {
    private let adapter = CodexAdapter()

    func testAllowOnceEncodesAllowDecision() throws {
        let data = adapter.encodeResponse(.approval(.allowOnce), for: envelope())
        let decision = try decision(in: data)
        XCTAssertEqual(decision["behavior"] as? String, "allow")
        XCTAssertNil(decision["message"])
    }

    func testAllowAlwaysEncodesAllowDecision() throws {
        // No verified Codex persistent rule → allowAlways equals a one-time allow.
        let data = adapter.encodeResponse(.approval(.allowAlways(scopeHint: "Bash")), for: envelope())
        let decision = try decision(in: data)
        XCTAssertEqual(decision["behavior"] as? String, "allow")
    }

    func testDenyEncodesDenyDecisionWithMessage() throws {
        let data = adapter.encodeResponse(.approval(.deny(reason: "Blocked by user")), for: envelope())
        let decision = try decision(in: data)
        XCTAssertEqual(decision["behavior"] as? String, "deny")
        XCTAssertEqual(decision["message"] as? String, "Blocked by user")
    }

    func testDenyWithoutReasonStillCarriesAMessage() throws {
        let data = adapter.encodeResponse(.approval(.deny(reason: nil)), for: envelope())
        let decision = try decision(in: data)
        XCTAssertEqual(decision["behavior"] as? String, "deny")
        XCTAssertNotNil(decision["message"] as? String)
    }

    func testQuestionDeclinesWithNoOutput() {
        let data = adapter.encodeResponse(.question(QuestionAnswer(answers: ["A": "B"])), for: envelope())
        XCTAssertTrue(data.isEmpty)
    }

    func testDeferDeclinesWithNoOutput() {
        XCTAssertTrue(adapter.encodeResponse(.defer, for: envelope()).isEmpty)
    }

    func testEncodingIsIdempotent() {
        let a = adapter.encodeResponse(.approval(.allowOnce), for: envelope())
        let b = adapter.encodeResponse(.approval(.allowOnce), for: envelope())
        XCTAssertEqual(a, b)
    }

    func testHookEventNameIsPermissionRequest() throws {
        let data = adapter.encodeResponse(.approval(.allowOnce), for: envelope())
        let output = try hookSpecificOutput(in: data)
        XCTAssertEqual(output["hookEventName"] as? String, "PermissionRequest")
    }

    /// Cross-adapter defer contract: Claude Code's defer is also empty stdout, so
    /// both tools fall back to their native flow on fail-open (shared `HookRuntime`).
    func testClaudeDeferStillEmpty() {
        XCTAssertTrue(ClaudeCodeAdapter().encodeResponse(.defer, for: envelope()).isEmpty)
    }

    // MARK: - Helpers

    private func envelope() -> BridgeEnvelope {
        BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .codex, projectName: "VibePet", sessionShortId: "9f8e7d", cwd: "/tmp"),
            content: .approval(ApprovalContent(
                title: "运行命令",
                risk: .medium,
                preview: .command(text: "swift build"),
                alwaysAllow: nil,
                requiresTerminalApproval: false
            ))
        )
    }

    private func hookSpecificOutput(in data: Data) throws -> [String: Any] {
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
    }

    private func decision(in data: Data) throws -> [String: Any] {
        let output = try hookSpecificOutput(in: data)
        return try XCTUnwrap(output["decision"] as? [String: Any])
    }
}

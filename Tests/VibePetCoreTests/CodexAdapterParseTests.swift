import XCTest
@testable import VibePetCore

/// M6-1: `CodexAdapter` normalizes Codex hook/notify events into the bridge
/// protocol. `PermissionRequest` → `.approval` (shell → `.command`, apply_patch →
/// `.fileChange`, risk-classified, not terminal); `notify(agent-turn-complete)` →
/// `.completion`; an answer-requiring request → `.approval(requiresTerminalApproval)`.
final class CodexAdapterParseTests: XCTestCase {
    private let adapter = CodexAdapter()

    func testToolKindIsCodex() {
        XCTAssertEqual(adapter.tool, .codex)
    }

    func testShellPermissionRequestBecomesCommandApproval() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("permission-request-shell.json"), env: [:]))
        let content = try approval(envelope)
        guard case let .command(text) = content.preview else {
            return XCTFail("Expected .command, got \(content.preview)")
        }
        XCTAssertEqual(text, "sudo rm -rf /tmp/build-cache")
        XCTAssertFalse(content.requiresTerminalApproval)
        XCTAssertNil(content.alwaysAllow)
        // RiskClassifier is wired: `sudo` escalates to high.
        XCTAssertEqual(content.risk, .high)
        XCTAssertEqual(envelope.source.tool, .codex)
        XCTAssertEqual(envelope.source.projectName, "VibePet")
        XCTAssertEqual(envelope.source.sessionShortId, "9f8e7d")
        XCTAssertTrue(envelope.content.needsResponse)
    }

    func testApplyPatchPermissionRequestBecomesFileChangeApproval() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("permission-request-apply-patch.json"), env: [:]))
        let content = try approval(envelope)
        guard case let .fileChange(path, added, removed) = content.preview else {
            return XCTFail("Expected .fileChange, got \(content.preview)")
        }
        XCTAssertEqual(path, "README.md")
        XCTAssertEqual(added, 2)
        XCTAssertEqual(removed, 1)
        XCTAssertFalse(content.requiresTerminalApproval)
    }

    func testNotifyAgentTurnCompleteBecomesCompletion() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("notify-agent-turn-complete.json"), env: [:]))
        guard case let .completion(content) = envelope.content else {
            return XCTFail("Expected .completion, got \(envelope.content)")
        }
        XCTAssertEqual(content.markdownSummary, "All 42 tests passed.")
        XCTAssertFalse(content.isError)
        XCTAssertFalse(envelope.content.needsResponse)
        XCTAssertEqual(envelope.source.tool, .codex)
        XCTAssertEqual(envelope.source.projectName, "VibePet")
        XCTAssertEqual(envelope.source.sessionShortId, "c0ffee")
    }

    func testStopHookBecomesCompletion() throws {
        // VibePet registers a Codex `Stop` hook for turn-completion (open-vibe-island
        // pattern), so the adapter maps it to `.completion` from `last_assistant_message`.
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("stop.json"), env: [:]))
        guard case let .completion(content) = envelope.content else {
            return XCTFail("Expected .completion, got \(envelope.content)")
        }
        XCTAssertEqual(content.markdownSummary, "Done — all 42 tests pass.")
        XCTAssertFalse(content.isError)
        XCTAssertFalse(envelope.content.needsResponse)
        XCTAssertEqual(envelope.source.tool, .codex)
        XCTAssertEqual(envelope.source.sessionShortId, "9f8e7d")
    }

    func testUnrelatedNotifyTypeIsIgnored() throws {
        let stdin = try json(["type": "session-configured", "thread-id": "abc"])
        XCTAssertNil(try adapter.parseEvent(stdin: stdin, env: [:]))
    }

    func testUnsupportedHookEventIsIgnored() throws {
        let stdin = try json([
            "hook_event_name": "SessionStart",
            "session_id": "x",
            "cwd": "/tmp",
        ])
        XCTAssertNil(try adapter.parseEvent(stdin: stdin, env: [:]))
    }

    func testMalformedInputIsIgnored() throws {
        XCTAssertNil(try adapter.parseEvent(stdin: Data("not json".utf8), env: [:]))
    }

    func testAnswerRequiringRequestDowngradesToTerminalApproval() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("permission-request-ask-question.json"), env: [:]))
        let content = try approval(envelope)
        XCTAssertTrue(content.requiresTerminalApproval)
        // It must NOT become a `.question` (Codex hooks cannot fill answers back).
        if case .question = envelope.content {
            XCTFail("Codex answer-requiring request must downgrade to approval, not question")
        }
    }

    // MARK: - Helpers

    private struct NotApproval: Error {}

    private func approval(
        _ envelope: BridgeEnvelope,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ApprovalContent {
        guard case let .approval(content) = envelope.content else {
            XCTFail("Expected .approval, got \(envelope.content)", file: file, line: line)
            throw NotApproval()
        }
        return content
    }

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func fixture(_ name: String) -> Data {
        (try? Data(contentsOf: URL(fileURLWithPath: fixturePath(name)))) ?? Data()
    }

    private func fixturePath(_ name: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/codex/\(name)")
            .path
    }
}

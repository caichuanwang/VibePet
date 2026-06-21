import XCTest
@testable import VibePetCore

/// M4-1: `PreToolUse` (≠ AskUserQuestion) → `.approval` with a tool-derived
/// `ActionPreview` and `SourceInfo`. Risk tagging is covered by
/// `RiskClassifierTests`; here we assert the preview variant and source.
final class ClaudeCodeApprovalParseTests: XCTestCase {
    private let adapter = ClaudeCodeAdapter()

    func testBashPreToolUseBecomesCommandApproval() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("pretooluse-bash.json"), env: [:]))
        let content = try approval(envelope)
        guard case let .command(text) = content.preview else {
            return XCTFail("Expected .command, got \(content.preview)")
        }
        XCTAssertEqual(text, "swift test")
        XCTAssertFalse(content.requiresTerminalApproval)
        XCTAssertNil(content.alwaysAllow)
        XCTAssertEqual(envelope.source.tool, .claudeCode)
        XCTAssertEqual(envelope.source.projectName, "VibePet")
        XCTAssertEqual(envelope.source.sessionShortId, "a1b2c3")
    }

    func testEditPreToolUseBecomesFileChangeApproval() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("pretooluse-edit.json"), env: [:]))
        let content = try approval(envelope)
        guard case let .fileChange(path, added, removed) = content.preview else {
            return XCTFail("Expected .fileChange, got \(content.preview)")
        }
        XCTAssertEqual(path, "/Users/dev/Projects/VibePet/README.md")
        XCTAssertEqual(added, 4)
        XCTAssertEqual(removed, 2)
    }

    func testWritePreToolUseBecomesFileChangeApproval() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("pretooluse-write.json"), env: [:]))
        let content = try approval(envelope)
        guard case let .fileChange(path, added, removed) = content.preview else {
            return XCTFail("Expected .fileChange, got \(content.preview)")
        }
        XCTAssertEqual(path, "/Users/dev/Projects/VibePet/NOTES.md")
        XCTAssertEqual(added, 3)
        XCTAssertEqual(removed, 0)
    }

    func testReadPreToolUseBecomesFileReadApproval() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("pretooluse-read.json"), env: [:]))
        let content = try approval(envelope)
        guard case let .fileRead(path) = content.preview else {
            return XCTFail("Expected .fileRead, got \(content.preview)")
        }
        XCTAssertEqual(path, "/Users/dev/Projects/VibePet/Package.swift")
    }

    func testWebFetchPreToolUseBecomesNetworkApproval() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("pretooluse-webfetch.json"), env: [:]))
        let content = try approval(envelope)
        guard case let .network(target) = content.preview else {
            return XCTFail("Expected .network, got \(content.preview)")
        }
        XCTAssertEqual(target, "https://example.com/docs")
    }

    func testUnknownToolBecomesGenericApproval() throws {
        let stdin = try json([
            "hook_event_name": "PreToolUse",
            "session_id": "a1b2c3d4e5f6",
            "tool_name": "Glob",
            "tool_input": ["pattern": "**/*.swift"],
        ])
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: stdin, env: [:]))
        let content = try approval(envelope)
        guard case let .generic(summary) = content.preview else {
            return XCTFail("Expected .generic, got \(content.preview)")
        }
        XCTAssertEqual(summary, "Glob")
    }

    func testAskUserQuestionIsNotApproval() throws {
        // AskUserQuestion becomes a `.question` (M5), never an approval. The full
        // question mapping is covered by ClaudeCodeQuestionParseTests.
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("ask-user-question.json"), env: [:]))
        if case .approval = envelope.content {
            XCTFail("AskUserQuestion must not become an approval")
        }
    }

    func testApprovalNeedsResponse() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("pretooluse-bash.json"), env: [:]))
        XCTAssertTrue(envelope.content.needsResponse)
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
            .appendingPathComponent("Fixtures/claude/\(name)")
            .path
    }
}

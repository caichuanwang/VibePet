import XCTest
@testable import VibePetCore

/// Claude follows open-vibe-island's interaction split: `PreToolUse` is lifecycle
/// activity, while `PermissionRequest` is the blocking approval/question entry.
final class ClaudeCodePermissionRequestParseTests: XCTestCase {
    private let adapter = ClaudeCodeAdapter()

    func testBashPermissionRequestBecomesCommandApproval() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("permission-request-bash.json"), env: [:]))
        let content = try approval(envelope)
        guard case let .command(text) = content.preview else {
            return XCTFail("Expected .command, got \(content.preview)")
        }
        XCTAssertEqual(text, "swift test")
        XCTAssertTrue(envelope.content.needsResponse)
        XCTAssertFalse(content.requiresTerminalApproval)
        XCTAssertNil(content.alwaysAllow)
        XCTAssertEqual(envelope.source.tool, .claudeCode)
        XCTAssertEqual(envelope.source.projectName, "VibePet")
        XCTAssertEqual(envelope.source.sessionShortId, "a1b2c3")
    }

    func testEditPermissionRequestBecomesFileChangeApproval() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(
            stdin: try permissionRequest(toolName: "Edit", input: [
                "file_path": "/Users/dev/Projects/VibePet/README.md",
                "old_string": "one\ntwo",
                "new_string": "one\ntwo\nthree\nfour",
            ]),
            env: [:]
        ))
        let content = try approval(envelope)
        guard case let .fileChange(path, added, removed) = content.preview else {
            return XCTFail("Expected .fileChange, got \(content.preview)")
        }
        XCTAssertEqual(path, "/Users/dev/Projects/VibePet/README.md")
        XCTAssertEqual(added, 4)
        XCTAssertEqual(removed, 2)
    }

    func testReadPermissionRequestBecomesFileReadApproval() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(
            stdin: try permissionRequest(toolName: "Read", input: [
                "file_path": "/Users/dev/Projects/VibePet/Package.swift",
            ]),
            env: [:]
        ))
        let content = try approval(envelope)
        guard case let .fileRead(path) = content.preview else {
            return XCTFail("Expected .fileRead, got \(content.preview)")
        }
        XCTAssertEqual(path, "/Users/dev/Projects/VibePet/Package.swift")
    }

    func testAskUserQuestionPermissionRequestBecomesQuestion() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("permission-request-ask-user-question.json"), env: [:]))

        guard case let .question(content) = envelope.content else {
            return XCTFail("Expected .question, got \(envelope.content)")
        }
        XCTAssertTrue(envelope.content.needsResponse)
        XCTAssertEqual(content.title, ClaudeCodeAdapter.askQuestionTitle)
        XCTAssertEqual(content.questions.first?.header, "Database")
    }

    func testAskUserQuestionPreToolUseIsStatusOnly() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("ask-user-question.json"), env: [:]))

        XCTAssertFalse(envelope.content.needsResponse)
        guard case let .status(content) = envelope.content else {
            return XCTFail("Expected status, got \(envelope.content)")
        }
        XCTAssertEqual(content.text, "Claude Code PreToolUse: AskUserQuestion")
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

    private func permissionRequest(toolName: String, input: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PermissionRequest",
            "session_id": "a1b2c3d4e5f6",
            "cwd": "/Users/dev/Projects/VibePet",
            "tool_name": toolName,
            "tool_input": input,
        ])
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

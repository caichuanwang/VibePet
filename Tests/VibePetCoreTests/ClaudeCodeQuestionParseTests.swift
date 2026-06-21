import XCTest
@testable import VibePetCore

/// M5-1: `PreToolUse(tool_name == AskUserQuestion)` → `.question`. The mechanism is
/// verified supported (M5-0 spike, Claude Code ≥ 2.1.85; see
/// `Tests/Fixtures/claude/m5-question-spike-notes.md`): a hook can satisfy
/// AskUserQuestion via `updatedInput`, so VibePet parses the questions for in-bubble
/// answering. Field names follow the real `AskUserQuestion` input schema.
final class ClaudeCodeQuestionParseTests: XCTestCase {
    private let adapter = ClaudeCodeAdapter()

    func testAskUserQuestionParsesToQuestion() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("ask-user-question.json"), env: [:]))
        let content = try question(envelope)

        XCTAssertEqual(content.questions.count, 1)
        let item = try XCTUnwrap(content.questions.first)
        XCTAssertEqual(item.header, "Database")
        XCTAssertEqual(item.prompt, "Which database should we use?")
        XCTAssertFalse(item.multiSelect)
        // The adapter appends a synthetic "其他" free-text choice to every question.
        XCTAssertEqual(item.options.map(\.label), ["SQLite", "Postgres", "其他"])
        XCTAssertEqual(item.options.first?.detail, "Lightweight, zero-config")
        XCTAssertEqual(item.options.first?.allowsFreeform, false)
        XCTAssertEqual(item.options.last?.allowsFreeform, true, "the appended 其他 option is freeform")

        XCTAssertEqual(envelope.source.tool, .claudeCode)
        XCTAssertEqual(envelope.source.projectName, "VibePet")
    }

    func testQuestionNeedsResponse() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("ask-user-question.json"), env: [:]))
        // `.question.needsResponse == true` → the CLI blocks for the answer and the
        // App enters `decide`, reusing the M4 round-trip.
        XCTAssertTrue(envelope.content.needsResponse)
    }

    func testMultiSelectIsPreserved() throws {
        let stdin = try json([
            "hook_event_name": "PreToolUse",
            "session_id": "a1b2c3d4e5f6",
            "tool_name": "AskUserQuestion",
            "tool_input": [
                "questions": [[
                    "question": "Which features?",
                    "header": "Features",
                    "multiSelect": true,
                    "options": [["label": "A", "description": "first"], ["label": "B"]],
                ]],
            ],
        ])
        let content = try question(try XCTUnwrap(adapter.parseEvent(stdin: stdin, env: [:])))
        let item = try XCTUnwrap(content.questions.first)
        XCTAssertTrue(item.multiSelect)
        XCTAssertEqual(item.options.map(\.label), ["A", "B", "其他"])
        XCTAssertNil(item.options[1].detail, "an option without a description maps to nil detail")
    }

    func testAskUserQuestionIsNotAnApproval() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("ask-user-question.json"), env: [:]))
        if case .approval = envelope.content {
            XCTFail("AskUserQuestion must become a question, never an approval")
        }
    }

    // MARK: - Helpers

    private struct NotQuestion: Error {}

    private func question(
        _ envelope: BridgeEnvelope,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> QuestionContent {
        guard case let .question(content) = envelope.content else {
            XCTFail("Expected .question, got \(envelope.content)", file: file, line: line)
            throw NotQuestion()
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

import XCTest
@testable import VibePetCore

/// M5-3: a `.question(QuestionAnswer)` response encodes to Claude Code's
/// `AskUserQuestion` hook output — `permissionDecision:"allow"` + an `updatedInput`
/// that carries the questions plus the user's answers (keyed by question text), so
/// the tool proceeds without a native prompt (verified ≥ 2.1.85). No usable
/// selection defers (no JSON), keeping the path fail-open.
final class ClaudeCodeQuestionEncodeTests: XCTestCase {
    private let adapter = ClaudeCodeAdapter()

    func testSingleSelectEncodesAllowWithUpdatedInput() throws {
        let envelope = try questionEnvelope()
        let answer = QuestionAnswer(answers: ["Database": "SQLite"])

        let output = try decode(adapter.encodeResponse(.question(answer), for: envelope))
        let hook = try XCTUnwrap(output["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(hook["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(hook["permissionDecision"] as? String, "allow")

        let updatedInput = try XCTUnwrap(hook["updatedInput"] as? [String: Any])
        let answers = try XCTUnwrap(updatedInput["answers"] as? [String: String])
        // `answers` is keyed by question text, not header — translated via the item.
        XCTAssertEqual(answers["Which database should we use?"], "SQLite")

        // updatedInput replaces the whole input, so the questions must be preserved —
        // but the UI-only "其他" option must be stripped back out.
        let questions = try XCTUnwrap(updatedInput["questions"] as? [[String: Any]])
        XCTAssertEqual(questions.count, 1)
        XCTAssertEqual(questions.first?["question"] as? String, "Which database should we use?")
        let labels = (questions.first?["options"] as? [[String: Any]])?.compactMap { $0["label"] as? String }
        XCTAssertEqual(labels, ["SQLite", "Postgres"], "the synthetic 其他 option is not written back to the tool")
    }

    func testMultiSelectAnswerIsCarriedThrough() throws {
        let envelope = try multiSelectEnvelope()
        // The card joins multi-select labels with ", " (matching Claude Code's CLI);
        // the adapter passes that value straight through, keyed by question text.
        let answer = QuestionAnswer(answers: ["Features": "A, B"])

        let output = try decode(adapter.encodeResponse(.question(answer), for: envelope))
        let updatedInput = try XCTUnwrap((output["hookSpecificOutput"] as? [String: Any])?["updatedInput"] as? [String: Any])
        let answers = try XCTUnwrap(updatedInput["answers"] as? [String: String])
        XCTAssertEqual(answers["Which features?"], "A, B")
    }

    func testNoSelectionDefersWithNoJSON() throws {
        let envelope = try questionEnvelope()
        let empty = QuestionAnswer(answers: [:])
        // Defer == no stdout JSON + exit 0 → native prompt (fail-open).
        XCTAssertTrue(adapter.encodeResponse(.question(empty), for: envelope).isEmpty)
    }

    func testQuestionResponseOnNonQuestionEnvelopeDefers() {
        let envelope = BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .claudeCode, projectName: nil, sessionShortId: nil, cwd: nil),
            content: .status(StatusContent(text: "x"))
        )
        let answer = QuestionAnswer(answers: ["Database": "SQLite"])
        XCTAssertTrue(adapter.encodeResponse(.question(answer), for: envelope).isEmpty)
    }

    // MARK: - Helpers

    private func questionEnvelope() throws -> BridgeEnvelope {
        try XCTUnwrap(adapter.parseEvent(stdin: fixture("ask-user-question.json"), env: [:]))
    }

    private func multiSelectEnvelope() throws -> BridgeEnvelope {
        let stdin = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PreToolUse",
            "tool_name": "AskUserQuestion",
            "tool_input": [
                "questions": [[
                    "question": "Which features?",
                    "header": "Features",
                    "multiSelect": true,
                    "options": [["label": "A"], ["label": "B"]],
                ]],
            ],
        ])
        return try XCTUnwrap(adapter.parseEvent(stdin: stdin, env: [:]))
    }

    private func decode(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
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

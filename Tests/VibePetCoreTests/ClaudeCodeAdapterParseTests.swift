import XCTest
@testable import VibePetCore

final class ClaudeCodeAdapterParseTests: XCTestCase {
    // MARK: - Stop → completion

    func testStopWithInlineSummaryBecomesCompletion() throws {
        let adapter = ClaudeCodeAdapter(transcriptSummaryReader: { _ in
            XCTFail("Inline summary should win before reading the transcript")
            return nil
        })
        let stdin = try json([
            "hook_event_name": "Stop",
            "session_id": "a1b2c3d4e5f6",
            "cwd": "/Users/dev/Projects/VibePet",
            "summary": "新增 3 个测试，全部通过"
        ])

        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: stdin, env: [:]))

        guard case let .completion(content) = envelope.content else {
            return XCTFail("Expected .completion, got \(envelope.content)")
        }
        XCTAssertEqual(content.markdownSummary, "新增 3 个测试，全部通过")
        XCTAssertFalse(content.isError)
    }

    func testStopUsesTranscriptSummaryWhenNoInlineSummary() throws {
        let adapter = ClaudeCodeAdapter(transcriptSummaryReader: { path in
            XCTAssertEqual(path, "/tmp/claude/transcript.jsonl")
            return "从 transcript 提取的摘要"
        })
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("stop.json"), env: [:]))

        guard case let .completion(content) = envelope.content else {
            return XCTFail("Expected .completion, got \(envelope.content)")
        }
        XCTAssertEqual(content.markdownSummary, "从 transcript 提取的摘要")
    }

    func testStopWithoutSummaryUsesReadableFallback() throws {
        let adapter = ClaudeCodeAdapter(transcriptSummaryReader: { _ in nil })
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("stop.json"), env: [:]))

        guard case let .completion(content) = envelope.content else {
            return XCTFail("Expected .completion, got \(envelope.content)")
        }
        XCTAssertEqual(content.markdownSummary, ClaudeCodeAdapter.completionFallback)
        XCTAssertFalse(content.markdownSummary.isEmpty)
    }

    func testStopMarksErrorWhenFlagged() throws {
        let adapter = ClaudeCodeAdapter(transcriptSummaryReader: { _ in nil })
        let stdin = try json([
            "hook_event_name": "Stop",
            "session_id": "a1b2c3d4e5f6",
            "is_error": true
        ])

        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: stdin, env: [:]))

        guard case let .completion(content) = envelope.content else {
            return XCTFail("Expected .completion, got \(envelope.content)")
        }
        XCTAssertTrue(content.isError)
    }

    func testTranscriptReaderExtractsLastAssistantText() throws {
        let summary = ClaudeCodeAdapter.readTranscriptSummary(path: fixturePath("transcript.jsonl"))
        XCTAssertEqual(summary, "我新增了 3 个测试，全部通过 ✅")
    }

    // MARK: - Notification → status

    func testNotificationBecomesSingleLineStatus() throws {
        let adapter = ClaudeCodeAdapter()
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("notification.json"), env: [:]))

        guard case let .status(content) = envelope.content else {
            return XCTFail("Expected .status, got \(envelope.content)")
        }
        XCTAssertEqual(content.text, "Claude is waiting for your input")
    }

    func testNotificationCollapsesMultilineMessage() throws {
        let adapter = ClaudeCodeAdapter()
        let stdin = try json([
            "hook_event_name": "Notification",
            "message": "line one\nline two"
        ])

        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: stdin, env: [:]))

        guard case let .status(content) = envelope.content else {
            return XCTFail("Expected .status, got \(envelope.content)")
        }
        XCTAssertEqual(content.text, "line one line two")
    }

    // MARK: - SourceInfo

    func testSourceInfoCarriesToolProjectAndSession() throws {
        let adapter = ClaudeCodeAdapter(transcriptSummaryReader: { _ in nil })
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("stop.json"), env: [:]))

        XCTAssertEqual(envelope.source.tool, .claudeCode)
        XCTAssertEqual(envelope.source.projectName, "VibePet")
        XCTAssertEqual(envelope.source.sessionShortId, "a1b2c3")
        XCTAssertEqual(envelope.source.cwd, "/Users/dev/Projects/VibePet")
    }

    // MARK: - Out-of-scope events

    func testUnhandledEventReturnsNil() throws {
        // PreToolUse is now handled (M4); an unrelated event still returns nil.
        let adapter = ClaudeCodeAdapter()
        let unrelated = try json(["hook_event_name": "SessionStart"])
        XCTAssertNil(try adapter.parseEvent(stdin: unrelated, env: [:]))
    }

    func testMalformedInputReturnsNil() throws {
        let adapter = ClaudeCodeAdapter()
        XCTAssertNil(try adapter.parseEvent(stdin: Data("not json".utf8), env: [:]))
    }

    // MARK: - Fixtures

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

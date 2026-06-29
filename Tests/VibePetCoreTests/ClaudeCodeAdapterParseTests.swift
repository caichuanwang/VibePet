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
        XCTAssertEqual(envelope.source.sessionID, "a1b2c3d4e5f6")
        XCTAssertEqual(envelope.source.sessionShortId, "a1b2c3")
        XCTAssertEqual(envelope.source.cwd, "/Users/dev/Projects/VibePet")
    }

    func testSourceInfoCarriesHookCapturedJumpTarget() throws {
        let adapter = ClaudeCodeAdapter(
            transcriptSummaryReader: { _ in nil },
            terminalJumpCapture: TerminalJumpCapture(
                currentTTYProvider: { "/dev/ttys001" },
                terminalLocator: { app in
                    XCTAssertEqual(app, "Terminal")
                    return TerminalJumpCapture.LocatorSnapshot(
                        sessionID: nil,
                        tty: "/dev/ttys111",
                        title: "Claude"
                    )
                }
            )
        )

        let envelope = try XCTUnwrap(adapter.parseEvent(
            stdin: fixture("stop.json"),
            env: ["TERM_PROGRAM": "Apple_Terminal"]
        ))

        XCTAssertEqual(envelope.source.jumpTarget?.terminalApp, "Terminal")
        XCTAssertEqual(envelope.source.jumpTarget?.workspaceName, "VibePet")
        XCTAssertEqual(envelope.source.jumpTarget?.workingDirectory, "/Users/dev/Projects/VibePet")
        XCTAssertEqual(envelope.source.jumpTarget?.terminalTTY, "/dev/ttys111")
        XCTAssertEqual(envelope.source.jumpTarget?.paneTitle, "Claude")
    }

    func testJumpTargetCaptureFailureKeepsEnvelopeFailOpen() throws {
        let adapter = ClaudeCodeAdapter(
            transcriptSummaryReader: { _ in nil },
            terminalJumpCapture: TerminalJumpCapture(
                currentTTYProvider: { nil },
                terminalLocator: { _ in nil }
            )
        )

        let envelope = try XCTUnwrap(adapter.parseEvent(
            stdin: fixture("stop.json"),
            env: ["TERM_PROGRAM": "iTerm.app"]
        ))

        XCTAssertEqual(envelope.source.jumpTarget?.terminalApp, "iTerm")
        XCTAssertEqual(envelope.source.jumpTarget?.workingDirectory, "/Users/dev/Projects/VibePet")
        XCTAssertNil(envelope.source.jumpTarget?.terminalSessionID)
        XCTAssertNil(envelope.source.jumpTarget?.terminalTTY)
    }

    // MARK: - Lifecycle AgentEvent

    func testSessionStartBecomesAgentEvent() throws {
        let adapter = ClaudeCodeAdapter()
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("session-start.json"), env: [:]))

        guard case let .sessionStarted(sessionID, _, title, tool, summary, _) = envelope.agentEvent else {
            return XCTFail("Expected sessionStarted, got \(String(describing: envelope.agentEvent))")
        }
        XCTAssertEqual(sessionID, "a1b2c3d4e5f6")
        XCTAssertEqual(title, "VibePet")
        XCTAssertEqual(tool, .claudeCode)
        XCTAssertEqual(summary, "Claude Code session started")
        XCTAssertFalse(envelope.content.needsResponse)
    }

    func testLifecycleActivityEventsBecomeActivityUpdated() throws {
        let adapter = ClaudeCodeAdapter()
        let fixtureNames = [
            "user-prompt-submit.json",
            "subagent-start.json",
            "subagent-stop.json",
            "pre-compact.json",
            "notification.json",
        ]

        for name in fixtureNames {
            let event = try XCTUnwrap(adapter.parseAgentEvent(stdin: fixture(name), env: [:]), name)
            guard case let .activityUpdated(sessionID, _, summary) = event else {
                return XCTFail("Expected activityUpdated for \(name), got \(event)")
            }
            XCTAssertEqual(sessionID, "a1b2c3d4e5f6")
            XCTAssertFalse(summary.isEmpty)
        }
    }

    func testPostToolUseIsIgnored() throws {
        let adapter = ClaudeCodeAdapter()

        XCTAssertNil(try adapter.parseEvent(stdin: fixture("post-tool-use.json"), env: [:]))
        XCTAssertNil(try adapter.parseAgentEvent(stdin: fixture("post-tool-use.json"), env: [:]))
    }

    func testPreToolUseMapsToActivityUpdated() throws {
        let adapter = ClaudeCodeAdapter()

        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("pretooluse-bash.json"), env: [:]))

        XCTAssertFalse(envelope.content.needsResponse)
        guard case let .status(content) = envelope.content else {
            return XCTFail("Expected status, got \(envelope.content)")
        }
        guard case let .activityUpdated(sessionID, _, summary) = envelope.agentEvent else {
            return XCTFail("Expected activityUpdated, got \(String(describing: envelope.agentEvent))")
        }
        XCTAssertEqual(content.text, "Claude Code PreToolUse: Bash")
        XCTAssertEqual(sessionID, "a1b2c3d4e5f6")
        XCTAssertEqual(summary, "Claude Code PreToolUse: Bash")
    }

    func testPermissionRequestMapsDecisionAgentEvents() throws {
        let adapter = ClaudeCodeAdapter()

        let approvalEvent = try XCTUnwrap(adapter.parseEvent(stdin: fixture("permission-request-bash.json"), env: [:])?.agentEvent)
        let questionEvent = try XCTUnwrap(adapter.parseEvent(stdin: fixture("permission-request-ask-user-question.json"), env: [:])?.agentEvent)

        guard case let .permissionRequested(approvalSessionID, _, approvalSummary) = approvalEvent else {
            return XCTFail("Expected permissionRequested, got \(approvalEvent)")
        }
        guard case let .questionAsked(questionSessionID, _, questionSummary) = questionEvent else {
            return XCTFail("Expected questionAsked, got \(questionEvent)")
        }
        XCTAssertEqual(approvalSessionID, "a1b2c3d4e5f6")
        XCTAssertEqual(questionSessionID, "a1b2c3d4e5f6")
        XCTAssertTrue(approvalSummary.contains("Bash"))
        XCTAssertEqual(questionSummary, ClaudeCodeAdapter.askQuestionTitle)
    }

    func testStopFailureAndSessionEndCompletionFlags() throws {
        let adapter = ClaudeCodeAdapter()

        let failure = try XCTUnwrap(adapter.parseAgentEvent(stdin: fixture("stop-failure.json"), env: [:]))
        let end = try XCTUnwrap(adapter.parseAgentEvent(stdin: fixture("session-end.json"), env: [:]))

        guard case let .sessionCompleted(_, _, _, failureIsError, failureIsEnd) = failure else {
            return XCTFail("Expected sessionCompleted, got \(failure)")
        }
        guard case let .sessionCompleted(_, _, _, endIsError, endIsEnd) = end else {
            return XCTFail("Expected sessionCompleted, got \(end)")
        }
        XCTAssertTrue(failureIsError)
        XCTAssertFalse(failureIsEnd)
        XCTAssertFalse(endIsError)
        XCTAssertTrue(endIsEnd)
    }

    func testPermissionDeniedBecomesActionableStateResolved() throws {
        let adapter = ClaudeCodeAdapter()
        let event = try XCTUnwrap(adapter.parseAgentEvent(stdin: fixture("permission-denied.json"), env: [:]))

        guard case let .actionableStateResolved(sessionID, _, summary) = event else {
            return XCTFail("Expected actionableStateResolved, got \(event)")
        }
        XCTAssertEqual(sessionID, "a1b2c3d4e5f6")
        XCTAssertEqual(summary, "Permission was denied in the terminal")
    }

    func testMalformedLifecyclePayloadFailsOpen() throws {
        let adapter = ClaudeCodeAdapter()
        let missingSessionID = try json([
            "hook_event_name": "SessionStart",
            "cwd": "/tmp/VibePet",
        ])

        XCTAssertNil(try adapter.parseAgentEvent(stdin: missingSessionID, env: [:]))
        XCTAssertNil(try adapter.parseEvent(stdin: missingSessionID, env: [:]))
    }

    // MARK: - Out-of-scope events

    func testUnhandledEventReturnsNil() throws {
        let adapter = ClaudeCodeAdapter()
        let unrelated = try json(["hook_event_name": "SomethingElse"])
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

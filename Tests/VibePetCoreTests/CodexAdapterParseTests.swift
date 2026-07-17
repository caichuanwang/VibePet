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
        XCTAssertEqual(envelope.source.sessionID, "9f8e7d6c5b4a3210")
        XCTAssertEqual(envelope.source.sessionShortId, "9f8e7d")
        XCTAssertTrue(envelope.content.needsResponse)
        guard case let .permissionRequested(sessionID, _, summary) = envelope.agentEvent else {
            return XCTFail("Expected permissionRequested, got \(String(describing: envelope.agentEvent))")
        }
        XCTAssertEqual(sessionID, "9f8e7d6c5b4a3210")
        XCTAssertEqual(summary, "Codex PermissionRequest: Bash")
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
        XCTAssertEqual(envelope.source.sessionID, "c0ffee123456")
        XCTAssertEqual(envelope.source.sessionShortId, "c0ffee")
        XCTAssertEqual(envelope.source.jumpTarget?.terminalApp, "Unknown")
        XCTAssertEqual(envelope.source.jumpTarget?.workingDirectory, "/Users/dev/Projects/VibePet")
    }

    func testNotifyAgentTurnCompleteUsesFixtureBackedThreadIDOnly() throws {
        let stdin = try json([
            "type": "agent-turn-complete",
            "thread-id": "codex-thread-1",
            "session_id": "unverified-session-alias",
            "thread_id": "unverified-thread-alias",
            "turn-id": "turn-is-not-a-session",
            "cwd": "/Users/dev/Projects/VibePet",
            "last-assistant-message": "Done",
        ])

        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: stdin, env: [:]))

        XCTAssertEqual(envelope.source.sessionID, "codex-thread-1")
        XCTAssertEqual(envelope.source.jumpTarget?.terminalApp, "Unknown")
        XCTAssertEqual(envelope.source.jumpTarget?.workingDirectory, "/Users/dev/Projects/VibePet")
        guard case let .sessionCompleted(sessionID, _, summary, _, _) = envelope.agentEvent else {
            return XCTFail("Expected sessionCompleted, got \(String(describing: envelope.agentEvent))")
        }
        XCTAssertEqual(sessionID, "codex-thread-1")
        XCTAssertEqual(summary, "Done")
    }

    func testNotifyDoesNotTreatUnverifiedAliasesAsSessionIdentity() throws {
        let stdin = try json([
            "type": "agent-turn-complete",
            "session_id": "hook-only-session",
            "thread_id": "unverified-thread",
            "turn-id": "turn-is-not-a-session",
            "last-assistant-message": "Done",
        ])

        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: stdin, env: [:]))

        XCTAssertEqual(envelope.source.sessionID, "unknown-codex")
        XCTAssertNil(envelope.agentEvent)
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
        XCTAssertEqual(envelope.source.sessionID, "9f8e7d6c5b4a3210")
        XCTAssertEqual(envelope.source.sessionShortId, "9f8e7d")
    }

    func testUnrelatedNotifyTypeIsIgnored() throws {
        let stdin = try json(["type": "session-configured", "thread-id": "abc"])
        XCTAssertNil(try adapter.parseEvent(stdin: stdin, env: [:]))
    }

    func testSessionStartBecomesAgentEvent() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("session-start.json"), env: [:]))

        guard case let .sessionStarted(sessionID, _, title, tool, summary, _) = envelope.agentEvent else {
            return XCTFail("Expected sessionStarted, got \(String(describing: envelope.agentEvent))")
        }
        XCTAssertEqual(sessionID, "9f8e7d6c5b4a3210")
        XCTAssertEqual(title, "VibePet")
        XCTAssertEqual(tool, .codex)
        XCTAssertEqual(summary, "Codex session started")
        XCTAssertFalse(envelope.content.needsResponse)
    }

    func testSourceInfoCarriesHookCapturedJumpTarget() throws {
        let adapter = CodexAdapter(terminalJumpCapture: TerminalJumpCapture(
            currentTTYProvider: { "/dev/ttys003" },
            terminalLocator: { app, tty in
                XCTAssertEqual(app, "iTerm")
                XCTAssertEqual(tty, "/dev/ttys003")
                return TerminalJumpCapture.LocatorSnapshot(
                    sessionID: "iterm-session",
                    tty: "/dev/ttys003",
                    title: "Codex"
                )
            }
        ))

        let envelope = try XCTUnwrap(adapter.parseEvent(
            stdin: fixture("session-start.json"),
            env: ["TERM_PROGRAM": "iTerm.app"]
        ))

        XCTAssertEqual(envelope.source.jumpTarget?.terminalApp, "iTerm")
        XCTAssertEqual(envelope.source.jumpTarget?.workspaceName, "VibePet")
        XCTAssertEqual(envelope.source.jumpTarget?.terminalSessionID, "iterm-session")
        XCTAssertEqual(envelope.source.jumpTarget?.terminalTTY, "/dev/ttys003")
        XCTAssertEqual(envelope.source.jumpTarget?.paneTitle, "Codex")
    }

    func testUserPromptSubmitBecomesActivityUpdated() throws {
        let event = try XCTUnwrap(adapter.parseAgentEvent(stdin: fixture("user-prompt-submit.json"), env: [:]))

        guard case let .activityUpdated(sessionID, _, summary) = event else {
            return XCTFail("Expected activityUpdated, got \(event)")
        }
        XCTAssertEqual(sessionID, "9f8e7d6c5b4a3210")
        XCTAssertEqual(summary, "User prompt: Run the tests")
    }

    func testPostToolUseIsIgnored() throws {
        XCTAssertNil(try adapter.parseEvent(stdin: fixture("post-tool-use.json"), env: [:]))
        XCTAssertNil(try adapter.parseAgentEvent(stdin: fixture("post-tool-use.json"), env: [:]))
    }

    func testPostToolUseMissingSessionIDIsIgnored() throws {
        let stdin = try json([
            "hook_event_name": "PostToolUse",
            "cwd": "/tmp",
            "tool_name": "Bash",
        ])

        XCTAssertNil(try adapter.parseEvent(stdin: stdin, env: [:]))
        XCTAssertNil(try adapter.parseAgentEvent(stdin: stdin, env: [:]))
    }

    func testUnsupportedHookEventIsIgnored() throws {
        let stdin = try json([
            "hook_event_name": "SubagentStart",
            "session_id": "x",
            "cwd": "/tmp",
        ])
        XCTAssertNil(try adapter.parseEvent(stdin: stdin, env: [:]))
    }

    func testLifecycleEventMissingSessionIDIsIgnored() throws {
        let stdin = try json([
            "hook_event_name": "SessionStart",
            "cwd": "/tmp",
        ])
        XCTAssertNil(try adapter.parseEvent(stdin: stdin, env: [:]))
        XCTAssertNil(try adapter.parseAgentEvent(stdin: stdin, env: [:]))
    }

    func testMalformedInputIsIgnored() throws {
        XCTAssertNil(try adapter.parseEvent(stdin: Data("not json".utf8), env: [:]))
    }

    func testUnverifiedAnswerRequiringToolDoesNotInventTerminalCapability() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixture("permission-request-ask-question.json"), env: [:]))
        let content = try approval(envelope)
        XCTAssertFalse(content.requiresTerminalApproval)
        XCTAssertNil(content.alwaysAllow)
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

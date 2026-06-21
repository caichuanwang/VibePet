import XCTest
@testable import VibePetCore

final class HookRuntimeTests: XCTestCase {
    func testNotificationEnvelopeIsSent() async throws {
        let recorder = EnvelopeRecorder()
        let stub = StubAdapter(result: .success(notificationEnvelope))
        let runtime = HookRuntime(adapter: stub, sendNotification: { envelope in
            await recorder.record(envelope)
        })

        let outcome = await runtime.run(stdin: Data("{}".utf8), env: [:])

        XCTAssertEqual(outcome, .sent)
        let sent = await recorder.envelopes
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.content, .status(StatusContent(text: "hi")))
    }

    func testIgnoredEventDefersWithoutSending() async throws {
        let recorder = EnvelopeRecorder()
        let stub = StubAdapter(result: .success(nil))
        let runtime = HookRuntime(adapter: stub, sendNotification: { envelope in
            await recorder.record(envelope)
        })

        let outcome = await runtime.run(stdin: Data("{}".utf8), env: [:])

        XCTAssertEqual(outcome, .deferred)
        let sent = await recorder.envelopes
        XCTAssertTrue(sent.isEmpty)
    }

    func testParseFailureDefers() async throws {
        let recorder = EnvelopeRecorder()
        let stub = StubAdapter(result: .failure(StubError()))
        let runtime = HookRuntime(adapter: stub, sendNotification: { envelope in
            await recorder.record(envelope)
        })

        let outcome = await runtime.run(stdin: Data("{}".utf8), env: [:])

        XCTAssertEqual(outcome, .deferred)
        let sent = await recorder.envelopes
        XCTAssertTrue(sent.isEmpty)
    }

    func testResponseBearingEnvelopeIsNotSentAsNotification() async throws {
        // Approval must NOT go through the one-way notification path.
        let recorder = EnvelopeRecorder()
        let stub = StubAdapter(result: .success(approvalEnvelope))
        let runtime = HookRuntime(adapter: stub, sendNotification: { envelope in
            await recorder.record(envelope)
        })

        _ = await runtime.run(stdin: Data("{}".utf8), env: [:])

        let sent = await recorder.envelopes
        XCTAssertTrue(sent.isEmpty, "approval must not be sent as a notification")
    }

    // MARK: - Decision round trip (M4-4)

    func testDecisionPathEncodesResponse() async throws {
        let adapter = ClaudeCodeAdapter()
        let runtime = HookRuntime(
            adapter: adapter,
            sendNotification: { _ in XCTFail("decision must not use the notification path") },
            sendDecision: { envelope in
                BridgeResponseEnvelope(requestId: envelope.requestId, response: .approval(.deny(reason: "no")))
            }
        )

        let outcome = await runtime.run(stdin: try bashPreToolUse(), env: [:])

        guard case let .responded(data) = outcome else {
            return XCTFail("Expected .responded, got \(outcome)")
        }
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let output = try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(output["permissionDecision"] as? String, "deny")
        XCTAssertEqual(output["permissionDecisionReason"] as? String, "no")
    }

    func testDecisionDeferResponseProducesNoOutput() async throws {
        let runtime = HookRuntime(
            adapter: ClaudeCodeAdapter(),
            sendNotification: { _ in },
            sendDecision: { envelope in
                BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
            }
        )

        let outcome = await runtime.run(stdin: try bashPreToolUse(), env: [:])

        guard case let .responded(data) = outcome else {
            return XCTFail("Expected .responded, got \(outcome)")
        }
        XCTAssertTrue(data.isEmpty, "a defer response writes nothing to stdout")
    }

    func testDecisionSendFailureDefers() async throws {
        let runtime = HookRuntime(
            adapter: ClaudeCodeAdapter(),
            sendNotification: { _ in },
            sendDecision: { _ in throw StubError() }
        )

        let outcome = await runtime.run(stdin: try bashPreToolUse(), env: [:])

        XCTAssertEqual(outcome, .deferred)
    }

    func testDecisionWithNoInjectedSenderDefers() async throws {
        // Default decision sender throws → fail open rather than crash.
        let runtime = HookRuntime(adapter: ClaudeCodeAdapter(), sendNotification: { _ in })
        let outcome = await runtime.run(stdin: try bashPreToolUse(), env: [:])
        XCTAssertEqual(outcome, .deferred)
    }

    private func bashPreToolUse() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PreToolUse",
            "session_id": "a1b2c3d4",
            "cwd": "/tmp/proj",
            "tool_name": "Bash",
            "tool_input": ["command": "ls"],
        ])
    }

    func testSendFailureDefers() async throws {
        let stub = StubAdapter(result: .success(notificationEnvelope))
        let runtime = HookRuntime(adapter: stub, sendNotification: { _ in
            throw StubError()
        })

        let outcome = await runtime.run(stdin: Data("{}".utf8), env: [:])

        XCTAssertEqual(outcome, .deferred)
    }

    // MARK: - Diagnostics (VIBEPET_HOOKS_DEBUG)

    func testDecisionSendFailureInvokesLogger() async throws {
        let box = MessageBox()
        let runtime = HookRuntime(
            adapter: StubAdapter(result: .success(approvalEnvelope)),
            sendNotification: { _ in XCTFail("decision must not use the notification path") },
            sendDecision: { _ in throw StubError() },
            log: { box.append($0) }
        )

        let outcome = await runtime.run(stdin: Data("{}".utf8), env: [:])

        XCTAssertEqual(outcome, .deferred)
        XCTAssertEqual(box.messages.count, 1)
        XCTAssertTrue(box.messages.first?.contains("decision deferred") == true, "log should explain the fail-open")
    }

    func testNotificationSendFailureInvokesLogger() async throws {
        let box = MessageBox()
        let runtime = HookRuntime(
            adapter: StubAdapter(result: .success(notificationEnvelope)),
            sendNotification: { _ in throw StubError() },
            log: { box.append($0) }
        )

        let outcome = await runtime.run(stdin: Data("{}".utf8), env: [:])

        XCTAssertEqual(outcome, .deferred)
        XCTAssertEqual(box.messages.count, 1)
        XCTAssertTrue(box.messages.first?.contains("notification deferred") == true)
    }

    func testIgnoredEventDoesNotInvokeLogger() async throws {
        let box = MessageBox()
        let runtime = HookRuntime(
            adapter: StubAdapter(result: .success(nil)),
            sendNotification: { _ in },
            log: { box.append($0) }
        )

        _ = await runtime.run(stdin: Data("{}".utf8), env: [:])

        XCTAssertTrue(box.messages.isEmpty, "an ignored event is normal — no diagnostics noise")
    }

    // MARK: - Fixtures

    private var notificationEnvelope: BridgeEnvelope {
        BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .claudeCode, projectName: nil, sessionShortId: nil, cwd: nil),
            content: .status(StatusContent(text: "hi"))
        )
    }

    private var approvalEnvelope: BridgeEnvelope {
        BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .claudeCode, projectName: nil, sessionShortId: nil, cwd: nil),
            content: .approval(ApprovalContent(
                title: "run command",
                risk: .medium,
                preview: .command(text: "ls"),
                alwaysAllow: nil,
                requiresTerminalApproval: false
            ))
        )
    }
}

private struct StubAdapter: ToolAdapter {
    let tool: ToolKind = .claudeCode
    let result: Result<BridgeEnvelope?, Error>

    func parseEvent(stdin: Data, env: [String: String]) throws -> BridgeEnvelope? {
        try result.get()
    }

    func encodeResponse(_ response: BridgeResponse, for envelope: BridgeEnvelope) -> Data {
        Data()
    }
}

private struct StubError: Error {}

/// Thread-safe collector for the runtime's synchronous `@Sendable` log closure,
/// which may be invoked off the test's actor.
private final class MessageBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        storage.append(message)
    }

    var messages: [String] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

private actor EnvelopeRecorder {
    private(set) var envelopes: [BridgeEnvelope] = []

    func record(_ envelope: BridgeEnvelope) {
        envelopes.append(envelope)
    }
}

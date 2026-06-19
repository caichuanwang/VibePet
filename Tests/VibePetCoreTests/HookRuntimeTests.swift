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

    func testResponseBearingEnvelopeIsNotSentInThisMilestone() async throws {
        let recorder = EnvelopeRecorder()
        let stub = StubAdapter(result: .success(approvalEnvelope))
        let runtime = HookRuntime(adapter: stub, sendNotification: { envelope in
            await recorder.record(envelope)
        })

        let outcome = await runtime.run(stdin: Data("{}".utf8), env: [:])

        XCTAssertEqual(outcome, .deferred)
        let sent = await recorder.envelopes
        XCTAssertTrue(sent.isEmpty)
    }

    func testSendFailureDefers() async throws {
        let stub = StubAdapter(result: .success(notificationEnvelope))
        let runtime = HookRuntime(adapter: stub, sendNotification: { _ in
            throw StubError()
        })

        let outcome = await runtime.run(stdin: Data("{}".utf8), env: [:])

        XCTAssertEqual(outcome, .deferred)
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

private actor EnvelopeRecorder {
    private(set) var envelopes: [BridgeEnvelope] = []

    func record(_ envelope: BridgeEnvelope) {
        envelopes.append(envelope)
    }
}

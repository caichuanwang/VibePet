import XCTest
@testable import VibePetCore

/// M5-3: end-to-end question round trip across the real CLI path — stdin →
/// `ClaudeCodeAdapter` (AskUserQuestion → question) → `HookRuntime` blocking send →
/// `BridgeServer` answer reply → `encodeResponse` → stdout (`allow` + `updatedInput`)
/// — plus fail-open. The question card itself is App UI (covered by App tests /
/// manual demo); here we prove the blocking transport + `updatedInput` encode
/// contract over the same path approvals use (`question.needsResponse == true`).
final class QuestionFlowTests: XCTestCase {
    private let answer = QuestionAnswer(answers: ["Database": "SQLite"])

    func testQuestionRoundTripEncodesUpdatedInputToStdout() async throws {
        let outcome = try await runQuestion(replying: .question(answer))
        guard case let .responded(data) = outcome else {
            return XCTFail("Expected .responded, got \(outcome)")
        }
        let hook = try hookOutput(data)
        let decision = try XCTUnwrap(hook["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "allow")
        let updatedInput = try XCTUnwrap(decision["updatedInput"] as? [String: Any])
        let answers = try XCTUnwrap(updatedInput["answers"] as? [String: String])
        XCTAssertEqual(answers["Which database should we use?"], "SQLite")
        XCTAssertNotNil(updatedInput["questions"], "updatedInput must preserve the questions")
    }

    func testQuestionDeferProducesNoStdout() async throws {
        let outcome = try await runQuestion(replying: .defer)
        guard case let .responded(data) = outcome else {
            return XCTFail("Expected .responded, got \(outcome)")
        }
        XCTAssertTrue(data.isEmpty, "a defer reply writes nothing → native question prompt")
    }

    func testQuestionFailsOpenWithinTwoSecondsWhenAppNotRunning() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        // No server listening.
        let runtime = HookRuntime(
            adapter: ClaudeCodeAdapter(),
            client: BridgeClient(socketPath: socketPath)
        )

        let started = Date()
        let outcome = await runtime.run(stdin: fixture("permission-request-ask-user-question.json"), env: [:])
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(outcome, .deferred)
        XCTAssertLessThan(elapsed, 2.0)
    }

    /// Real binary: the `VibePetHooks` subprocess pointed at a temp socket must
    /// encode the answer to stdout (`allow` + `updatedInput`) and exit 0.
    func testHookBinaryWritesUpdatedInputStdout() async throws {
        let binary = try Self.hooksBinaryURL()
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)

        let reply = answer
        let server = BridgeServer(socketPath: socketPath) { envelope in
            BridgeResponseEnvelope(requestId: envelope.requestId, response: .question(reply))
        }
        try await server.start()
        defer { server.stop() }

        let process = Process()
        process.executableURL = binary
        process.environment = ["VIBEPET_SUPPORT_DIR": root.url.path]
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        try process.run()

        stdinPipe.fileHandleForWriting.write(fixture("permission-request-ask-user-question.json"))
        try stdinPipe.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(6)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            return XCTFail("VibePetHooks did not exit within 6s on the question path")
        }

        XCTAssertEqual(process.terminationStatus, 0, "hook CLI must exit 0")
        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let hook = try hookOutput(stdout)
        let decision = try XCTUnwrap(hook["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "allow")
        let answers = try XCTUnwrap((decision["updatedInput"] as? [String: Any])?["answers"] as? [String: String])
        XCTAssertEqual(answers["Which database should we use?"], "SQLite")
    }

    // MARK: - Helpers

    private func runQuestion(replying response: BridgeResponse) async throws -> HookRuntime.Outcome {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let server = BridgeServer(socketPath: socketPath) { envelope in
            BridgeResponseEnvelope(requestId: envelope.requestId, response: response)
        }
        try await server.start()
        defer { server.stop() }

        let runtime = HookRuntime(
            adapter: ClaudeCodeAdapter(),
            client: BridgeClient(socketPath: socketPath, readTimeout: 5)
        )
        return await runtime.run(stdin: fixture("permission-request-ask-user-question.json"), env: [:])
    }

    private func hookOutput(_ data: Data) throws -> [String: Any] {
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
    }

    private static func hooksBinaryURL() throws -> URL {
        let buildDir = Bundle(for: QuestionFlowTests.self)
            .bundleURL
            .deletingLastPathComponent()
        let candidate = buildDir.appendingPathComponent("VibePetHooks")
        guard FileManager.default.isExecutableFile(atPath: candidate.path) else {
            throw XCTSkip("VibePetHooks binary not found at \(candidate.path)")
        }
        return candidate
    }

    private func fixture(_ name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/claude/\(name)")
        return (try? Data(contentsOf: url)) ?? Data()
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vp-question-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

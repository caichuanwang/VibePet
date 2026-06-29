import XCTest
@testable import VibePetCore

/// M4-8: end-to-end approval round trip across the real CLI path — stdin →
/// `ClaudeCodeAdapter` (PermissionRequest → approval) → `HookRuntime` blocking send →
/// `BridgeServer` decision reply → `encodeResponse` → stdout — plus the fail-open
/// timing guarantees. The approval card itself is App UI (covered by App tests /
/// manual demo); here we prove the blocking transport + encode contract.
final class ApprovalFlowTests: XCTestCase {
    func testDenyRoundTripEncodesDenyToStdout() async throws {
        let response = try await runApproval(replying: .approval(.deny(reason: "用户拒绝")))
        guard case let .responded(data) = response else {
            return XCTFail("Expected .responded, got \(response)")
        }
        let output = try hookOutput(data)
        let decision = try XCTUnwrap(output["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "deny")
        XCTAssertEqual(decision["message"] as? String, "用户拒绝")
    }

    func testAllowOnceRoundTripEncodesAllowToStdout() async throws {
        let response = try await runApproval(replying: .approval(.allowOnce))
        guard case let .responded(data) = response else {
            return XCTFail("Expected .responded, got \(response)")
        }
        let output = try hookOutput(data)
        let decision = try XCTUnwrap(output["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "allow")
    }

    func testDeferReplyProducesNoStdout() async throws {
        let response = try await runApproval(replying: .defer)
        guard case let .responded(data) = response else {
            return XCTFail("Expected .responded, got \(response)")
        }
        XCTAssertTrue(data.isEmpty, "a defer reply writes nothing → native permission flow")
    }

    func testApprovalFailsOpenWithinTwoSecondsWhenAppNotRunning() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        // No server listening.
        let runtime = HookRuntime(
            adapter: ClaudeCodeAdapter(),
            client: BridgeClient(socketPath: socketPath)
        )

        let started = Date()
        let outcome = await runtime.run(stdin: fixture("permission-request-bash.json"), env: [:])
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(outcome, .deferred)
        XCTAssertLessThan(elapsed, 2.0)
    }

    func testApprovalFailsOpenWhenUserDoesNotRespond() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        // Server accepts but never replies (handler stalls past the read deadline).
        let server = BridgeServer(socketPath: socketPath) { _ in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            return BridgeResponseEnvelope(requestId: UUID(), response: .defer)
        }
        try await server.start()
        defer { server.stop() }

        // Short read deadline so the test is fast; the CLI maps the timeout to defer.
        let runtime = HookRuntime(
            adapter: ClaudeCodeAdapter(),
            client: BridgeClient(socketPath: socketPath, readTimeout: 0.4)
        )
        let outcome = await runtime.run(stdin: fixture("permission-request-bash.json"), env: [:])
        XCTAssertEqual(outcome, .deferred)
    }

    /// Real binary: the `VibePetHooks` subprocess pointed at a temp socket (via
    /// `VIBEPET_SUPPORT_DIR`) must encode the decision to stdout and exit 0.
    func testHookBinaryWritesDecisionStdout() async throws {
        let binary = try Self.hooksBinaryURL()
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)

        let server = BridgeServer(socketPath: socketPath) { envelope in
            BridgeResponseEnvelope(requestId: envelope.requestId, response: .approval(.deny(reason: "blocked")))
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

        stdinPipe.fileHandleForWriting.write(fixture("permission-request-bash.json"))
        try stdinPipe.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(6)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            return XCTFail("VibePetHooks did not exit within 6s on the approval path")
        }

        XCTAssertEqual(process.terminationStatus, 0, "hook CLI must exit 0")
        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let output = try hookOutput(stdout)
        let decision = try XCTUnwrap(output["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "deny")
        XCTAssertEqual(decision["message"] as? String, "blocked")
    }

    // MARK: - Helpers

    /// Runs the real CLI runtime against a real server that replies `response`,
    /// returning the runtime outcome.
    private func runApproval(replying response: BridgeResponse) async throws -> HookRuntime.Outcome {
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
        return await runtime.run(stdin: fixture("permission-request-bash.json"), env: [:])
    }

    private func hookOutput(_ data: Data) throws -> [String: Any] {
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
    }

    private static func hooksBinaryURL() throws -> URL {
        let buildDir = Bundle(for: ApprovalFlowTests.self)
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
            .appendingPathComponent("vp-approval-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

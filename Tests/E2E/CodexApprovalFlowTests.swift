import XCTest
@testable import VibePetCore

/// M6-2 E2E: Codex approval round trip across the real CLI path — stdin →
/// `CodexAdapter` (PermissionRequest → approval) → `HookRuntime` blocking send →
/// `BridgeServer` decision reply → `encodeResponse` → stdout — plus fail-open timing
/// and the `--tool codex` adapter selection in the real binary. The approval card is
/// App UI (App tests / manual demo); here we prove the transport + encode contract.
final class CodexApprovalFlowTests: XCTestCase {
    func testDenyRoundTripEncodesDenyToStdout() async throws {
        let response = try await runApproval(replying: .approval(.deny(reason: "blocked")))
        guard case let .responded(data) = response else {
            return XCTFail("Expected .responded, got \(response)")
        }
        let decision = try decision(in: data)
        XCTAssertEqual(decision["behavior"] as? String, "deny")
        XCTAssertEqual(decision["message"] as? String, "blocked")
    }

    func testAllowOnceRoundTripEncodesAllowToStdout() async throws {
        let response = try await runApproval(replying: .approval(.allowOnce))
        guard case let .responded(data) = response else {
            return XCTFail("Expected .responded, got \(response)")
        }
        XCTAssertEqual(try decision(in: data)["behavior"] as? String, "allow")
    }

    func testDeferReplyProducesNoStdout() async throws {
        // Codex decline = no output → Codex uses its native approval flow.
        let response = try await runApproval(replying: .defer)
        guard case let .responded(data) = response else {
            return XCTFail("Expected .responded, got \(response)")
        }
        XCTAssertTrue(data.isEmpty)
    }

    func testFailsOpenWithinTwoSecondsWhenAppNotRunning() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let runtime = HookRuntime(adapter: CodexAdapter(), client: BridgeClient(socketPath: socketPath))

        let started = Date()
        let outcome = await runtime.run(stdin: fixture("permission-request-shell.json"), env: [:])
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(outcome, .deferred)
        XCTAssertLessThan(elapsed, 2.0)
    }

    /// Real binary with `--tool codex`: the subprocess must select `CodexAdapter`,
    /// block for the decision, and encode the Codex allow decision to stdout.
    func testHookBinarySelectsCodexAdapterAndEncodesDecision() async throws {
        let binary = try Self.hooksBinaryURL()
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let server = BridgeServer(socketPath: socketPath) { envelope in
            BridgeResponseEnvelope(requestId: envelope.requestId, response: .approval(.allowOnce))
        }
        try await server.start()
        defer { server.stop() }

        let process = Process()
        process.executableURL = binary
        process.arguments = ["--tool", "codex"]
        process.environment = ["VIBEPET_SUPPORT_DIR": root.url.path]
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        try process.run()

        stdinPipe.fileHandleForWriting.write(fixture("permission-request-shell.json"))
        try stdinPipe.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(6)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            return XCTFail("VibePetHooks did not exit within 6s on the Codex approval path")
        }

        XCTAssertEqual(process.terminationStatus, 0, "hook CLI must exit 0")
        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        XCTAssertEqual(try decision(in: stdout)["behavior"] as? String, "allow")
    }

    // MARK: - Helpers

    private func runApproval(replying response: BridgeResponse) async throws -> HookRuntime.Outcome {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let server = BridgeServer(socketPath: socketPath) { envelope in
            BridgeResponseEnvelope(requestId: envelope.requestId, response: response)
        }
        try await server.start()
        defer { server.stop() }

        let runtime = HookRuntime(
            adapter: CodexAdapter(),
            client: BridgeClient(socketPath: socketPath, readTimeout: 5)
        )
        return await runtime.run(stdin: fixture("permission-request-shell.json"), env: [:])
    }

    private func decision(in data: Data) throws -> [String: Any] {
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let output = try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
        return try XCTUnwrap(output["decision"] as? [String: Any])
    }

    private static func hooksBinaryURL() throws -> URL {
        let buildDir = Bundle(for: CodexApprovalFlowTests.self).bundleURL.deletingLastPathComponent()
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
            .appendingPathComponent("Fixtures/codex/\(name)")
        return (try? Data(contentsOf: url)) ?? Data()
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vp-codex-e2e-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

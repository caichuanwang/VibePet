import XCTest
@testable import VibePetCore

/// End-to-end notification flow across the real CLI path: stdin → `ClaudeCodeAdapter`
/// → `HookRuntime` → `BridgeClient` → `BridgeServer`, plus `PetStateMachine`
/// routing (the bubble itself is App UI, covered by manual demo / unit tests).
final class NotificationFlowTests: XCTestCase {
    func testStopEventDeliversCompletionAndEntersNotify() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let recorder = EnvelopeRecorder()
        let server = BridgeServer(socketPath: socketPath) { envelope in
            await recorder.record(envelope)
            return BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }
        try await server.start()
        defer { server.stop() }

        let runtime = HookRuntime(
            adapter: ClaudeCodeAdapter(),
            client: BridgeClient(socketPath: socketPath)
        )
        let outcome = await runtime.run(stdin: fixture("stop.json"), env: [:])
        XCTAssertEqual(outcome, .sent)

        let envelope = try await waitForFirst(recorder)
        guard case .completion = envelope.content else {
            return XCTFail("Expected .completion, got \(envelope.content)")
        }

        var machine = PetStateMachine()
        XCTAssertTrue(machine.receive(envelope.content))
        XCTAssertEqual(machine.state, .notify)
    }

    func testNotificationEventDeliversStatus() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let recorder = EnvelopeRecorder()
        let server = BridgeServer(socketPath: socketPath) { envelope in
            await recorder.record(envelope)
            return BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }
        try await server.start()
        defer { server.stop() }

        let runtime = HookRuntime(
            adapter: ClaudeCodeAdapter(),
            client: BridgeClient(socketPath: socketPath)
        )
        let outcome = await runtime.run(stdin: fixture("notification.json"), env: [:])
        XCTAssertEqual(outcome, .sent)

        let envelope = try await waitForFirst(recorder)
        guard case let .status(status) = envelope.content else {
            return XCTFail("Expected .status, got \(envelope.content)")
        }
        XCTAssertEqual(status.text, "Claude is waiting for your input")
    }

    func testFailOpenDefersWithinTwoSecondsWhenAppNotRunning() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        // No server listening.
        let runtime = HookRuntime(
            adapter: ClaudeCodeAdapter(),
            client: BridgeClient(socketPath: socketPath)
        )

        let started = Date()
        let outcome = await runtime.run(stdin: fixture("stop.json"), env: [:])
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(outcome, .deferred)
        XCTAssertLessThan(elapsed, 2.0)
    }

    /// Runs the actual `VibePetHooks` executable as a subprocess so the process
    /// entry point (`main.swift` concurrency wiring) is exercised. A prior bug had
    /// `main.swift` block the main thread on a semaphore while a MainActor-inherited
    /// `Task` waited for that same thread — deadlocking every invocation. In-process
    /// tests await `HookRuntime.run` directly and never caught it; only spawning the
    /// real binary does. Whether the dev box has the App running or not, the CLI must
    /// exit promptly (send or fail-open) — never hang.
    func testHookCLIBinaryExitsPromptlyAndNeverHangs() throws {
        let binary = try Self.hooksBinaryURL()

        let process = Process()
        process.executableURL = binary
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        try process.run()

        stdinPipe.fileHandleForWriting.write(fixture("stop.json"))
        try stdinPipe.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(4)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }

        if process.isRunning {
            process.terminate()
            return XCTFail("VibePetHooks did not exit within 4s — CLI deadlock / fail-open regression")
        }

        XCTAssertEqual(process.terminationStatus, 0, "hook CLI must always exit 0")
        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        XCTAssertTrue(stdout.isEmpty, "M3 notification path must not print stdout")
    }

    // MARK: - Helpers

    /// The `VibePetHooks` binary built alongside this test bundle (same build
    /// config/triple). `VibePetE2ETests` depends on the executable so `swift test`
    /// builds it; skip cleanly if it is somehow absent.
    private static func hooksBinaryURL() throws -> URL {
        let buildDir = Bundle(for: NotificationFlowTests.self)
            .bundleURL
            .deletingLastPathComponent()
        let candidate = buildDir.appendingPathComponent("VibePetHooks")
        guard FileManager.default.isExecutableFile(atPath: candidate.path) else {
            throw XCTSkip("VibePetHooks binary not found at \(candidate.path)")
        }
        return candidate
    }

    private func waitForFirst(
        _ recorder: EnvelopeRecorder,
        timeout: TimeInterval = 2
    ) async throws -> BridgeEnvelope {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let envelope = await recorder.firstEnvelope() {
                return envelope
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw WaitTimeout()
    }

    private func fixture(_ name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/claude/\(name)")
        return (try? Data(contentsOf: url)) ?? Data()
    }
}

private actor EnvelopeRecorder {
    private var envelopes: [BridgeEnvelope] = []

    func record(_ envelope: BridgeEnvelope) {
        envelopes.append(envelope)
    }

    func firstEnvelope() -> BridgeEnvelope? {
        envelopes.first
    }
}

private struct WaitTimeout: Error {}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vp-e2e-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

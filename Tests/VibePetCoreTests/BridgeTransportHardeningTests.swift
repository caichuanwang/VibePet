import XCTest
@testable import VibePetCore

final class BridgeTransportHardeningTests: XCTestCase {
    // TD-3: the support directory must be user-private 0700 regardless of which
    // writer creates it first — here ConfigStore creates it before any server.
    func testSupportDirectoryIs0700WhenConfigStoreWritesFirst() throws {
        let root = try TemporaryDirectory()
        let configStore = ConfigStore(applicationSupportRoot: root.url)

        try configStore.write(.default)

        let directory = SupportDirectory.url(applicationSupportRoot: root.url)
        XCTAssertEqual(try permissions(at: directory), 0o700)
    }

    // TD-2: stop() must interrupt a thread blocked in accept() promptly (via the
    // self-pipe, not undefined close-wakeup) and free the path for a replacement.
    func testStopInterruptsBlockedAcceptPromptly() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let server = BridgeServer(socketPath: socketPath) { envelope in
            BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }
        try await server.start()

        let started = Date()
        server.stop()
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)

        let replacement = BridgeServer(socketPath: socketPath) { envelope in
            BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }
        try await replacement.start()
        replacement.stop()
    }

    // TD-2: stop() right after start() must not leak the listen fd; a replacement
    // server must be able to bind the same path afterward.
    func testStopImmediatelyAfterStartDoesNotLeak() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let server = BridgeServer(socketPath: socketPath) { envelope in
            BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }
        try await server.start()
        server.stop()

        let replacement = BridgeServer(socketPath: socketPath) { envelope in
            BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }
        try await replacement.start()
        replacement.stop()
    }

    // TD-4: a server that accepts but never replies must not block the client
    // forever — the read deadline surfaces a typed timeout error.
    func testClientReadTimesOutWhenServerNeverReplies() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let server = BridgeServer(socketPath: socketPath) { envelope in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            return BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }
        try await server.start()
        defer {
            server.stop()
        }

        let client = BridgeClient(socketPath: socketPath, connectTimeout: 2, readTimeout: 0.3)
        let envelope = BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .claudeCode, projectName: nil, sessionShortId: nil, cwd: nil),
            content: .status(StatusContent(text: "ping"))
        )

        do {
            _ = try await client.send(envelope)
            XCTFail("Expected a read timeout")
        } catch let error as BridgeClientError {
            XCTAssertEqual(error, .readTimedOut(path: socketPath.socketURL.path))
        }
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let permissions = attributes[.posixPermissions] as? NSNumber else {
            XCTFail("Missing permissions for \(url.path)")
            return -1
        }
        return permissions.intValue & 0o777
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vp-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

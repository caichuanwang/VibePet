import XCTest
@testable import VibePetCore

final class BridgeRoundTripTests: XCTestCase {
    func testSocketPathCreatesSupportDirectoryWithRestrictivePermissions() throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)

        _ = try socketPath.prepareDirectory()

        XCTAssertEqual(try permissions(at: socketPath.supportDirectoryURL), 0o700)
        XCTAssertEqual(socketPath.socketURL.path, root.url.appendingPathComponent("VibePet/bridge.sock").path)
    }

    func testClientAndServerExchangeOneNewlineDelimitedMessage() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let expectedRequestId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let server = BridgeServer(socketPath: socketPath) { envelope in
            XCTAssertEqual(envelope.requestId, expectedRequestId)
            XCTAssertEqual(envelope.content, .status(StatusContent(text: "ping")))
            return BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }

        try await server.start()
        defer {
            server.stop()
        }

        XCTAssertEqual(try permissions(at: socketPath.supportDirectoryURL), 0o700)
        XCTAssertEqual(try permissions(at: socketPath.socketURL), 0o600)

        let client = BridgeClient(socketPath: socketPath)
        let envelope = BridgeEnvelope(
            requestId: expectedRequestId,
            source: SourceInfo(tool: .codex, projectName: "VibePet", sessionShortId: "def456", cwd: "/tmp/VibePet"),
            content: .status(StatusContent(text: "ping"))
        )

        let response = try await client.send(envelope)

        XCTAssertEqual(response, BridgeResponseEnvelope(requestId: expectedRequestId, response: .defer))
    }

    func testServerRefusesToReplaceOrdinaryFileAtSocketPath() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        _ = try socketPath.prepareDirectory()
        let contents = Data("do-not-delete".utf8)
        FileManager.default.createFile(atPath: socketPath.socketURL.path, contents: contents)

        let server = BridgeServer(socketPath: socketPath) { envelope in
            BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }

        do {
            try await server.start()
            XCTFail("Expected ordinary socket-path file protection")
        } catch let error as BridgeServerError {
            XCTAssertEqual(error, .unsafeSocketPath(path: socketPath.socketURL.path))
        }
        XCTAssertEqual(try Data(contentsOf: socketPath.socketURL), contents)
    }

    func testSecondServerDoesNotReplaceLiveSocket() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let firstServer = BridgeServer(socketPath: socketPath) { envelope in
            BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }
        try await firstServer.start()
        defer {
            firstServer.stop()
        }

        let secondServer = BridgeServer(socketPath: socketPath) { envelope in
            BridgeResponseEnvelope(requestId: envelope.requestId, response: .approval(.allowOnce))
        }

        do {
            try await secondServer.start()
            XCTFail("Expected live socket protection")
        } catch let error as BridgeServerError {
            XCTAssertEqual(error, .socketInUse(path: socketPath.socketURL.path))
        }

        let client = BridgeClient(socketPath: socketPath)
        let response = try await client.send(
            BridgeEnvelope(
                requestId: UUID(uuidString: "22222222-3333-4444-5555-666666666666")!,
                source: SourceInfo(tool: .codex, projectName: nil, sessionShortId: nil, cwd: nil),
                content: .status(StatusContent(text: "still first"))
            )
        )

        XCTAssertEqual(response.response, .defer)
    }

    func testStoppingServerConcurrentlyIsIdempotent() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let server = BridgeServer(socketPath: socketPath) { envelope in
            BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }
        try await server.start()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    server.stop()
                }
            }
        }

        let replacement = BridgeServer(socketPath: socketPath) { envelope in
            BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }
        try await replacement.start()
        replacement.stop()
    }

    func testClientReturnsConnectionErrorWhenServerIsMissing() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let client = BridgeClient(socketPath: socketPath)
        let envelope = BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .codex, projectName: nil, sessionShortId: nil, cwd: nil),
            content: .status(StatusContent(text: "ping"))
        )

        do {
            _ = try await client.send(envelope)
            XCTFail("Expected connection failure")
        } catch let error as BridgeClientError {
            XCTAssertEqual(error, .connectionFailed(path: socketPath.socketURL.path))
        }
    }

    func testClientReturnsInvalidResponseWhenServerHandlerThrows() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let server = BridgeServer(socketPath: socketPath) { _ in
            throw HandlerFailure()
        }
        try await server.start()
        defer {
            server.stop()
        }

        let client = BridgeClient(socketPath: socketPath)
        let envelope = BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .codex, projectName: nil, sessionShortId: nil, cwd: nil),
            content: .status(StatusContent(text: "ping"))
        )

        do {
            _ = try await client.send(envelope)
            XCTFail("Expected invalid response")
        } catch let error as BridgeClientError {
            XCTAssertEqual(error, .invalidResponse(path: socketPath.socketURL.path))
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

private struct HandlerFailure: Error {}

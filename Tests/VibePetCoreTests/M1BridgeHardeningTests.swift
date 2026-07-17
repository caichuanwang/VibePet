import XCTest
@testable import VibePetCore

final class M1BridgeHardeningTests: XCTestCase {
    func testWriteLineRejectsPayloadOverMaximumBeforeWriting() throws {
        let sink = Darwin.open("/dev/null", O_WRONLY)
        XCTAssertGreaterThanOrEqual(sink, 0)
        defer { BridgeSocketIO.close(sink) }
        let oversized = Data(repeating: 0x61, count: BridgeSocketIO.maximumFrameBytes + 1)

        XCTAssertThrowsError(try BridgeSocketIO.writeLine(oversized, to: sink)) { error in
            XCTAssertEqual(error as? BridgeSocketError, .frameTooLarge(BridgeSocketIO.maximumFrameBytes))
        }
    }

    func testWriteLineAbsoluteDeadlineBoundsPeerThatDoesNotRead() throws {
        let pair = try SocketPair()
        var sendBufferBytes: Int32 = 1_024
        XCTAssertEqual(
            Darwin.setsockopt(
                pair.writer,
                SOL_SOCKET,
                SO_SNDBUF,
                &sendBufferBytes,
                socklen_t(MemoryLayout<Int32>.size)
            ),
            0
        )
        let payload = Data(repeating: 0x61, count: BridgeSocketIO.maximumFrameBytes)
        let started = Date()

        XCTAssertThrowsError(
            try BridgeSocketIO.writeLine(payload, to: pair.writer, absoluteTimeout: 0.08)
        ) { error in
            XCTAssertEqual(error as? BridgeSocketError, .writeTimedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
    }

    func testConnectFailsOpenWhenReadingFileStatusFlagsFails() throws {
        let root = try M1TemporaryDirectory()
        let path = SocketPath(applicationSupportRoot: root.url).socketURL.path

        XCTAssertThrowsError(try BridgeSocketIO.connect(
            to: path,
            timeout: 0.1,
            fileControl: { fileDescriptor, command, value in
                if command == F_GETFL {
                    errno = EIO
                    return -1
                }
                return Darwin.fcntl(fileDescriptor, command, value)
            }
        )) { error in
            XCTAssertEqual(error as? BridgeSocketError, .connectFailed(EIO))
        }
    }

    func testConnectFailsOpenWhenEnablingNonBlockingModeFails() throws {
        let root = try M1TemporaryDirectory()
        let path = SocketPath(applicationSupportRoot: root.url).socketURL.path
        var setCalls = 0

        XCTAssertThrowsError(try BridgeSocketIO.connect(
            to: path,
            timeout: 0.1,
            fileControl: { fileDescriptor, command, value in
                if command == F_SETFL {
                    setCalls += 1
                    if setCalls == 1 {
                        errno = EPERM
                        return -1
                    }
                }
                return Darwin.fcntl(fileDescriptor, command, value)
            }
        )) { error in
            XCTAssertEqual(error as? BridgeSocketError, .connectFailed(EPERM))
        }
    }

    func testConnectFailsOpenWhenRestoringFileStatusFlagsFails() throws {
        let root = try M1TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        try socketPath.prepareDirectory()
        let listener = try listenRaw(at: socketPath.socketURL.path)
        defer { BridgeSocketIO.close(listener) }
        var setCalls = 0

        do {
            let connected = try BridgeSocketIO.connect(
                to: socketPath.socketURL.path,
                timeout: 1,
                fileControl: { fileDescriptor, command, value in
                    if command == F_SETFL {
                        setCalls += 1
                        if setCalls == 2 {
                            errno = EIO
                            return -1
                        }
                    }
                    return Darwin.fcntl(fileDescriptor, command, value)
                }
            )
            BridgeSocketIO.close(connected)
            XCTFail("Expected restoring file status flags to fail")
        } catch {
            XCTAssertEqual(error as? BridgeSocketError, .connectFailed(EIO))
        }
    }

    func testReadLineAcceptsExactlyMaximumFrameBytes() throws {
        let file = try FrameFile(contents: Data(repeating: 0x61, count: BridgeSocketIO.maximumFrameBytes) + Data([0x0A]))

        let data = try BridgeSocketIO.readLine(from: file.fileDescriptor)

        XCTAssertEqual(data.count, BridgeSocketIO.maximumFrameBytes)
        XCTAssertEqual(data.first, 0x61)
        XCTAssertEqual(data.last, 0x61)
    }

    func testReadLineAcceptsMaximumFrameFromSocketBeforeServerDeadline() throws {
        let pair = try SocketPair()
        let payload = Data(repeating: 0x61, count: BridgeSocketIO.maximumFrameBytes)
        let writeFinished = expectation(description: "maximum frame write finished")
        DispatchQueue.global().async {
            defer { writeFinished.fulfill() }
            try? BridgeSocketIO.writeLine(payload, to: pair.writer, absoluteTimeout: 3)
        }

        let received: Data
        do {
            received = try BridgeSocketIO.readLine(from: pair.reader, absoluteTimeout: 2)
        } catch {
            BridgeSocketIO.shutdown(pair.reader)
            BridgeSocketIO.shutdown(pair.writer)
            wait(for: [writeFinished], timeout: 1)
            throw error
        }

        XCTAssertEqual(received.count, BridgeSocketIO.maximumFrameBytes)
        XCTAssertEqual(received.first, 0x61)
        XCTAssertEqual(received.last, 0x61)
        wait(for: [writeFinished], timeout: 1)
    }

    func testReadLineRejectsFrameOneByteOverMaximum() throws {
        let file = try FrameFile(
            contents: Data(repeating: 0x61, count: BridgeSocketIO.maximumFrameBytes + 1) + Data([0x0A])
        )

        XCTAssertThrowsError(try BridgeSocketIO.readLine(from: file.fileDescriptor)) { error in
            XCTAssertEqual(error as? BridgeSocketError, .frameTooLarge(BridgeSocketIO.maximumFrameBytes))
        }
    }

    func testReadLineAbsoluteDeadlineBoundsPartialFrame() throws {
        let pair = try SocketPair()
        try write(Data("{".utf8), to: pair.writer)
        let started = Date()

        XCTAssertThrowsError(
            try BridgeSocketIO.readLine(from: pair.reader, absoluteTimeout: 0.08)
        ) { error in
            XCTAssertEqual(error as? BridgeSocketError, .readTimedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
    }

    func testReadLineAbsoluteDeadlineDoesNotResetForDripFeed() throws {
        let pair = try SocketPair()
        let writesFinished = expectation(description: "drip writes finished")
        DispatchQueue.global().async {
            defer { writesFinished.fulfill() }
            for byte in [UInt8(ascii: "{"), UInt8(ascii: "a"), UInt8(ascii: "b")] {
                _ = Darwin.write(pair.writer, [byte], 1)
                usleep(30_000)
            }
        }
        let started = Date()

        XCTAssertThrowsError(
            try BridgeSocketIO.readLine(from: pair.reader, absoluteTimeout: 0.08)
        ) { error in
            XCTAssertEqual(error as? BridgeSocketError, .readTimedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
        wait(for: [writesFinished], timeout: 1)
    }

    func testReadLineAssemblesManySmallChunksBeforeDeadline() throws {
        let pair = try SocketPair()
        let payload = Data(#"{"message":"split across many writes","value":42}"#.utf8)
        let writesFinished = expectation(description: "chunked writes finished")
        DispatchQueue.global().async {
            defer { writesFinished.fulfill() }
            for chunkStart in stride(from: 0, to: payload.count, by: 3) {
                let chunkEnd = min(chunkStart + 3, payload.count)
                let chunk = payload.subdata(in: chunkStart..<chunkEnd)
                _ = chunk.withUnsafeBytes { bytes in
                    Darwin.write(pair.writer, bytes.baseAddress, bytes.count)
                }
            }
            var newline: UInt8 = 0x0A
            _ = Darwin.write(pair.writer, &newline, 1)
        }

        let data = try BridgeSocketIO.readLine(from: pair.reader, absoluteTimeout: 1)

        XCTAssertEqual(data, payload)
        wait(for: [writesFinished], timeout: 1)
    }

    func testReadLineReturnsCompleteFrameAtEOFWithoutNewline() throws {
        let payload = Data(#"{"complete":true}"#.utf8)
        let file = try FrameFile(contents: payload)

        XCTAssertEqual(try BridgeSocketIO.readLine(from: file.fileDescriptor), payload)
    }

    func testServerAcceptsCompleteEnvelopeAtEOFWithoutNewline() async throws {
        let root = try M1TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let envelope = BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .claudeCode, projectName: nil, sessionShortId: nil, cwd: nil),
            content: .status(StatusContent(text: "EOF"))
        )
        let server = BridgeServer(socketPath: socketPath) { received in
            BridgeResponseEnvelope(requestId: received.requestId, response: .defer)
        }
        try await server.start()
        defer { server.stop() }
        let client = try connectRaw(to: socketPath.socketURL.path)
        defer { BridgeSocketIO.close(client) }
        try write(JSONEncoder().encode(envelope), to: client)
        _ = Darwin.shutdown(client, SHUT_WR)

        let responseData = try BridgeSocketIO.readLine(from: client, absoluteTimeout: 1)
        let response = try JSONDecoder().decode(BridgeResponseEnvelope.self, from: responseData)

        XCTAssertEqual(response.requestId, envelope.requestId)
        XCTAssertEqual(response.response, .defer)
    }

    func testServerRejectsTruncatedEnvelopeAtEOF() async throws {
        let root = try M1TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let handlerCalled = expectation(description: "malformed EOF must not reach handler")
        handlerCalled.isInverted = true
        let server = BridgeServer(socketPath: socketPath) { envelope in
            handlerCalled.fulfill()
            return BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }
        try await server.start()
        defer { server.stop() }
        let client = try connectRaw(to: socketPath.socketURL.path)
        defer { BridgeSocketIO.close(client) }
        try write(Data(#"{"requestId":"truncated""#.utf8), to: client)
        _ = Darwin.shutdown(client, SHUT_WR)

        XCTAssertThrowsError(try BridgeSocketIO.readLine(from: client, absoluteTimeout: 1)) { error in
            XCTAssertEqual(error as? BridgeSocketError, .connectionClosed)
        }
        await fulfillment(of: [handlerCalled], timeout: 0.1)
    }

    func testServerDispatchesChunkedEnvelopeExactlyOnce() async throws {
        let root = try M1TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let recorder = M1InvocationRecorder()
        let envelope = BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .claudeCode, projectName: nil, sessionShortId: nil, cwd: nil),
            content: .status(StatusContent(text: "chunked"))
        )
        let server = BridgeServer(socketPath: socketPath) { received in
            await recorder.record(received.requestId)
            return BridgeResponseEnvelope(requestId: received.requestId, response: .defer)
        }
        try await server.start()
        defer { server.stop() }
        let client = try connectRaw(to: socketPath.socketURL.path)
        defer { BridgeSocketIO.close(client) }
        let data = try JSONEncoder().encode(envelope)
        for chunkStart in stride(from: 0, to: data.count, by: 7) {
            try write(data.subdata(in: chunkStart..<min(chunkStart + 7, data.count)), to: client)
        }
        try write(Data([0x0A]), to: client)

        _ = try BridgeSocketIO.readLine(from: client, absoluteTimeout: 1)
        let requestIDs = await recorder.requestIDs

        XCTAssertEqual(requestIDs, [envelope.requestId])
    }

    func testServerAppliesTwoSecondDeadlineToSilentClient() async throws {
        let root = try M1TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let server = BridgeServer(socketPath: socketPath) { envelope in
            BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }
        try await server.start()
        defer { server.stop() }
        let client = try connectRaw(to: socketPath.socketURL.path)
        defer { BridgeSocketIO.close(client) }
        let started = Date()

        XCTAssertThrowsError(try BridgeSocketIO.readLine(from: client, absoluteTimeout: 3)) { error in
            XCTAssertEqual(error as? BridgeSocketError, .connectionClosed)
        }
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertGreaterThanOrEqual(elapsed, 1.8)
        XCTAssertLessThan(elapsed, 2.8)
    }

    func testServerAbsoluteDeadlineDoesNotResetForDripFedClient() async throws {
        let root = try M1TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let server = BridgeServer(socketPath: socketPath) { envelope in
            BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }
        try await server.start()
        defer { server.stop() }
        let client = try connectRaw(to: socketPath.socketURL.path)
        defer { BridgeSocketIO.close(client) }
        let dripFinished = expectation(description: "drip writer finished")
        DispatchQueue.global().async {
            defer { dripFinished.fulfill() }
            for _ in 0..<15 {
                var byte = UInt8(ascii: "{")
                guard Darwin.write(client, &byte, 1) == 1 else { return }
                usleep(180_000)
            }
        }
        let started = Date()

        XCTAssertThrowsError(try BridgeSocketIO.readLine(from: client, absoluteTimeout: 3)) { error in
            XCTAssertEqual(error as? BridgeSocketError, .connectionClosed)
        }
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertGreaterThanOrEqual(elapsed, 1.8)
        XCTAssertLessThan(elapsed, 2.8)
        await fulfillment(of: [dripFinished], timeout: 1)
    }

    func testSocketPathRejectsOrdinaryFileAndPreservesIt() throws {
        let root = try M1TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        _ = try socketPath.prepareDirectory()
        let contents = Data("do-not-delete".utf8)
        XCTAssertTrue(FileManager.default.createFile(atPath: socketPath.socketURL.path, contents: contents))

        XCTAssertThrowsError(try socketPath.removeStaleSocket()) { error in
            XCTAssertEqual(error as? BridgeServerError, .unsafeSocketPath(path: socketPath.socketURL.path))
        }
        XCTAssertEqual(try Data(contentsOf: socketPath.socketURL), contents)
    }

    func testSocketPathRejectsDirectoryAndPreservesIt() throws {
        let root = try M1TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        _ = try socketPath.prepareDirectory()
        try FileManager.default.createDirectory(at: socketPath.socketURL, withIntermediateDirectories: false)

        XCTAssertThrowsError(try socketPath.removeStaleSocket()) { error in
            XCTAssertEqual(error as? BridgeServerError, .unsafeSocketPath(path: socketPath.socketURL.path))
        }
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: socketPath.socketURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testSocketPathRemovesRealStaleUnixSocket() throws {
        let root = try M1TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        _ = try socketPath.prepareDirectory()
        try bindStaleSocket(at: socketPath.socketURL.path)
        XCTAssertNotNil(try BridgeSocketIO.verifiedSocketIdentity(at: socketPath.socketURL))

        try socketPath.removeStaleSocket()

        XCTAssertFalse(FileManager.default.fileExists(atPath: socketPath.socketURL.path))
    }

    func testServerStopPreservesReplacementFileAtSocketPath() async throws {
        let root = try M1TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let server = BridgeServer(socketPath: socketPath) { envelope in
            BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }
        try await server.start()
        try FileManager.default.removeItem(at: socketPath.socketURL)
        let replacement = Data("replacement".utf8)
        XCTAssertTrue(FileManager.default.createFile(atPath: socketPath.socketURL.path, contents: replacement))

        server.stop()

        XCTAssertEqual(try Data(contentsOf: socketPath.socketURL), replacement)
    }

    func testBridgeClientRejectsMismatchedResponseRequestID() async throws {
        let root = try M1TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let requestID = UUID()
        let responseID = UUID()
        let server = BridgeServer(socketPath: socketPath) { _ in
            BridgeResponseEnvelope(requestId: responseID, response: .defer)
        }
        try await server.start()
        defer { server.stop() }
        let envelope = BridgeEnvelope(
            requestId: requestID,
            source: SourceInfo(tool: .claudeCode, projectName: nil, sessionShortId: nil, cwd: nil),
            content: .status(StatusContent(text: "ping"))
        )

        do {
            _ = try await BridgeClient(socketPath: socketPath).send(envelope)
            XCTFail("Expected mismatched request ID")
        } catch let error as BridgeClientError {
            XCTAssertEqual(error, .mismatchedResponse(expected: requestID, actual: responseID))
        }
    }

    func testBridgeClientRejectsOversizedRequestBeforeConnecting() async throws {
        let root = try M1TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let envelope = BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .claudeCode, projectName: nil, sessionShortId: nil, cwd: nil),
            content: .status(StatusContent(
                text: String(repeating: "a", count: BridgeSocketIO.maximumFrameBytes)
            ))
        )

        do {
            try await BridgeClient(socketPath: socketPath).sendOneWay(envelope)
            XCTFail("Expected an oversized request error")
        } catch let error as BridgeClientError {
            XCTAssertEqual(
                error,
                .requestFrameTooLarge(maximumBytes: BridgeSocketIO.maximumFrameBytes)
            )
        }
    }

    func testBridgeClientWriteDeadlineBoundsServerThatDoesNotRead() async throws {
        let root = try M1TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        _ = try socketPath.prepareDirectory()
        let listener = try listenRaw(at: socketPath.socketURL.path)
        let serverFinished = expectation(description: "non-reading server finished")
        DispatchQueue.global().async {
            defer { serverFinished.fulfill() }
            let client = Darwin.accept(listener, nil, nil)
            guard client >= 0 else { return }
            defer { BridgeSocketIO.close(client) }
            usleep(300_000)
        }
        defer {
            BridgeSocketIO.close(listener)
            try? socketPath.removeStaleSocket()
        }
        let envelope = BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .claudeCode, projectName: nil, sessionShortId: nil, cwd: nil),
            content: .status(StatusContent(
                text: String(repeating: "a", count: BridgeSocketIO.maximumFrameBytes - 2_048)
            ))
        )
        let started = Date()

        do {
            try await BridgeClient(
                socketPath: socketPath,
                writeTimeout: 0.08
            ).sendOneWay(envelope)
            XCTFail("Expected the write deadline to expire")
        } catch let error as BridgeClientError {
            XCTAssertEqual(error, .writeTimedOut(path: socketPath.socketURL.path))
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
        await fulfillment(of: [serverFinished], timeout: 1)
    }

    func testHookRuntimeFailsOpenOnMismatchedResponseRequestID() async throws {
        let root = try M1TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let server = BridgeServer(socketPath: socketPath) { _ in
            BridgeResponseEnvelope(requestId: UUID(), response: .approval(.allowOnce))
        }
        try await server.start()
        defer { server.stop() }
        let runtime = HookRuntime(
            adapter: ClaudeCodeAdapter(),
            client: BridgeClient(socketPath: socketPath, readTimeout: 1)
        )
        let input = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PermissionRequest",
            "session_id": "mismatch",
            "tool_name": "Bash",
            "tool_input": ["command": "echo test"],
        ])

        let outcome = await runtime.run(stdin: input, env: [:])
        XCTAssertEqual(outcome, .deferred)
    }

    func testBrokenPipeIsReportedAsWriteErrorWithoutSIGPIPE() throws {
        var descriptors: [Int32] = [-1, -1]
        XCTAssertEqual(Darwin.socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors), 0)
        BridgeSocketIO.disableSigPipe(descriptors[1])
        BridgeSocketIO.close(descriptors[0])
        defer { BridgeSocketIO.close(descriptors[1]) }

        XCTAssertThrowsError(try BridgeSocketIO.writeLine(Data("response".utf8), to: descriptors[1])) { error in
            guard case .writeFailed = error as? BridgeSocketError else {
                return XCTFail("Expected writeFailed, got \(error)")
            }
        }
    }

    func testBridgeClientAbsoluteDeadlineRejectsDripFedResponse() async throws {
        let root = try M1TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        _ = try socketPath.prepareDirectory()
        let listener = try listenRaw(at: socketPath.socketURL.path)
        let serverFinished = expectation(description: "drip server finished")
        DispatchQueue.global().async {
            defer { serverFinished.fulfill() }
            let client = Darwin.accept(listener, nil, nil)
            guard client >= 0 else { return }
            defer { BridgeSocketIO.close(client) }
            BridgeSocketIO.disableSigPipe(client)
            _ = try? BridgeSocketIO.readLine(from: client, absoluteTimeout: 1)
            for byte in Data("{\"requestId\"".utf8) {
                var byte = byte
                guard Darwin.write(client, &byte, 1) == 1 else { return }
                usleep(30_000)
            }
        }
        defer {
            BridgeSocketIO.close(listener)
            try? socketPath.removeStaleSocket()
        }
        let envelope = BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .claudeCode, projectName: nil, sessionShortId: nil, cwd: nil),
            content: .status(StatusContent(text: "ping"))
        )
        let started = Date()

        do {
            _ = try await BridgeClient(socketPath: socketPath, readTimeout: 0.08).send(envelope)
            XCTFail("Expected the absolute response deadline to expire")
        } catch let error as BridgeClientError {
            XCTAssertEqual(error, .readTimedOut(path: socketPath.socketURL.path))
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.3)
        await fulfillment(of: [serverFinished], timeout: 1)
    }

    func testServerStopInterruptsPartialFrameHandler() async throws {
        let root = try M1TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let server = BridgeServer(socketPath: socketPath) { envelope in
            BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }
        try await server.start()
        let client = try connectRaw(to: socketPath.socketURL.path)
        defer { BridgeSocketIO.close(client) }
        try write(Data("{\"requestId\":".utf8), to: client)
        let started = Date()

        server.stop()

        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        let replacement = BridgeServer(socketPath: socketPath) { envelope in
            BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }
        try await replacement.start()
        replacement.stop()
    }

    func testPeerDisconnectCancelsDecisionHandlerByRequestID() async throws {
        let root = try M1TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let requestID = UUID()
        let cancelled = expectation(description: "decision cancelled")
        let server = BridgeServer(
            socketPath: socketPath,
            cancellationHandler: { receivedID in
                XCTAssertEqual(receivedID, requestID)
                cancelled.fulfill()
            }
        ) { envelope in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }
        try await server.start()
        defer { server.stop() }
        let client = try connectRaw(to: socketPath.socketURL.path)
        let envelope = BridgeEnvelope(
            requestId: requestID,
            source: SourceInfo(tool: .claudeCode, projectName: nil, sessionShortId: nil, cwd: nil),
            content: .approval(ApprovalContent(
                title: "Approve",
                risk: .medium,
                preview: .command(text: "echo hi"),
                alwaysAllow: nil,
                requiresTerminalApproval: false
            ))
        )
        try BridgeSocketIO.writeLine(JSONEncoder().encode(envelope), to: client)
        BridgeSocketIO.close(client)

        await fulfillment(of: [cancelled], timeout: 1)
    }

    func testExtraFrameCancelsDecisionHandlerByRequestID() async throws {
        let root = try M1TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let requestID = UUID()
        let cancelled = expectation(description: "extra frame cancels decision")
        let server = BridgeServer(
            socketPath: socketPath,
            cancellationHandler: { receivedID in
                XCTAssertEqual(receivedID, requestID)
                cancelled.fulfill()
            }
        ) { envelope in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }
        try await server.start()
        defer { server.stop() }
        let client = try connectRaw(to: socketPath.socketURL.path)
        defer { BridgeSocketIO.close(client) }
        let envelope = BridgeEnvelope(
            requestId: requestID,
            source: SourceInfo(tool: .claudeCode, projectName: nil, sessionShortId: nil, cwd: nil),
            content: .approval(ApprovalContent(
                title: "Approve",
                risk: .medium,
                preview: .command(text: "echo hi"),
                alwaysAllow: nil,
                requiresTerminalApproval: false
            ))
        )
        try BridgeSocketIO.writeLine(JSONEncoder().encode(envelope), to: client)
        try BridgeSocketIO.writeLine(Data("{}".utf8), to: client)

        await fulfillment(of: [cancelled], timeout: 1)
    }

    func testHookDecisionBudgetsAreToolSpecificAndOrdered() {
        XCTAssertEqual(HookDecisionBudget.cliReadTimeout(for: .claudeCode), 86_390)
        XCTAssertEqual(HookDecisionBudget.appDecisionTimeout(for: .claudeCode), 86_385)
        XCTAssertEqual(HookDecisionBudget.cliReadTimeout(for: .codex), 3_590)
        XCTAssertEqual(HookDecisionBudget.appDecisionTimeout(for: .codex), 3_585)
        XCTAssertLessThan(
            HookDecisionBudget.appDecisionTimeout(for: .claudeCode),
            HookDecisionBudget.cliReadTimeout(for: .claudeCode)
        )
        XCTAssertLessThan(
            HookDecisionBudget.appDecisionTimeout(for: .codex),
            HookDecisionBudget.cliReadTimeout(for: .codex)
        )
    }

    func testOneHundredPartialConnectionsAndRestartsDoNotLeakFileDescriptors() async throws {
        let baseline = try openFileDescriptorCount()

        for _ in 0..<100 {
            let root = try M1TemporaryDirectory()
            let socketPath = SocketPath(applicationSupportRoot: root.url)
            let server = BridgeServer(socketPath: socketPath) { envelope in
                BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
            }
            try await server.start()
            let client = try connectRaw(to: socketPath.socketURL.path)
            try write(Data("{".utf8), to: client)
            server.stop()
            BridgeSocketIO.close(client)
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertLessThanOrEqual(try openFileDescriptorCount(), baseline + 2)
    }

    private func bindStaleSocket(at path: String) throws {
        let fileDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fileDescriptor, 0)
        defer { BridgeSocketIO.close(fileDescriptor) }
        var address = try BridgeSocketIO.socketAddress(for: path)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fileDescriptor, $0, BridgeSocketIO.addressLength(for: path))
            }
        }
        XCTAssertEqual(result, 0)
    }

    private func connectRaw(to path: String) throws -> Int32 {
        try BridgeSocketIO.connect(to: path, timeout: 1)
    }

    private func listenRaw(at path: String) throws -> Int32 {
        let fileDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else { throw BridgeSocketError.connectFailed(errno) }
        var address = try BridgeSocketIO.socketAddress(for: path)
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fileDescriptor, $0, BridgeSocketIO.addressLength(for: path))
            }
        }
        guard bindResult == 0, Darwin.listen(fileDescriptor, 1) == 0 else {
            BridgeSocketIO.close(fileDescriptor)
            throw BridgeServerError.bindFailed(path: path)
        }
        return fileDescriptor
    }

    private func write(_ data: Data, to fileDescriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let result = Darwin.write(fileDescriptor, base.advanced(by: offset), bytes.count - offset)
                guard result > 0 else { throw BridgeSocketError.writeFailed(errno) }
                offset += result
            }
        }
    }

    private func openFileDescriptorCount() throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
    }
}

private final class FrameFile {
    let fileDescriptor: Int32
    private let url: URL

    init(contents: Data) throws {
        url = URL(fileURLWithPath: "/tmp/m1-frame-\(UUID().uuidString)")
        try contents.write(to: url, options: .atomic)
        fileDescriptor = Darwin.open(url.path, O_RDONLY)
        guard fileDescriptor >= 0 else { throw BridgeSocketError.readFailed(errno) }
    }

    deinit {
        BridgeSocketIO.close(fileDescriptor)
        try? FileManager.default.removeItem(at: url)
    }
}

private final class SocketPair: @unchecked Sendable {
    let reader: Int32
    let writer: Int32

    init() throws {
        var descriptors: [Int32] = [-1, -1]
        guard Darwin.socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
            throw BridgeSocketError.connectFailed(errno)
        }
        reader = descriptors[0]
        writer = descriptors[1]
        BridgeSocketIO.disableSigPipe(reader)
        BridgeSocketIO.disableSigPipe(writer)
    }

    deinit {
        BridgeSocketIO.close(reader)
        BridgeSocketIO.close(writer)
    }
}

private actor M1InvocationRecorder {
    private(set) var requestIDs: [UUID] = []

    func record(_ requestID: UUID) {
        requestIDs.append(requestID)
    }
}

private final class M1TemporaryDirectory {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vp-m1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

import Foundation

public final class BridgeServer: Sendable {
    public typealias Handler = @Sendable (BridgeEnvelope) async throws -> BridgeResponseEnvelope
    public typealias CancellationHandler = @Sendable (UUID) -> Void

    private let socketPath: SocketPath
    private let handler: Handler
    private let cancellationHandler: CancellationHandler
    private let state = BridgeServerState()

    public init(
        socketPath: SocketPath = SocketPath(),
        cancellationHandler: @escaping CancellationHandler = { _ in },
        handler: @escaping Handler
    ) {
        self.socketPath = socketPath
        self.cancellationHandler = cancellationHandler
        self.handler = handler
    }

    public func start() async throws {
        try socketPath.prepareDirectory()
        try socketPath.removeStaleSocket()

        let fileDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw BridgeServerError.bindFailed(path: socketPath.socketURL.path)
        }

        var boundIdentity: BridgeSocketIO.SocketFileIdentity?
        do {
            var address = try BridgeSocketIO.socketAddress(for: socketPath.socketURL.path)
            let length = BridgeSocketIO.addressLength(for: socketPath.socketURL.path)
            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.bind(fileDescriptor, sockaddrPointer, length)
                }
            }

            guard bindResult == 0 else {
                throw BridgeServerError.bindFailed(path: socketPath.socketURL.path)
            }

            let identity = try BridgeSocketIO.verifiedSocketIdentity(at: socketPath.socketURL)
            guard let identity else {
                throw BridgeServerError.unsafeSocketPath(path: socketPath.socketURL.path)
            }
            boundIdentity = identity
            try socketPath.setSocketPermissions()

            guard Darwin.listen(fileDescriptor, SOMAXCONN) == 0 else {
                throw BridgeServerError.listenFailed(path: socketPath.socketURL.path)
            }

            let handler = self.handler
            let cancellationHandler = self.cancellationHandler
            try state.startAccepting(
                listenFileDescriptor: fileDescriptor,
                socketURL: socketPath.socketURL,
                socketIdentity: identity
            ) { clientFileDescriptor in
                BridgeServer.handleConnection(
                    clientFileDescriptor,
                    handler: handler,
                    cancellationHandler: cancellationHandler
                )
            }
        } catch {
            BridgeSocketIO.close(fileDescriptor)
            if let boundIdentity {
                try? BridgeSocketIO.removeSocket(at: socketPath.socketURL, matching: boundIdentity)
            }
            throw error
        }
    }

    public func stop() {
        state.stop()
    }

    deinit {
        stop()
    }

    private static func handleConnection(
        _ clientFileDescriptor: Int32,
        handler: @escaping Handler,
        cancellationHandler: @escaping CancellationHandler
    ) {
        // BridgeServerState owns the accepted fd and closes it after this handler
        // returns, so stop() can safely snapshot and shutdown live connections.
        do {
            let requestData = try BridgeSocketIO.readLine(
                from: clientFileDescriptor,
                absoluteTimeout: 2
            )
            let envelope = try JSONDecoder().decode(BridgeEnvelope.self, from: requestData)
            let response = try runHandlerSynchronously(
                requestID: envelope.requestId,
                clientFileDescriptor: clientFileDescriptor,
                cancellationHandler: envelope.content.needsResponse ? cancellationHandler : nil
            ) {
                try await handler(envelope)
            }
            let responseData = try JSONEncoder().encode(response)
            try BridgeSocketIO.writeLine(responseData, to: clientFileDescriptor)
        } catch {
            // Every transport failure is fail-open. The accepted fd is closed by defer.
        }
    }
}

private func runHandlerSynchronously(
    requestID: UUID,
    clientFileDescriptor: Int32,
    cancellationHandler: BridgeServer.CancellationHandler?,
    _ operation: @escaping @Sendable () async throws -> BridgeResponseEnvelope
) throws -> BridgeResponseEnvelope {
    let semaphore = DispatchSemaphore(value: 0)
    let box = HandlerResultBox()
    let task = Task {
        do {
            box.store(.success(try await operation()))
        } catch {
            box.store(.failure(error))
        }
        semaphore.signal()
    }

    while semaphore.wait(timeout: .now() + 0.05) == .timedOut {
        guard let cancellationHandler else {
            continue
        }
        switch BridgeSocketIO.pendingPeerEvent(clientFileDescriptor) {
        case .none:
            continue
        case .disconnected, .unexpectedInput:
            cancellationHandler(requestID)
            task.cancel()
            throw BridgeSocketError.connectionClosed
        }
    }
    return try box.take()
}

private final class HandlerResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<BridgeResponseEnvelope, Error>?

    func store(_ value: Result<BridgeResponseEnvelope, Error>) {
        lock.lock()
        result = value
        lock.unlock()
    }

    func take() throws -> BridgeResponseEnvelope {
        lock.lock()
        defer { lock.unlock() }
        guard let result else {
            throw BridgeSocketError.connectionClosed
        }
        return try result.get()
    }
}

public enum BridgeServerError: Error, Equatable {
    case socketInUse(path: String)
    case unsafeSocketPath(path: String)
    case bindFailed(path: String)
    case listenFailed(path: String)
    case serverStopped
}

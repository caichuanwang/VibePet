import Foundation

public final class BridgeServer: Sendable {
    public typealias Handler = @Sendable (BridgeEnvelope) async throws -> BridgeResponseEnvelope

    private let socketPath: SocketPath
    private let handler: Handler
    private let state = BridgeServerState()

    public init(
        socketPath: SocketPath = SocketPath(),
        handler: @escaping Handler
    ) {
        self.socketPath = socketPath
        self.handler = handler
    }

    public func start() async throws {
        try socketPath.prepareDirectory()
        try socketPath.removeStaleSocket()

        let fileDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw BridgeServerError.bindFailed(path: socketPath.socketURL.path)
        }

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

            try socketPath.setSocketPermissions()

            guard Darwin.listen(fileDescriptor, SOMAXCONN) == 0 else {
                throw BridgeServerError.listenFailed(path: socketPath.socketURL.path)
            }

            // Register the listen fd and spawn the dedicated accept thread. Both
            // happen here (synchronously, before start() returns) so there is no
            // window where the fd is live but unregistered (TD-2).
            let handler = self.handler
            try state.startAccepting(listenFileDescriptor: fileDescriptor) { clientFileDescriptor in
                BridgeServer.handleConnection(clientFileDescriptor, handler: handler)
            }
        } catch {
            BridgeSocketIO.close(fileDescriptor)
            throw error
        }
    }

    public func stop() {
        state.stop(socketURL: socketPath.socketURL)
    }

    deinit {
        stop()
    }

    /// Runs on a dedicated handling queue (off the cooperative pool). Blocking
    /// reads/writes happen here; the async handler is bridged synchronously so it
    /// can hop to its own actor without occupying a cooperative thread for I/O.
    private static func handleConnection(_ clientFileDescriptor: Int32, handler: @escaping Handler) {
        // `defer` is the single owner of the client fd close on every path.
        defer {
            BridgeSocketIO.close(clientFileDescriptor)
        }

        do {
            let requestData = try BridgeSocketIO.readLine(from: clientFileDescriptor)
            let envelope = try JSONDecoder().decode(BridgeEnvelope.self, from: requestData)
            let response = try runHandlerSynchronously { try await handler(envelope) }
            let responseData = try JSONEncoder().encode(response)
            try BridgeSocketIO.writeLine(responseData, to: clientFileDescriptor)
        } catch {
            // Connection failed mid-exchange (including a notification client that
            // closed without reading the reply); the client treats a dropped
            // connection as fail-open. The fd is released by `defer`.
        }
    }
}

/// Bridges the async handler to the synchronous handling thread. The semaphore
/// establishes a happens-before edge, so the result box needs no extra locking.
private func runHandlerSynchronously(
    _ operation: @escaping @Sendable () async throws -> BridgeResponseEnvelope
) throws -> BridgeResponseEnvelope {
    let semaphore = DispatchSemaphore(value: 0)
    let box = HandlerResultBox()
    Task {
        do {
            box.store(.success(try await operation()))
        } catch {
            box.store(.failure(error))
        }
        semaphore.signal()
    }
    semaphore.wait()
    return try box.take()
}

private final class HandlerResultBox: @unchecked Sendable {
    private var result: Result<BridgeResponseEnvelope, Error>?

    func store(_ value: Result<BridgeResponseEnvelope, Error>) {
        result = value
    }

    func take() throws -> BridgeResponseEnvelope {
        guard let result else {
            throw BridgeSocketError.connectionClosed
        }
        return try result.get()
    }
}

public enum BridgeServerError: Error, Equatable {
    case socketInUse(path: String)
    case bindFailed(path: String)
    case listenFailed(path: String)
}

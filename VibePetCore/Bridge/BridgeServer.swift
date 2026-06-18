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

            let acceptTask = Task { [weak self] in
                await self?.acceptConnections(fileDescriptor: fileDescriptor)
                return
            }
            state.install(fileDescriptor: fileDescriptor, acceptTask: acceptTask)
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

    private func acceptConnections(fileDescriptor: Int32) async {
        while !Task.isCancelled {
            let clientFileDescriptor = Darwin.accept(fileDescriptor, nil, nil)
            if clientFileDescriptor < 0 {
                // EINTR is transient (interrupted syscall); keep listening. Any other
                // error (e.g. EBADF after stop() closes the listen fd) ends the loop.
                if errno == EINTR {
                    continue
                }
                break
            }

            Task { [handler] in
                // `defer` is the single owner of the client fd close on every path.
                defer {
                    BridgeSocketIO.close(clientFileDescriptor)
                }

                do {
                    let requestData = try BridgeSocketIO.readLine(from: clientFileDescriptor)
                    let envelope = try JSONDecoder().decode(BridgeEnvelope.self, from: requestData)
                    let response = try await handler(envelope)
                    let responseData = try JSONEncoder().encode(response)
                    try BridgeSocketIO.writeLine(responseData, to: clientFileDescriptor)
                } catch {
                    // Connection failed mid-exchange; the client treats a dropped
                    // connection as fail-open. The fd is released by `defer`.
                }
            }
        }
    }
}

public enum BridgeServerError: Error, Equatable {
    case socketInUse(path: String)
    case bindFailed(path: String)
    case listenFailed(path: String)
}

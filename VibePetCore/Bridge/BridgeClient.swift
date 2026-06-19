import Foundation

public struct BridgeClient: Sendable {
    private let socketPath: SocketPath
    private let connectTimeout: TimeInterval
    private let readTimeout: TimeInterval

    public init(
        socketPath: SocketPath = SocketPath(),
        connectTimeout: TimeInterval = 2,
        readTimeout: TimeInterval = 20
    ) {
        self.socketPath = socketPath
        self.connectTimeout = connectTimeout
        self.readTimeout = readTimeout
    }

    /// Sends an envelope and blocks for the response. Used by approval / question
    /// paths that must wait for a user decision. Both the connect and the read are
    /// bounded so a missing or stalled App surfaces a typed timeout the CLI can map
    /// to a `defer` fail-open outcome.
    @discardableResult
    public func send(_ envelope: BridgeEnvelope) async throws -> BridgeResponseEnvelope {
        let fileDescriptor = try connect()
        defer {
            BridgeSocketIO.close(fileDescriptor)
        }

        BridgeSocketIO.setReadTimeout(fileDescriptor, seconds: readTimeout)

        do {
            let requestData = try JSONEncoder().encode(envelope)
            try BridgeSocketIO.writeLine(requestData, to: fileDescriptor)
            let responseData = try BridgeSocketIO.readLine(from: fileDescriptor)
            return try JSONDecoder().decode(BridgeResponseEnvelope.self, from: responseData)
        } catch BridgeSocketError.readTimedOut {
            throw BridgeClientError.readTimedOut(path: socketPath.socketURL.path)
        } catch {
            throw BridgeClientError.invalidResponse(path: socketPath.socketURL.path)
        }
    }

    /// Sends a notification envelope without waiting for a response. Used by the
    /// hook CLI for `completion` / `status` (non-blocking) traffic: write one line
    /// and return immediately. The server still writes a reply; closing before
    /// reading it is harmless.
    public func sendOneWay(_ envelope: BridgeEnvelope) async throws {
        let fileDescriptor = try connect()
        defer {
            BridgeSocketIO.close(fileDescriptor)
        }

        do {
            let requestData = try JSONEncoder().encode(envelope)
            try BridgeSocketIO.writeLine(requestData, to: fileDescriptor)
        } catch {
            throw BridgeClientError.invalidResponse(path: socketPath.socketURL.path)
        }
    }

    private func connect() throws -> Int32 {
        do {
            return try BridgeSocketIO.connect(to: socketPath.socketURL.path, timeout: connectTimeout)
        } catch BridgeSocketError.connectTimedOut {
            throw BridgeClientError.connectionTimedOut(path: socketPath.socketURL.path)
        } catch {
            throw BridgeClientError.connectionFailed(path: socketPath.socketURL.path)
        }
    }
}

public enum BridgeClientError: Error, Equatable {
    case connectionFailed(path: String)
    case connectionTimedOut(path: String)
    case invalidResponse(path: String)
    case readTimedOut(path: String)
}

import Foundation

public struct BridgeClient: Sendable {
    private let socketPath: SocketPath
    private let connectTimeout: TimeInterval
    private let writeTimeout: TimeInterval
    private let readTimeout: TimeInterval

    public init(
        socketPath: SocketPath = SocketPath(),
        connectTimeout: TimeInterval = 2,
        writeTimeout: TimeInterval = 2,
        readTimeout: TimeInterval = 20
    ) {
        self.socketPath = socketPath
        self.connectTimeout = connectTimeout
        self.writeTimeout = writeTimeout
        self.readTimeout = readTimeout
    }

    /// Sends an envelope and blocks for the response. Used by approval / question
    /// paths that must wait for a user decision. Both the connect and the read are
    /// bounded so a missing or stalled App surfaces a typed timeout the CLI can map
    /// to a `defer` fail-open outcome.
    @discardableResult
    public func send(_ envelope: BridgeEnvelope) async throws -> BridgeResponseEnvelope {
        let requestData = try encodeRequest(envelope)
        let fileDescriptor = try connect()
        defer {
            BridgeSocketIO.close(fileDescriptor)
        }

        BridgeSocketIO.setReadTimeout(fileDescriptor, seconds: readTimeout)

        do {
            try BridgeSocketIO.writeLine(
                requestData,
                to: fileDescriptor,
                absoluteTimeout: writeTimeout
            )
            let responseData = try BridgeSocketIO.readLine(
                from: fileDescriptor,
                absoluteTimeout: readTimeout
            )
            let response = try JSONDecoder().decode(BridgeResponseEnvelope.self, from: responseData)
            guard response.requestId == envelope.requestId else {
                throw BridgeClientError.mismatchedResponse(
                    expected: envelope.requestId,
                    actual: response.requestId
                )
            }
            return response
        } catch BridgeSocketError.readTimedOut {
            throw BridgeClientError.readTimedOut(path: socketPath.socketURL.path)
        } catch BridgeSocketError.writeTimedOut {
            throw BridgeClientError.writeTimedOut(path: socketPath.socketURL.path)
        } catch let error as BridgeClientError {
            throw error
        } catch {
            throw BridgeClientError.invalidResponse(path: socketPath.socketURL.path)
        }
    }

    /// Sends a notification envelope without waiting for a response. Used by the
    /// hook CLI for `completion` / `status` (non-blocking) traffic: write one line
    /// and return immediately. The server still writes a reply; closing before
    /// reading it is harmless.
    public func sendOneWay(_ envelope: BridgeEnvelope) async throws {
        let requestData = try encodeRequest(envelope)
        let fileDescriptor = try connect()
        defer {
            BridgeSocketIO.close(fileDescriptor)
        }

        do {
            try BridgeSocketIO.writeLine(
                requestData,
                to: fileDescriptor,
                absoluteTimeout: writeTimeout
            )
        } catch BridgeSocketError.writeTimedOut {
            throw BridgeClientError.writeTimedOut(path: socketPath.socketURL.path)
        } catch {
            throw BridgeClientError.invalidResponse(path: socketPath.socketURL.path)
        }
    }

    private func encodeRequest(_ envelope: BridgeEnvelope) throws -> Data {
        do {
            let data = try JSONEncoder().encode(envelope)
            guard data.count <= BridgeSocketIO.maximumFrameBytes else {
                throw BridgeClientError.requestFrameTooLarge(
                    maximumBytes: BridgeSocketIO.maximumFrameBytes
                )
            }
            return data
        } catch let error as BridgeClientError {
            throw error
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
    case mismatchedResponse(expected: UUID, actual: UUID)
    case requestFrameTooLarge(maximumBytes: Int)
    case readTimedOut(path: String)
    case writeTimedOut(path: String)
}

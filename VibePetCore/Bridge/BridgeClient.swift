import Foundation

public struct BridgeClient: Sendable {
    private let socketPath: SocketPath

    public init(socketPath: SocketPath = SocketPath()) {
        self.socketPath = socketPath
    }

    public func send(_ envelope: BridgeEnvelope) async throws -> BridgeResponseEnvelope {
        let fileDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw BridgeClientError.connectionFailed(path: socketPath.socketURL.path)
        }

        defer {
            BridgeSocketIO.close(fileDescriptor)
        }

        var address: sockaddr_un
        do {
            address = try BridgeSocketIO.socketAddress(for: socketPath.socketURL.path)
        } catch {
            throw BridgeClientError.connectionFailed(path: socketPath.socketURL.path)
        }

        let length = BridgeSocketIO.addressLength(for: socketPath.socketURL.path)
        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fileDescriptor, sockaddrPointer, length)
            }
        }

        guard connectResult == 0 else {
            throw BridgeClientError.connectionFailed(path: socketPath.socketURL.path)
        }

        do {
            let requestData = try JSONEncoder().encode(envelope)
            try BridgeSocketIO.writeLine(requestData, to: fileDescriptor)
            let responseData = try BridgeSocketIO.readLine(from: fileDescriptor)
            return try JSONDecoder().decode(BridgeResponseEnvelope.self, from: responseData)
        } catch {
            throw BridgeClientError.invalidResponse(path: socketPath.socketURL.path)
        }
    }
}

public enum BridgeClientError: Error, Equatable {
    case connectionFailed(path: String)
    case invalidResponse(path: String)
}

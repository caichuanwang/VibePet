import Foundation

enum BridgeSocketIO {
    static func socketAddress(for path: String) throws -> sockaddr_un {
        let encodedPath = Array(path.utf8)
        let maxPathLength = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        guard encodedPath.count < maxPathLength else {
            throw BridgeSocketError.pathTooLong(path)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            for index in encodedPath.indices {
                bytes[index] = encodedPath[index]
            }
            bytes[encodedPath.count] = 0
        }

        return address
    }

    static func addressLength(for path: String) -> socklen_t {
        socklen_t(MemoryLayout.offset(of: \sockaddr_un.sun_path)! + path.utf8.count + 1)
    }

    static func canConnect(to path: String) -> Bool {
        let fileDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            return false
        }

        defer {
            close(fileDescriptor)
        }

        guard var address = try? socketAddress(for: path) else {
            return false
        }

        let length = addressLength(for: path)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fileDescriptor, sockaddrPointer, length)
            }
        }

        return result == 0
    }

    static func writeLine(_ data: Data, to fileDescriptor: Int32) throws {
        var payload = data
        payload.append(0x0A)
        try payload.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }

            var bytesWritten = 0
            while bytesWritten < rawBuffer.count {
                let result = Darwin.write(
                    fileDescriptor,
                    baseAddress.advanced(by: bytesWritten),
                    rawBuffer.count - bytesWritten
                )

                if result < 0 {
                    throw BridgeSocketError.writeFailed(errno)
                }

                bytesWritten += result
            }
        }
    }

    static func readLine(from fileDescriptor: Int32) throws -> Data {
        var data = Data()
        var byte: UInt8 = 0

        while true {
            let result = Darwin.read(fileDescriptor, &byte, 1)

            if result == 0 {
                if data.isEmpty {
                    throw BridgeSocketError.connectionClosed
                }
                return data
            }

            if result < 0 {
                throw BridgeSocketError.readFailed(errno)
            }

            if byte == 0x0A {
                return data
            }

            data.append(byte)
        }
    }

    static func close(_ fileDescriptor: Int32) {
        guard fileDescriptor >= 0 else {
            return
        }
        _ = Darwin.close(fileDescriptor)
    }
}

final class BridgeServerState: @unchecked Sendable {
    private let queue = DispatchQueue(label: "VibePet.BridgeServerState")
    private var listenFileDescriptor: Int32 = -1
    private var acceptTask: Task<Void, Never>?

    func install(fileDescriptor: Int32, acceptTask: Task<Void, Never>) {
        queue.sync {
            self.listenFileDescriptor = fileDescriptor
            self.acceptTask = acceptTask
        }
    }

    func stop(socketURL: URL) {
        let snapshot = queue.sync {
            let fileDescriptor = listenFileDescriptor
            listenFileDescriptor = -1
            let task = acceptTask
            acceptTask = nil
            return (fileDescriptor, task)
        }

        guard snapshot.0 >= 0 else {
            return
        }

        snapshot.1?.cancel()
        BridgeSocketIO.close(snapshot.0)
        try? FileManager.default.removeItem(at: socketURL)
    }
}

enum BridgeSocketError: Error, Equatable {
    case pathTooLong(String)
    case readFailed(Int32)
    case writeFailed(Int32)
    case connectionClosed
}

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

    /// Connects to a Unix socket with a bounded deadline. Uses a non-blocking
    /// connect + `poll` so a missing or stalled peer cannot block the caller past
    /// `timeout` (TD-4). Returns a connected, blocking fd on success.
    static func connect(to path: String, timeout: TimeInterval) throws -> Int32 {
        var address = try socketAddress(for: path)
        let length = addressLength(for: path)

        let fileDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw BridgeSocketError.connectFailed(errno)
        }

        let originalFlags = fcntl(fileDescriptor, F_GETFL, 0)
        _ = fcntl(fileDescriptor, F_SETFL, originalFlags | O_NONBLOCK)

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fileDescriptor, sockaddrPointer, length)
            }
        }

        if connectResult != 0 {
            guard errno == EINPROGRESS else {
                let failure = errno
                close(fileDescriptor)
                throw BridgeSocketError.connectFailed(failure)
            }

            var pollDescriptor = pollfd(fd: fileDescriptor, events: Int16(POLLOUT), revents: 0)
            let milliseconds = timeout > 0 ? Int32(timeout * 1000) : 0
            let pollResult = withUnsafeMutablePointer(to: &pollDescriptor) { pointer in
                Darwin.poll(pointer, 1, milliseconds)
            }

            if pollResult == 0 {
                close(fileDescriptor)
                throw BridgeSocketError.connectTimedOut
            }
            if pollResult < 0 {
                let failure = errno
                close(fileDescriptor)
                throw BridgeSocketError.connectFailed(failure)
            }

            var socketError: Int32 = 0
            var socketErrorSize = socklen_t(MemoryLayout<Int32>.size)
            _ = getsockopt(fileDescriptor, SOL_SOCKET, SO_ERROR, &socketError, &socketErrorSize)
            if socketError != 0 {
                close(fileDescriptor)
                throw BridgeSocketError.connectFailed(socketError)
            }
        }

        _ = fcntl(fileDescriptor, F_SETFL, originalFlags)
        disableSigPipe(fileDescriptor)
        return fileDescriptor
    }

    /// Suppresses SIGPIPE for this socket so writing to a peer that has already
    /// closed surfaces as an `EPIPE` error (caught locally) instead of killing the
    /// process. The notification path always closes the client before the server
    /// writes its reply, so without this the server (and App) would crash.
    static func disableSigPipe(_ fileDescriptor: Int32) {
        var on: Int32 = 1
        _ = setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &on,
            socklen_t(MemoryLayout<Int32>.size)
        )
    }

    /// Bounds blocking reads with a receive timeout so a peer that accepts but
    /// never replies cannot block the reader forever (TD-4).
    static func setReadTimeout(_ fileDescriptor: Int32, seconds: TimeInterval) {
        guard seconds > 0 else {
            return
        }
        let whole = floor(seconds)
        var timeout = timeval(
            tv_sec: Int(whole),
            tv_usec: Int32((seconds - whole) * 1_000_000)
        )
        _ = setsockopt(
            fileDescriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )
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
                // SO_RCVTIMEO expiry surfaces as EAGAIN / EWOULDBLOCK.
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    throw BridgeSocketError.readTimedOut
                }
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

/// Owns the listen descriptor, a self-pipe used to interrupt `accept`, and the
/// dedicated accept thread. Blocking socket I/O runs here — off the Swift
/// concurrency cooperative pool — so the accept loop and connection handlers
/// cannot starve the cooperative executor (TD-1). Shutdown wakes the accept
/// thread through the self-pipe rather than relying on Darwin's undefined
/// close()-wakeup behavior, and the listen fd is registered before the thread
/// starts so a stop() in the startup window cannot leak it (TD-2).
final class BridgeServerState: @unchecked Sendable {
    private let lock = NSLock()
    private var listenFileDescriptor: Int32 = -1
    private var wakeReadFileDescriptor: Int32 = -1
    private var wakeWriteFileDescriptor: Int32 = -1
    private var isStopped = false
    private var didStart = false
    private let finished = DispatchSemaphore(value: 0)
    private let handlingQueue = DispatchQueue(
        label: "VibePet.BridgeServer.handling",
        qos: .userInitiated,
        attributes: .concurrent
    )

    func startAccepting(
        listenFileDescriptor: Int32,
        handle: @escaping @Sendable (Int32) -> Void
    ) throws {
        var pipeDescriptors: [Int32] = [-1, -1]
        guard Darwin.pipe(&pipeDescriptors) == 0 else {
            BridgeSocketIO.close(listenFileDescriptor)
            throw BridgeServerError.listenFailed(path: "")
        }

        lock.lock()
        if isStopped {
            // stop() ran before the listener was registered; don't start a thread.
            lock.unlock()
            BridgeSocketIO.close(listenFileDescriptor)
            BridgeSocketIO.close(pipeDescriptors[0])
            BridgeSocketIO.close(pipeDescriptors[1])
            return
        }
        let wakeRead = pipeDescriptors[0]
        self.listenFileDescriptor = listenFileDescriptor
        self.wakeReadFileDescriptor = wakeRead
        self.wakeWriteFileDescriptor = pipeDescriptors[1]
        self.didStart = true
        lock.unlock()

        let thread = Thread { [weak self] in
            self?.acceptLoop(
                listenFileDescriptor: listenFileDescriptor,
                wakeFileDescriptor: wakeRead,
                handle: handle
            )
            self?.finished.signal()
        }
        thread.name = "VibePet.BridgeServer.accept"
        thread.start()
    }

    private func acceptLoop(
        listenFileDescriptor: Int32,
        wakeFileDescriptor: Int32,
        handle: @escaping @Sendable (Int32) -> Void
    ) {
        let originalFlags = fcntl(listenFileDescriptor, F_GETFL, 0)
        _ = fcntl(listenFileDescriptor, F_SETFL, originalFlags | O_NONBLOCK)

        var descriptors = [
            pollfd(fd: listenFileDescriptor, events: Int16(POLLIN), revents: 0),
            pollfd(fd: wakeFileDescriptor, events: Int16(POLLIN), revents: 0)
        ]

        while true {
            let pollResult = descriptors.withUnsafeMutableBufferPointer { buffer in
                Darwin.poll(buffer.baseAddress, nfds_t(buffer.count), -1)
            }

            if pollResult < 0 {
                if errno == EINTR {
                    continue
                }
                break
            }

            // Any activity on the wake pipe (data or hangup) means stop requested.
            if descriptors[1].revents != 0 {
                break
            }

            let listenEvents = descriptors[0].revents
            if listenEvents & Int16(POLLIN) != 0 {
                let clientFileDescriptor = Darwin.accept(listenFileDescriptor, nil, nil)
                if clientFileDescriptor < 0 {
                    if errno == EINTR || errno == EWOULDBLOCK || errno == EAGAIN {
                        continue
                    }
                    break
                }
                // The accepted fd inherits O_NONBLOCK from the non-blocking listen
                // fd; the handler does blocking reads, so clear it explicitly.
                let clientFlags = fcntl(clientFileDescriptor, F_GETFL, 0)
                _ = fcntl(clientFileDescriptor, F_SETFL, clientFlags & ~O_NONBLOCK)
                BridgeSocketIO.disableSigPipe(clientFileDescriptor)
                handlingQueue.async {
                    handle(clientFileDescriptor)
                }
            } else if listenEvents != 0 {
                // Listen fd error / hangup / invalid (e.g. closed) → end the loop.
                break
            }
        }
    }

    func stop(socketURL: URL) {
        lock.lock()
        if isStopped {
            lock.unlock()
            return
        }
        isStopped = true
        let listenFileDescriptor = self.listenFileDescriptor
        let wakeRead = wakeReadFileDescriptor
        let wakeWrite = wakeWriteFileDescriptor
        let didStart = self.didStart
        self.listenFileDescriptor = -1
        wakeReadFileDescriptor = -1
        wakeWriteFileDescriptor = -1
        lock.unlock()

        guard didStart else {
            // No accept thread was ever started; nothing to wake or join.
            return
        }

        // Wake the accept thread out of poll, then wait for it to leave the loop
        // before closing the descriptors it polls (avoids closing fds under poll).
        if wakeWrite >= 0 {
            var byte: UInt8 = 1
            _ = Darwin.write(wakeWrite, &byte, 1)
        }
        _ = finished.wait(timeout: .now() + 2)

        BridgeSocketIO.close(listenFileDescriptor)
        BridgeSocketIO.close(wakeRead)
        BridgeSocketIO.close(wakeWrite)
        try? FileManager.default.removeItem(at: socketURL)
    }
}

enum BridgeSocketError: Error, Equatable {
    case pathTooLong(String)
    case readFailed(Int32)
    case writeFailed(Int32)
    case connectionClosed
    case connectFailed(Int32)
    case connectTimedOut
    case readTimedOut
}

import Foundation

enum BridgeSocketIO {
    static let maximumFrameBytes = 4 * 1024 * 1024
    typealias FileControl = (_ fileDescriptor: Int32, _ command: Int32, _ value: Int32) -> Int32

    struct SocketFileIdentity: Equatable, Sendable {
        let device: UInt64
        let inode: UInt64
    }
    private static let installSignalHandling: Void = {
        _ = Darwin.signal(SIGPIPE, SIG_IGN)
    }()

    static func ignoreSigPipe() {
        _ = installSignalHandling
    }

    static func socketAddress(for path: String) throws -> sockaddr_un {
        ignoreSigPipe()
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
    static func connect(
        to path: String,
        timeout: TimeInterval,
        fileControl: FileControl = { Darwin.fcntl($0, $1, $2) }
    ) throws -> Int32 {
        var address = try socketAddress(for: path)
        let length = addressLength(for: path)

        let fileDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw BridgeSocketError.connectFailed(errno)
        }

        let originalFlags = fileControl(fileDescriptor, F_GETFL, 0)
        guard originalFlags >= 0 else {
            let failure = errno
            close(fileDescriptor)
            throw BridgeSocketError.connectFailed(failure)
        }
        guard fileControl(fileDescriptor, F_SETFL, originalFlags | O_NONBLOCK) == 0 else {
            let failure = errno
            close(fileDescriptor)
            throw BridgeSocketError.connectFailed(failure)
        }

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

        guard fileControl(fileDescriptor, F_SETFL, originalFlags) == 0 else {
            let failure = errno
            close(fileDescriptor)
            throw BridgeSocketError.connectFailed(failure)
        }
        disableSigPipe(fileDescriptor)
        return fileDescriptor
    }

    /// Suppresses SIGPIPE for this socket so writing to a peer that has already
    /// closed surfaces as an `EPIPE` error (caught locally) instead of killing the
    /// process. The notification path always closes the client before the server
    /// writes its reply, so without this the server (and App) would crash.
    static func disableSigPipe(_ fileDescriptor: Int32) {
        _ = fcntl(fileDescriptor, F_SETNOSIGPIPE, 1)

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

    static func writeLine(
        _ data: Data,
        to fileDescriptor: Int32,
        absoluteTimeout: TimeInterval? = nil
    ) throws {
        guard data.count <= maximumFrameBytes else {
            throw BridgeSocketError.frameTooLarge(maximumFrameBytes)
        }
        let deadlineNanoseconds = absoluteTimeout.map { timeout -> UInt64 in
            let duration = UInt64(max(0, timeout) * 1_000_000_000)
            return DispatchTime.now().uptimeNanoseconds &+ duration
        }
        let originalFlags: Int32?
        if deadlineNanoseconds != nil {
            let flags = fcntl(fileDescriptor, F_GETFL, 0)
            guard flags >= 0, fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
                throw BridgeSocketError.writeFailed(errno)
            }
            originalFlags = flags
        } else {
            originalFlags = nil
        }
        defer {
            if let originalFlags {
                _ = fcntl(fileDescriptor, F_SETFL, originalFlags)
            }
        }
        var payload = data
        payload.append(0x0A)
        try payload.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }

            var bytesWritten = 0
            while bytesWritten < rawBuffer.count {
                if let deadlineNanoseconds {
                    guard DispatchTime.now().uptimeNanoseconds < deadlineNanoseconds else {
                        throw BridgeSocketError.writeTimedOut
                    }
                }
                let result = Darwin.write(
                    fileDescriptor,
                    baseAddress.advanced(by: bytesWritten),
                    rawBuffer.count - bytesWritten
                )

                if result < 0 {
                    if errno == EINTR {
                        continue
                    }
                    if (errno == EAGAIN || errno == EWOULDBLOCK), let deadlineNanoseconds {
                        try waitUntilWritable(fileDescriptor, deadlineNanoseconds: deadlineNanoseconds)
                        continue
                    }
                    throw BridgeSocketError.writeFailed(errno)
                }
                guard result > 0 else {
                    throw BridgeSocketError.connectionClosed
                }

                bytesWritten += result
            }
        }
    }

    private static func waitUntilWritable(
        _ fileDescriptor: Int32,
        deadlineNanoseconds: UInt64
    ) throws {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadlineNanoseconds else {
                throw BridgeSocketError.writeTimedOut
            }
            let remainingNanoseconds = deadlineNanoseconds - now
            let milliseconds = max(
                1,
                min(Int64(Int32.max), Int64((remainingNanoseconds + 999_999) / 1_000_000))
            )
            var descriptor = pollfd(
                fd: fileDescriptor,
                events: Int16(POLLOUT | POLLHUP | POLLERR),
                revents: 0
            )
            let pollResult = Darwin.poll(&descriptor, 1, Int32(milliseconds))
            if pollResult == 0 {
                throw BridgeSocketError.writeTimedOut
            }
            if pollResult < 0 {
                if errno == EINTR { continue }
                throw BridgeSocketError.writeFailed(errno)
            }
            if descriptor.revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 {
                throw BridgeSocketError.connectionClosed
            }
            if descriptor.revents & Int16(POLLOUT) != 0 {
                return
            }
        }
    }

    static func readLine(
        from fileDescriptor: Int32,
        maximumBytes: Int = maximumFrameBytes,
        absoluteTimeout: TimeInterval? = nil
    ) throws -> Data {
        precondition(maximumBytes > 0)

        let deadlineNanoseconds = absoluteTimeout.map { timeout -> UInt64 in
            let duration = UInt64(max(0, timeout) * 1_000_000_000)
            return DispatchTime.now().uptimeNanoseconds &+ duration
        }
        var data = Data()
        var socketBuffer = [UInt8](repeating: 0, count: 64 * 1024)
        var isSocket: Bool?

        while true {
            if let deadlineNanoseconds {
                let now = DispatchTime.now().uptimeNanoseconds
                guard now < deadlineNanoseconds else {
                    throw BridgeSocketError.readTimedOut
                }
                let remainingNanoseconds = deadlineNanoseconds - now
                let milliseconds = max(1, min(Int64(Int32.max), Int64((remainingNanoseconds + 999_999) / 1_000_000)))
                var descriptor = pollfd(
                    fd: fileDescriptor,
                    events: Int16(POLLIN | POLLHUP | POLLERR),
                    revents: 0
                )
                let pollResult = Darwin.poll(&descriptor, 1, Int32(milliseconds))
                if pollResult == 0 {
                    throw BridgeSocketError.readTimedOut
                }
                if pollResult < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw BridgeSocketError.readFailed(errno)
                }
                if descriptor.revents & Int16(POLLNVAL) != 0 {
                    throw BridgeSocketError.connectionClosed
                }
            }

            if isSocket != false {
                let flags = MSG_PEEK | (deadlineNanoseconds == nil ? 0 : MSG_DONTWAIT)
                let result = Darwin.recv(fileDescriptor, &socketBuffer, socketBuffer.count, flags)
                if result > 0 {
                    isSocket = true
                    let count = Int(result)
                    let newlineIndex = socketBuffer[..<count].firstIndex(of: 0x0A)
                    let contentCount = newlineIndex ?? count
                    guard data.count + contentCount <= maximumBytes else {
                        throw BridgeSocketError.frameTooLarge(maximumBytes)
                    }
                    data.append(contentsOf: socketBuffer[..<contentCount])
                    try consumeSocketBytes(
                        newlineIndex.map { $0 + 1 } ?? count,
                        from: fileDescriptor,
                        deadlineNanoseconds: deadlineNanoseconds
                    )
                    if newlineIndex != nil {
                        return data
                    }
                    continue
                }
                if result == 0 {
                    if data.isEmpty {
                        throw BridgeSocketError.connectionClosed
                    }
                    return data
                }
                if errno == EINTR {
                    continue
                }
                if errno == ENOTSOCK {
                    isSocket = false
                } else if errno == EAGAIN || errno == EWOULDBLOCK {
                    throw BridgeSocketError.readTimedOut
                } else {
                    throw BridgeSocketError.readFailed(errno)
                }
            }

            var byte: UInt8 = 0
            let result = Darwin.read(fileDescriptor, &byte, 1)

            if result == 0 {
                if data.isEmpty {
                    throw BridgeSocketError.connectionClosed
                }
                return data
            }

            if result < 0 {
                if errno == EINTR {
                    continue
                }
                // SO_RCVTIMEO expiry surfaces as EAGAIN / EWOULDBLOCK.
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    throw BridgeSocketError.readTimedOut
                }
                throw BridgeSocketError.readFailed(errno)
            }

            if byte == 0x0A {
                return data
            }

            guard data.count < maximumBytes else {
                throw BridgeSocketError.frameTooLarge(maximumBytes)
            }
            data.append(byte)
        }
    }

    private static func consumeSocketBytes(
        _ count: Int,
        from fileDescriptor: Int32,
        deadlineNanoseconds: UInt64?
    ) throws {
        var consumed = 0
        var buffer = [UInt8](repeating: 0, count: min(count, 64 * 1024))
        while consumed < count {
            if let deadlineNanoseconds,
               DispatchTime.now().uptimeNanoseconds >= deadlineNanoseconds {
                throw BridgeSocketError.readTimedOut
            }
            let result = Darwin.read(
                fileDescriptor,
                &buffer,
                min(buffer.count, count - consumed)
            )
            if result > 0 {
                consumed += Int(result)
                continue
            }
            if result == 0 {
                throw BridgeSocketError.connectionClosed
            }
            if errno == EINTR {
                continue
            }
            if errno == EAGAIN || errno == EWOULDBLOCK {
                throw BridgeSocketError.readTimedOut
            }
            throw BridgeSocketError.readFailed(errno)
        }
    }

    enum PeerEvent: Equatable {
        case none
        case disconnected
        case unexpectedInput
    }

    static func pendingPeerEvent(_ fileDescriptor: Int32) -> PeerEvent {
        var descriptor = pollfd(
            fd: fileDescriptor,
            events: Int16(POLLIN | POLLHUP | POLLERR),
            revents: 0
        )
        let result = Darwin.poll(&descriptor, 1, 0)
        guard result > 0 else { return .none }
        if descriptor.revents & Int16(POLLERR | POLLNVAL) != 0 {
            return .disconnected
        }
        if descriptor.revents & Int16(POLLIN) != 0 {
            var byte: UInt8 = 0
            let peeked = Darwin.recv(fileDescriptor, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
            if peeked > 0 { return .unexpectedInput }
            if peeked == 0 { return .disconnected }
        }
        if descriptor.revents & Int16(POLLHUP) != 0 {
            return .disconnected
        }
        return .none
    }

    static func shutdown(_ fileDescriptor: Int32) {
        guard fileDescriptor >= 0 else { return }
        _ = Darwin.shutdown(fileDescriptor, SHUT_RDWR)
    }

    static func verifiedSocketIdentity(at url: URL) throws -> SocketFileIdentity? {
        var info = stat()
        if Darwin.lstat(url.path, &info) != 0 {
            if errno == ENOENT { return nil }
            throw BridgeServerError.unsafeSocketPath(path: url.path)
        }
        guard (info.st_mode & S_IFMT) == S_IFSOCK, info.st_uid == geteuid() else {
            throw BridgeServerError.unsafeSocketPath(path: url.path)
        }
        return SocketFileIdentity(
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino)
        )
    }

    static func removeSocket(at url: URL, matching expectedIdentity: SocketFileIdentity? = nil) throws {
        guard let currentIdentity = try verifiedSocketIdentity(at: url) else { return }
        if let expectedIdentity, currentIdentity != expectedIdentity {
            throw BridgeServerError.unsafeSocketPath(path: url.path)
        }
        try FileManager.default.removeItem(at: url)
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
    private var acceptedFileDescriptors: Set<Int32> = []
    private var socketURL: URL?
    private var socketIdentity: BridgeSocketIO.SocketFileIdentity?
    private let finished = DispatchSemaphore(value: 0)
    private let handlingQueue = DispatchQueue(
        label: "VibePet.BridgeServer.handling",
        qos: .userInitiated,
        attributes: .concurrent
    )

    func startAccepting(
        listenFileDescriptor: Int32,
        socketURL: URL,
        socketIdentity: BridgeSocketIO.SocketFileIdentity,
        handle: @escaping @Sendable (Int32) -> Void
    ) throws {
        var pipeDescriptors: [Int32] = [-1, -1]
        guard Darwin.pipe(&pipeDescriptors) == 0 else {
            throw BridgeServerError.listenFailed(path: "")
        }

        BridgeSocketIO.disableSigPipe(pipeDescriptors[1])

        lock.lock()
        if isStopped {
            // stop() ran before the listener was registered. The caller still owns
            // the listen fd and bound socket path and will clean both up on throw.
            lock.unlock()
            BridgeSocketIO.close(pipeDescriptors[0])
            BridgeSocketIO.close(pipeDescriptors[1])
            throw BridgeServerError.serverStopped
        }
        let wakeRead = pipeDescriptors[0]
        self.listenFileDescriptor = listenFileDescriptor
        self.wakeReadFileDescriptor = wakeRead
        self.wakeWriteFileDescriptor = pipeDescriptors[1]
        self.socketURL = socketURL
        self.socketIdentity = socketIdentity
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
                lock.lock()
                let shouldHandle = !isStopped
                if shouldHandle {
                    acceptedFileDescriptors.insert(clientFileDescriptor)
                }
                lock.unlock()
                guard shouldHandle else {
                    BridgeSocketIO.close(clientFileDescriptor)
                    break
                }
                handlingQueue.async { [weak self] in
                    handle(clientFileDescriptor)
                    if let self {
                        self.connectionFinished(clientFileDescriptor)
                    } else {
                        BridgeSocketIO.close(clientFileDescriptor)
                    }
                }
            } else if listenEvents != 0 {
                // Listen fd error / hangup / invalid (e.g. closed) → end the loop.
                break
            }
        }
    }

    private func connectionFinished(_ fileDescriptor: Int32) {
        lock.lock()
        acceptedFileDescriptors.remove(fileDescriptor)
        BridgeSocketIO.close(fileDescriptor)
        lock.unlock()
    }

    func stop() {
        lock.lock()
        if isStopped {
            lock.unlock()
            return
        }
        isStopped = true
        let listenFileDescriptor = self.listenFileDescriptor
        let wakeRead = wakeReadFileDescriptor
        let wakeWrite = wakeWriteFileDescriptor
        let accepted = acceptedFileDescriptors
        let didStart = self.didStart
        let socketURL = self.socketURL
        let socketIdentity = self.socketIdentity
        self.listenFileDescriptor = -1
        wakeReadFileDescriptor = -1
        wakeWriteFileDescriptor = -1
        self.socketURL = nil
        self.socketIdentity = nil
        // Interrupt under the same lock that connectionFinished uses before close,
        // preventing a completed fd from being reused between snapshot and shutdown.
        for fileDescriptor in accepted {
            BridgeSocketIO.shutdown(fileDescriptor)
        }
        lock.unlock()

        guard didStart else {
            return
        }

        // Wake accept and interrupt every accepted read/decision wait. Handler queues
        // retain ownership of close(); shutdown only makes their blocking I/O finish.
        if wakeWrite >= 0 {
            var byte: UInt8 = 1
            _ = Darwin.write(wakeWrite, &byte, 1)
        }
        _ = finished.wait(timeout: .now() + 2)

        BridgeSocketIO.close(listenFileDescriptor)
        BridgeSocketIO.close(wakeRead)
        BridgeSocketIO.close(wakeWrite)
        if let socketURL, let socketIdentity {
            try? BridgeSocketIO.removeSocket(at: socketURL, matching: socketIdentity)
        }
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
    case writeTimedOut
    case frameTooLarge(Int)
}

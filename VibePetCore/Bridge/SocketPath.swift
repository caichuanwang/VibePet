import Foundation

public struct SocketPath: Equatable, Sendable {
    public let applicationSupportRoot: URL

    public init(applicationSupportRoot: URL? = nil) {
        if let applicationSupportRoot {
            self.applicationSupportRoot = applicationSupportRoot
        } else {
            self.applicationSupportRoot = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        }
    }

    public var supportDirectoryURL: URL {
        applicationSupportRoot.appendingPathComponent("VibePet", isDirectory: true)
    }

    public var socketURL: URL {
        supportDirectoryURL.appendingPathComponent("bridge.sock", isDirectory: false)
    }

    @discardableResult
    public func prepareDirectory() throws -> URL {
        try FileManager.default.createDirectory(
            at: supportDirectoryURL,
            withIntermediateDirectories: true
        )
        try setPermissions(0o700, at: supportDirectoryURL)
        return supportDirectoryURL
    }

    public func removeStaleSocket() throws {
        guard FileManager.default.fileExists(atPath: socketURL.path) else {
            return
        }

        if BridgeSocketIO.canConnect(to: socketURL.path) {
            throw BridgeServerError.socketInUse(path: socketURL.path)
        }

        try FileManager.default.removeItem(at: socketURL)
    }

    public func setSocketPermissions() throws {
        try setPermissions(0o600, at: socketURL)
    }

    private func setPermissions(_ permissions: Int, at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: permissions)],
            ofItemAtPath: url.path
        )
    }
}

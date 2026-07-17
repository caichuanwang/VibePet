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
        SupportDirectory.url(applicationSupportRoot: applicationSupportRoot)
    }

    public var socketURL: URL {
        supportDirectoryURL.appendingPathComponent("bridge.sock", isDirectory: false)
    }

    @discardableResult
    public func prepareDirectory() throws -> URL {
        try SupportDirectory.ensure(applicationSupportRoot: applicationSupportRoot)
    }

    public func removeStaleSocket() throws {
        guard let identity = try BridgeSocketIO.verifiedSocketIdentity(at: socketURL) else {
            return
        }

        if BridgeSocketIO.canConnect(to: socketURL.path) {
            throw BridgeServerError.socketInUse(path: socketURL.path)
        }

        try BridgeSocketIO.removeSocket(at: socketURL, matching: identity)
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

import Foundation

/// Single source of truth for the VibePet Application Support directory and its
/// permissions. Both `SocketPath` (which hosts `bridge.sock`) and `ConfigStore`
/// (which writes `config.json`) create this directory; without a shared helper
/// whichever ran first set the mode, leaving the socket's parent at the default
/// umask (~0755) until the server reset it. Routing every creator through here
/// keeps the directory stably user-private `0700` regardless of write order.
public enum SupportDirectory {
    /// `~/Library/Application Support` for the current user.
    public static func defaultApplicationSupportRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    /// The `VibePet` directory under the given (or default) Application Support root.
    public static func url(applicationSupportRoot: URL? = nil) -> URL {
        (applicationSupportRoot ?? defaultApplicationSupportRoot())
            .appendingPathComponent("VibePet", isDirectory: true)
    }

    /// Ensures the VibePet support directory exists with mode `0700`, returning it.
    @discardableResult
    public static func ensure(applicationSupportRoot: URL? = nil) throws -> URL {
        let directory = url(applicationSupportRoot: applicationSupportRoot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: directory.path
        )
        return directory
    }
}

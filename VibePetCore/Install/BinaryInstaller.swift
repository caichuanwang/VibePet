import Foundation

/// Copies the `VibePetHooks` binary to its stable Application Support path
/// (`bin/VibePetHooks`), decoupled from the `.app` bundle (technical design §1.2).
/// The copy is re-done when it is missing, the installed version is behind the
/// current one, or the on-disk bytes differ from the source — so a same-version
/// reinstall of an *unchanged* binary is a no-op, while a rebuilt-but-not-version-
/// bumped binary (common during development) is still refreshed.
public struct BinaryInstaller: Sendable {
    private let applicationSupportRoot: URL?

    public init(applicationSupportRoot: URL? = nil) {
        self.applicationSupportRoot = applicationSupportRoot
    }

    /// The stable destination the tool config `command` must reference.
    public var binaryURL: URL {
        InstallPaths.hookBinaryURL(applicationSupportRoot: applicationSupportRoot)
    }

    /// Installs/updates the binary from `source`.
    ///
    /// - Parameters:
    ///   - source: the freshly built `VibePetHooks` to copy (next to the app/product).
    ///   - version: the current binary version (`VibePetCore.hookBinaryVersion`).
    ///   - installedVersion: the version recorded in the manifest, or nil if absent.
    /// - Returns: `true` if it copied, `false` if it skipped because the installed
    ///   copy is present, the version matches, and the bytes are identical.
    @discardableResult
    public func install(
        from source: URL,
        version: String = VibePetCore.hookBinaryVersion,
        installedVersion: String?
    ) throws -> Bool {
        let destination = binaryURL
        let exists = FileManager.default.fileExists(atPath: destination.path)
        if exists, installedVersion == version, sameContents(source, destination) {
            return false
        }

        try SupportDirectory.ensure(applicationSupportRoot: applicationSupportRoot)
        let binDirectory = InstallPaths.binDirectory(applicationSupportRoot: applicationSupportRoot)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)

        if exists {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: destination.path
        )
        return true
    }

    /// Whether two files hold identical bytes. A read failure is treated as "differ"
    /// so the caller errs toward re-copying rather than skipping.
    private func sameContents(_ lhs: URL, _ rhs: URL) -> Bool {
        guard
            let lhsData = try? Data(contentsOf: lhs),
            let rhsData = try? Data(contentsOf: rhs)
        else {
            return false
        }
        return lhsData == rhsData
    }
}

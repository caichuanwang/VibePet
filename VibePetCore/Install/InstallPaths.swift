import Foundation

/// Stable on-disk locations the installer writes to, all under the shared VibePet
/// Application Support directory (technical design §1.2 / §6). The hook binary lives
/// at `bin/VibePetHooks` — a copy decoupled from the `.app` bundle so tool configs
/// never reference a path inside the bundle.
public enum InstallPaths {
    /// `<support>/bin`.
    public static func binDirectory(applicationSupportRoot: URL? = nil) -> URL {
        SupportDirectory.url(applicationSupportRoot: applicationSupportRoot)
            .appendingPathComponent("bin", isDirectory: true)
    }

    /// `<support>/bin/VibePetHooks` — the stable hook binary path written into tool
    /// configuration `command` entries.
    public static func hookBinaryURL(applicationSupportRoot: URL? = nil) -> URL {
        binDirectory(applicationSupportRoot: applicationSupportRoot)
            .appendingPathComponent("VibePetHooks", isDirectory: false)
    }

    /// `<support>/install-manifest.json`.
    public static func manifestURL(applicationSupportRoot: URL? = nil) -> URL {
        SupportDirectory.url(applicationSupportRoot: applicationSupportRoot)
            .appendingPathComponent("install-manifest.json", isDirectory: false)
    }

    /// `<support>/backups` — where original tool configs are copied before writing.
    public static func backupsDirectory(applicationSupportRoot: URL? = nil) -> URL {
        SupportDirectory.url(applicationSupportRoot: applicationSupportRoot)
            .appendingPathComponent("backups", isDirectory: true)
    }
}

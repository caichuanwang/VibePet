public enum VibePetCore {
    public static let protocolVersion = 1

    /// Version stamp for the installed `bin/VibePetHooks` copy. The installer
    /// records this in the manifest and re-copies the binary when the installed
    /// copy is behind (technical design §1.2 / §4.3).
    public static let hookBinaryVersion = "0.1.0"
}

import Foundation

/// Finds a usable `VibePetHooks` binary to copy from at install time. The install
/// `command` always points at the stable managed copy (`InstallPaths.hookBinaryURL`);
/// this locator is only about discovering a *source* to copy, robustly across the
/// app bundle, a `swift run` dev build, and an explicit override.
///
/// Search order (first executable hit wins):
///   1. `VIBEPET_HOOKS_BINARY` env override (CI / packaging / tests)
///   2. next to the running executable, and a sibling `Helpers/` (app bundle layouts)
///   3. the already-installed managed copy
///   4. `.build/{arch}/{release,debug}` under the working directory (dev `swift run`)
///
/// Pure and injectable so it is unit-testable without a real bundle.
public enum HooksBinaryLocator {
    public static let binaryName = "VibePetHooks"
    public static let environmentKey = "VIBEPET_HOOKS_BINARY"

    public static func locate(
        fileManager: FileManager = .default,
        executableDirectory: URL? = nil,
        currentDirectory: URL? = nil,
        applicationSupportRoot: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let override = environment[environmentKey],
           fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override).standardizedFileURL
        }

        let workingDirectory = currentDirectory
            ?? URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)

        let candidates: [URL] = [
            executableDirectory?.appendingPathComponent(binaryName, isDirectory: false),
            executableDirectory?.appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent(binaryName, isDirectory: false),
            InstallPaths.hookBinaryURL(applicationSupportRoot: applicationSupportRoot),
        ].compactMap { $0 } + buildDirectoryCandidates(under: workingDirectory)

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate.standardizedFileURL
        }
        return nil
    }

    /// `.build/{arch}/release|debug/VibePetHooks` and the arch-agnostic
    /// `.build/release|debug/VibePetHooks`, for a local `swift run`/`swift build`.
    private static func buildDirectoryCandidates(under directory: URL) -> [URL] {
        #if arch(arm64)
        let archTriple: String? = "arm64-apple-macosx"
        #elseif arch(x86_64)
        let archTriple: String? = "x86_64-apple-macosx"
        #else
        let archTriple: String? = nil
        #endif

        let relativePaths = [
            archTriple.map { ".build/\($0)/release/\(binaryName)" },
            ".build/release/\(binaryName)",
            archTriple.map { ".build/\($0)/debug/\(binaryName)" },
            ".build/debug/\(binaryName)",
        ].compactMap { $0 }

        return relativePaths.map { directory.appendingPathComponent($0, isDirectory: false) }
    }
}

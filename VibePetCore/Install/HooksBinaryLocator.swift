import Foundation

public enum HooksBinaryLocation: Equatable, Sendable {
    case found(URL)
    case invalidExplicitOverride(URL)
    case notFound(attempted: [URL])

    public var url: URL? {
        guard case let .found(url) = self else { return nil }
        return url
    }
}

/// Finds a usable `VibePetHooks` source binary. An explicit override is authoritative:
/// when present but invalid it never falls through to a different binary.
public enum HooksBinaryLocator {
    public static let binaryName = "VibePetHooks"
    public static let environmentKey = "VIBEPET_HOOKS_BINARY"

    public static func locateResult(
        fileManager: FileManager = .default,
        executableDirectory: URL? = nil,
        currentDirectory: URL? = nil,
        applicationSupportRoot: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> HooksBinaryLocation {
        if let override = environment[environmentKey] {
            let url = URL(fileURLWithPath: override).standardizedFileURL
            return isExecutableRegularFile(url, fileManager: fileManager)
                ? .found(url)
                : .invalidExplicitOverride(url)
        }

        let workingDirectory = currentDirectory
            ?? URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let candidates: [URL] = [
            executableDirectory?.appendingPathComponent(binaryName, isDirectory: false),
            executableDirectory?.appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent(binaryName, isDirectory: false),
        ].compactMap { $0 } + buildDirectoryCandidates(under: workingDirectory)
        let standardizedCandidates = candidates.map(\.standardizedFileURL)
        if let candidate = standardizedCandidates.first(where: {
            isExecutableRegularFile($0, fileManager: fileManager)
        }) {
            return .found(candidate)
        }
        return .notFound(attempted: standardizedCandidates)
    }

    private static func isExecutableRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
        guard fileManager.isExecutableFile(atPath: url.path),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular else {
            return false
        }
        return true
    }

    public static func locate(
        fileManager: FileManager = .default,
        executableDirectory: URL? = nil,
        currentDirectory: URL? = nil,
        applicationSupportRoot: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        locateResult(
            fileManager: fileManager,
            executableDirectory: executableDirectory,
            currentDirectory: currentDirectory,
            applicationSupportRoot: applicationSupportRoot,
            environment: environment
        ).url
    }

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

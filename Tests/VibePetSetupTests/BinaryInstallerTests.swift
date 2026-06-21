import XCTest
@testable import VibePetCore

/// M6-4: `BinaryInstaller` copies `VibePetHooks` to a stable path under Application
/// Support (decoupled from the `.app` bundle) and re-copies only when the installed
/// copy is missing or behind. Tool config always points at this stable copy.
final class BinaryInstallerTests: XCTestCase {
    func testCopiesBinaryToStablePath() throws {
        let root = try TempRoot()
        let installer = BinaryInstaller(applicationSupportRoot: root.url)
        let source = try root.makeSourceBinary(contents: "hooks-v1")

        let copied = try installer.install(from: source, version: "0.1.0", installedVersion: nil)

        XCTAssertTrue(copied)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installer.binaryURL.path))
        XCTAssertEqual(try String(contentsOf: installer.binaryURL, encoding: .utf8), "hooks-v1")
    }

    func testStablePathIsUnderSupportBinNotBundle() throws {
        let root = try TempRoot()
        let installer = BinaryInstaller(applicationSupportRoot: root.url)
        XCTAssertTrue(installer.binaryURL.path.hasSuffix("VibePet/bin/VibePetHooks"))
    }

    func testCopiedBinaryIsExecutable() throws {
        let root = try TempRoot()
        let installer = BinaryInstaller(applicationSupportRoot: root.url)
        let source = try root.makeSourceBinary(contents: "hooks-v1")

        try installer.install(from: source, version: "0.1.0", installedVersion: nil)

        let perms = try FileManager.default.attributesOfItem(atPath: installer.binaryURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual((perms?.uint16Value ?? 0) & 0o111, 0o111, "binary must be owner/group/other-executable")
    }

    func testSkipsWhenSameVersionAndIdenticalContents() throws {
        let root = try TempRoot()
        let installer = BinaryInstaller(applicationSupportRoot: root.url)
        try installer.install(from: try root.makeSourceBinary(contents: "hooks-v1"), version: "0.1.0", installedVersion: nil)

        // Same version AND identical bytes → no-op.
        let copied = try installer.install(
            from: try root.makeSourceBinary(contents: "hooks-v1"),
            version: "0.1.0",
            installedVersion: "0.1.0"
        )

        XCTAssertFalse(copied)
        XCTAssertEqual(try String(contentsOf: installer.binaryURL, encoding: .utf8), "hooks-v1")
    }

    func testRecopiesWhenContentsDifferAtSameVersion() throws {
        let root = try TempRoot()
        let installer = BinaryInstaller(applicationSupportRoot: root.url)
        try installer.install(from: try root.makeSourceBinary(contents: "hooks-v1"), version: "0.1.0", installedVersion: nil)

        // Same version string, but the source was rebuilt (different bytes) — a common
        // dev case where the version wasn't bumped. The installed copy must refresh.
        let copied = try installer.install(
            from: try root.makeSourceBinary(contents: "hooks-v2"),
            version: "0.1.0",
            installedVersion: "0.1.0"
        )

        XCTAssertTrue(copied)
        XCTAssertEqual(try String(contentsOf: installer.binaryURL, encoding: .utf8), "hooks-v2")
    }

    func testRecopiesWhenInstalledVersionIsBehind() throws {
        let root = try TempRoot()
        let installer = BinaryInstaller(applicationSupportRoot: root.url)
        try installer.install(from: try root.makeSourceBinary(contents: "hooks-v1"), version: "0.0.1", installedVersion: nil)

        let copied = try installer.install(
            from: try root.makeSourceBinary(contents: "hooks-v2"),
            version: "0.1.0",
            installedVersion: "0.0.1"
        )

        XCTAssertTrue(copied)
        XCTAssertEqual(try String(contentsOf: installer.binaryURL, encoding: .utf8), "hooks-v2")
    }

    func testRecopiesWhenBinaryMissingEvenIfVersionMatches() throws {
        let root = try TempRoot()
        let installer = BinaryInstaller(applicationSupportRoot: root.url)
        // Manifest claims installed at current version, but the binary is absent.
        let copied = try installer.install(
            from: try root.makeSourceBinary(contents: "hooks-v1"),
            version: "0.1.0",
            installedVersion: "0.1.0"
        )
        XCTAssertTrue(copied)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installer.binaryURL.path))
    }
}

/// A throwaway Application Support root for isolation.
final class TempRoot {
    let url: URL
    private var sourceCounter = 0

    init() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vp-setup-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func makeSourceBinary(contents: String) throws -> URL {
        sourceCounter += 1
        let source = url.appendingPathComponent("src-\(sourceCounter)-VibePetHooks", isDirectory: false)
        try contents.data(using: .utf8)!.write(to: source)
        return source
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

import XCTest
@testable import VibePetCore

/// `HooksBinaryLocator` discovers a `VibePetHooks` *source* to copy from, across the
/// env override, the executable directory (+ `Helpers/`), the managed copy, and dev
/// `.build` layouts — returning only an executable hit.
final class HooksBinaryLocatorTests: XCTestCase {
    func testEnvironmentOverrideWins() throws {
        let dir = try tempDir()
        let override = try makeExecutable(dir.appendingPathComponent("custom-hooks"))
        // Also drop a binary next to the "executable" to prove the override takes priority.
        _ = try makeExecutable(dir.appendingPathComponent("VibePetHooks"))

        let located = HooksBinaryLocator.locate(
            executableDirectory: dir,
            currentDirectory: dir,
            environment: [HooksBinaryLocator.environmentKey: override.path]
        )

        XCTAssertEqual(located?.standardizedFileURL, override.standardizedFileURL)
    }

    func testIgnoresNonExecutableOverride() throws {
        let dir = try tempDir()
        let plain = dir.appendingPathComponent("not-exec")
        try Data("x".utf8).write(to: plain) // exists but not executable
        let adjacent = try makeExecutable(dir.appendingPathComponent("VibePetHooks"))

        let located = HooksBinaryLocator.locate(
            executableDirectory: dir,
            currentDirectory: dir,
            environment: [HooksBinaryLocator.environmentKey: plain.path]
        )

        XCTAssertEqual(located?.standardizedFileURL, adjacent.standardizedFileURL, "falls through to the adjacent binary")
    }

    func testFindsExecutableInHelpersSubdirectory() throws {
        let dir = try tempDir()
        let helpers = dir.appendingPathComponent("Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        let helperBinary = try makeExecutable(helpers.appendingPathComponent("VibePetHooks"))

        let located = HooksBinaryLocator.locate(
            executableDirectory: dir,
            currentDirectory: dir,
            environment: [:]
        )

        XCTAssertEqual(located?.standardizedFileURL, helperBinary.standardizedFileURL)
    }

    func testReturnsNilWhenNothingFound() throws {
        let dir = try tempDir()
        let located = HooksBinaryLocator.locate(
            executableDirectory: dir,
            currentDirectory: dir,
            applicationSupportRoot: dir, // empty → no managed copy
            environment: [:]
        )
        XCTAssertNil(located)
    }

    // MARK: - Helpers

    private func tempDir() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vp-locator-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func makeExecutable(_ url: URL) throws -> URL {
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: url.path)
        return url
    }
}

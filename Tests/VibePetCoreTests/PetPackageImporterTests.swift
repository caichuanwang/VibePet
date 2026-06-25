import Foundation
@testable import VibePetCore
import XCTest

final class PetPackageImporterTests: XCTestCase {
    func testImportsStandardZipIntoImportedRoot() throws {
        let directory = try TemporaryPetImportDirectory()
        let package = directory.url.appendingPathComponent("boba-package", isDirectory: true)
        try writeCodexPet(folder: package, id: "boba", displayName: "Boba")
        let zip = try zipFolder(package, named: "boba.zip", in: directory.url)

        let importer = PetPackageImporter(store: PetAssetStore(
            applicationSupportRoot: directory.applicationSupportRoot,
            sharedPetsRoot: directory.sharedRoot
        ))
        let asset = try importer.importPackage(from: zip)

        XCTAssertEqual(asset.slug, "boba")
        XCTAssertEqual(asset.source, .imported)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.importedRoot.appendingPathComponent("boba/pet.json").path))
    }

    func testImportsSingleWrappedZip() throws {
        let directory = try TemporaryPetImportDirectory()
        let wrapper = directory.url.appendingPathComponent("wrapper", isDirectory: true)
        let package = wrapper.appendingPathComponent("cortana", isDirectory: true)
        try writeCodexPet(folder: package, id: "cortana", displayName: "Cortana")
        let zip = try zipFolder(wrapper, named: "cortana.zip", in: directory.url)

        let importer = PetPackageImporter(store: PetAssetStore(
            applicationSupportRoot: directory.applicationSupportRoot,
            sharedPetsRoot: directory.sharedRoot
        ))

        XCTAssertEqual(try importer.importPackage(from: zip).slug, "cortana")
    }

    func testImportsFinderZipWithMacOSXMetadataFolder() throws {
        let directory = try TemporaryPetImportDirectory()
        let wrapper = directory.url.appendingPathComponent("finder-wrapper", isDirectory: true)
        let package = wrapper.appendingPathComponent("mypet", isDirectory: true)
        let metadata = wrapper.appendingPathComponent("__MACOSX", isDirectory: true)
        try writeCodexPet(folder: package, id: "mypet", displayName: "My Pet")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try Data("metadata".utf8).write(to: metadata.appendingPathComponent("._mypet"))
        let zip = try zipFolder(wrapper, named: "finder.zip", in: directory.url)
        let importer = PetPackageImporter(store: PetAssetStore(
            applicationSupportRoot: directory.applicationSupportRoot,
            sharedPetsRoot: directory.sharedRoot
        ))

        let asset = try importer.importPackage(from: zip)

        XCTAssertEqual(asset.slug, "mypet")
    }

    func testImportsFolderThroughSameValidationPath() throws {
        let directory = try TemporaryPetImportDirectory()
        let package = directory.url.appendingPathComponent("folder-slug", isDirectory: true)
        try writeCodexPet(folder: package, id: "manifest-id", displayName: "Trump")
        let importer = PetPackageImporter(store: PetAssetStore(
            applicationSupportRoot: directory.applicationSupportRoot,
            sharedPetsRoot: directory.sharedRoot
        ))

        let asset = try importer.importPackage(from: package)

        XCTAssertEqual(asset.slug, "folder-slug")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.importedRoot.appendingPathComponent("folder-slug/spritesheet.webp").path))
    }

    func testReplacingExistingPetIsNonDestructiveWhenWriteFails() throws {
        let directory = try TemporaryPetImportDirectory()
        let oldDestination = directory.importedRoot.appendingPathComponent("boba", isDirectory: true)
        try writeCodexPet(folder: oldDestination, id: "boba", displayName: "Old Boba")
        let package = directory.url.appendingPathComponent("boba", isDirectory: true)
        try writeCodexPet(folder: package, id: "boba", displayName: "New Boba")
        let collidingFile = directory.importedRoot.appendingPathComponent("boba.replace-\(UUID().uuidString)")
        try Data("not a directory".utf8).write(to: collidingFile)
        let importer = PetPackageImporter(
            store: PetAssetStore(applicationSupportRoot: directory.applicationSupportRoot, sharedPetsRoot: directory.sharedRoot),
            replacementNameProvider: { _ in collidingFile.lastPathComponent }
        )

        XCTAssertThrowsError(try importer.importPackage(from: package))

        let preserved = PetAssetStore.parsePetFolder(oldDestination, source: .imported)
        XCTAssertEqual(preserved.asset?.displayName, "Old Boba")
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldDestination.appendingPathComponent("pet.json").path))
    }

    func testRejectsMissingSpritesheetWithoutPollutingImportRoot() throws {
        let directory = try TemporaryPetImportDirectory()
        let package = directory.url.appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(#"{"id":"broken","displayName":"Broken","description":"No sprite.","spritesheetPath":"spritesheet.webp"}"#.utf8)
            .write(to: package.appendingPathComponent("pet.json"))
        let importer = PetPackageImporter(store: PetAssetStore(
            applicationSupportRoot: directory.applicationSupportRoot,
            sharedPetsRoot: directory.sharedRoot
        ))

        XCTAssertThrowsError(try importer.importPackage(from: package)) { error in
            XCTAssertTrue(String(describing: error).contains("missing"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.importedRoot.appendingPathComponent("broken").path))
    }

    func testRejectsWrongGridWithoutPollutingImportRoot() throws {
        let directory = try TemporaryPetImportDirectory()
        let package = directory.url.appendingPathComponent("bad-grid", isDirectory: true)
        try writeCodexPet(folder: package, id: "bad-grid", displayName: "Bad Grid", width: 64, height: 64)
        let importer = PetPackageImporter(store: PetAssetStore(
            applicationSupportRoot: directory.applicationSupportRoot,
            sharedPetsRoot: directory.sharedRoot
        ))

        XCTAssertThrowsError(try importer.importPackage(from: package)) { error in
            XCTAssertTrue(String(describing: error).contains("1536x1872"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.importedRoot.appendingPathComponent("bad-grid").path))
    }
}

private func zipFolder(_ folder: URL, named name: String, in parent: URL) throws -> URL {
    let zipURL = parent.appendingPathComponent(name)
    let process = Process()
    process.currentDirectoryURL = folder
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.arguments = ["-qry", zipURL.path, "."]
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    return zipURL
}

private final class TemporaryPetImportDirectory {
    let url: URL
    let applicationSupportRoot: URL
    let importedRoot: URL
    let sharedRoot: URL

    init() throws {
        url = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vp-import-\(UUID().uuidString.prefix(8))", isDirectory: true)
        applicationSupportRoot = url.appendingPathComponent("Application Support", isDirectory: true)
        importedRoot = applicationSupportRoot
            .appendingPathComponent("VibePet", isDirectory: true)
            .appendingPathComponent("pets", isDirectory: true)
        sharedRoot = url.appendingPathComponent(".codex/pets", isDirectory: true)
        try FileManager.default.createDirectory(at: importedRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sharedRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

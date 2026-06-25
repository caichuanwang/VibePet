import Foundation
import ImageIO
@testable import VibePetCore
import UniformTypeIdentifiers
import XCTest

final class PetAssetStoreTests: XCTestCase {
    func testParseValidCodexPetManifest() throws {
        let directory = try TemporaryPetAssetDirectory()
        let petFolder = directory.sharedRoot.appendingPathComponent("boba", isDirectory: true)
        try writeCodexPet(folder: petFolder, id: "boba", displayName: "Boba")

        let result = PetAssetStore.parsePetFolder(petFolder, source: .shared)

        let asset = try XCTUnwrap(result.asset)
        XCTAssertNil(result.issue)
        XCTAssertEqual(asset.slug, "boba")
        XCTAssertEqual(asset.id, "boba")
        XCTAssertEqual(asset.displayName, "Boba")
        XCTAssertEqual(asset.source, .shared)
        XCTAssertEqual(asset.folderURL.standardizedFileURL, petFolder.standardizedFileURL)
        XCTAssertEqual(asset.spritesheetURL.lastPathComponent, "spritesheet.webp")
    }

    func testParseDescriptionIsOptional() throws {
        let directory = try TemporaryPetAssetDirectory()
        let petFolder = directory.sharedRoot.appendingPathComponent("minimal", isDirectory: true)
        try FileManager.default.createDirectory(at: petFolder, withIntermediateDirectories: true)
        try Data(#"{"id":"minimal","displayName":"Minimal","spritesheetPath":"spritesheet.webp"}"#.utf8)
            .write(to: petFolder.appendingPathComponent("pet.json"))
        try writeImage(
            makeSolidTestImage(width: 1536, height: 1872, red: 12, green: 140, blue: 180, alpha: 255),
            to: petFolder.appendingPathComponent("spritesheet.webp"),
            type: UTType.png.identifier
        )

        let result = PetAssetStore.parsePetFolder(petFolder, source: .shared)

        let asset = try XCTUnwrap(result.asset)
        XCTAssertNil(result.issue)
        XCTAssertEqual(asset.description, "")
    }

    func testParseStateRowsCreatesStateAnimationSpecs() throws {
        let directory = try TemporaryPetAssetDirectory()
        let petFolder = directory.sharedRoot.appendingPathComponent("custom", isDirectory: true)
        try writeCodexPet(
            folder: petFolder,
            id: "custom",
            displayName: "Custom",
            customManifestFields: #"""
,
  "states": {
    "running": { "row": 2, "durations": [10, 20] },
    "idle": { "row": 0, "durations": [30, 40] },
    "sleep": { "row": 0, "durations": [99] }
  }
"""#
        )

        let result = PetAssetStore.parsePetFolder(petFolder, source: .shared)

        let asset = try XCTUnwrap(result.asset)
        XCTAssertEqual(asset.customAnimations[.running], SpriteAnimationSpec(row: 2, durationsMs: [10, 20]))
        XCTAssertEqual(asset.customAnimations[.idle], SpriteAnimationSpec(row: 0, durationsMs: [30, 40]))
        XCTAssertNil(asset.customAnimations[.waiting])
    }

    func testParseMissingFieldReportsReadableIssue() throws {
        let directory = try TemporaryPetAssetDirectory()
        let petFolder = directory.sharedRoot.appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: petFolder, withIntermediateDirectories: true)
        try Data(#"{"id":"broken","displayName":"Broken","description":"Missing sprite."}"#.utf8)
            .write(to: petFolder.appendingPathComponent("pet.json"))

        let result = PetAssetStore.parsePetFolder(petFolder, source: .shared)

        XCTAssertNil(result.asset)
        XCTAssertEqual(result.issue?.slug, "broken")
        XCTAssertTrue(result.issue?.reason.contains("spritesheetPath") == true)
    }

    func testParseWrongGridReportsReadableIssue() throws {
        let directory = try TemporaryPetAssetDirectory()
        let petFolder = directory.sharedRoot.appendingPathComponent("bad-grid", isDirectory: true)
        try writeCodexPet(folder: petFolder, id: "bad-grid", displayName: "Bad Grid", width: 64, height: 64)

        let result = PetAssetStore.parsePetFolder(petFolder, source: .shared)

        XCTAssertNil(result.asset)
        XCTAssertEqual(result.issue?.slug, "bad-grid")
        XCTAssertTrue(result.issue?.reason.contains("1536x1872") == true)
    }

    func testParseRejectsSpritesheetPathOutsidePetFolder() throws {
        let directory = try TemporaryPetAssetDirectory()
        let petFolder = directory.sharedRoot.appendingPathComponent("escape", isDirectory: true)
        let outside = directory.url.appendingPathComponent("outside.png")
        try FileManager.default.createDirectory(at: petFolder, withIntermediateDirectories: true)
        try Data(#"{"id":"escape","displayName":"Escape","description":"Escape","spritesheetPath":"../outside.png"}"#.utf8)
            .write(to: petFolder.appendingPathComponent("pet.json"))
        try writeImage(
            makeSolidTestImage(width: 1536, height: 1872, red: 12, green: 140, blue: 180, alpha: 255),
            to: outside,
            type: UTType.png.identifier
        )

        let result = PetAssetStore.parsePetFolder(petFolder, source: .shared)

        XCTAssertNil(result.asset)
        XCTAssertEqual(result.issue?.slug, "escape")
        XCTAssertTrue(result.issue?.reason.contains("inside pet folder") == true)
    }

    func testListAggregatesRootsAndImportedPetsWinBySlug() throws {
        let directory = try TemporaryPetAssetDirectory()
        try writeCodexPet(
            folder: directory.sharedRoot.appendingPathComponent("boba", isDirectory: true),
            id: "boba",
            displayName: "Shared Boba"
        )
        let importedFolder = directory.importedRoot.appendingPathComponent("boba", isDirectory: true)
        try writeCodexPet(folder: importedFolder, id: "boba", displayName: "Imported Boba")
        try writeCodexPet(
            folder: directory.sharedRoot.appendingPathComponent("cortana", isDirectory: true),
            id: "cortana",
            displayName: "Cortana"
        )

        let store = PetAssetStore(applicationSupportRoot: directory.applicationSupportRoot, sharedPetsRoot: directory.sharedRoot)
        let assets = try store.list()

        XCTAssertEqual(assets.map(\.slug), ["boba", "cortana"])
        XCTAssertEqual(assets.first?.displayName, "Imported Boba")
        XCTAssertEqual(assets.first?.source, .imported)
        XCTAssertEqual(assets.first?.folderURL.standardizedFileURL, importedFolder.standardizedFileURL)
    }

    func testMissingSharedRootReturnsImportedOrEmptyWithoutThrowing() throws {
        let directory = try TemporaryPetAssetDirectory()
        let missingSharedRoot = directory.url.appendingPathComponent("missing-shared", isDirectory: true)
        let store = PetAssetStore(applicationSupportRoot: directory.applicationSupportRoot, sharedPetsRoot: missingSharedRoot)

        XCTAssertEqual(try store.list(), [])

        try writeCodexPet(
            folder: directory.importedRoot.appendingPathComponent("local", isDirectory: true),
            id: "local",
            displayName: "Local"
        )

        XCTAssertEqual(try store.list().map(\.slug), ["local"])
    }

    func testListSkipsInvalidAndLegacyUUIDFoldersWithoutThrowing() throws {
        let directory = try TemporaryPetAssetDirectory()
        try writeCodexPet(
            folder: directory.importedRoot.appendingPathComponent("valid", isDirectory: true),
            id: "valid",
            displayName: "Valid"
        )
        try writeCodexPet(
            folder: directory.sharedRoot.appendingPathComponent("invalid", isDirectory: true),
            id: "invalid",
            displayName: "Invalid",
            width: 32,
            height: 32
        )
        let legacy = directory.importedRoot.appendingPathComponent("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: legacy.appendingPathComponent("meta.json"))
        try writeImage(makeSolidTestImage(), to: legacy.appendingPathComponent("sprite.png"), type: UTType.png.identifier)

        let store = PetAssetStore(applicationSupportRoot: directory.applicationSupportRoot, sharedPetsRoot: directory.sharedRoot)
        let result = try store.listWithIssues()
        let assets = result.assets

        XCTAssertEqual(assets.map(\.slug), ["valid"])
        XCTAssertTrue(result.issues.contains { $0.slug == "invalid" && $0.reason.contains("1536x1872") })
        XCTAssertFalse(result.issues.contains { $0.slug.contains("AAAAAAAA") })
    }

    func testReadLooksUpSlugAcrossAggregatedRoots() throws {
        let directory = try TemporaryPetAssetDirectory()
        try writeCodexPet(
            folder: directory.sharedRoot.appendingPathComponent("trump", isDirectory: true),
            id: "trump",
            displayName: "Trump"
        )
        let store = PetAssetStore(applicationSupportRoot: directory.applicationSupportRoot, sharedPetsRoot: directory.sharedRoot)

        XCTAssertEqual(try store.read(slug: "trump")?.displayName, "Trump")
        XCTAssertNil(try store.read(slug: "missing"))
    }
}

func writeCodexPet(
    folder: URL,
    id: String,
    displayName: String,
    description: String = "A test Codex pet.",
    width: Int = 1536,
    height: Int = 1872,
    customManifestFields: String = ""
) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let manifest = """
    {
      "id": "\(id)",
      "displayName": "\(displayName)",
      "description": "\(description)",
      "spritesheetPath": "spritesheet.webp"\(customManifestFields)
    }
    """
    try Data(manifest.utf8).write(to: folder.appendingPathComponent("pet.json"))
    try writeImage(
        makeSolidTestImage(width: width, height: height, red: 12, green: 140, blue: 180, alpha: 255),
        to: folder.appendingPathComponent("spritesheet.webp"),
        type: UTType.png.identifier
    )
}

func writeImage(_ image: CGImage, to url: URL, type: String) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown)
    }
}

private final class TemporaryPetAssetDirectory {
    let url: URL
    let applicationSupportRoot: URL
    let importedRoot: URL
    let sharedRoot: URL

    init() throws {
        url = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vp-pets-\(UUID().uuidString.prefix(8))", isDirectory: true)
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

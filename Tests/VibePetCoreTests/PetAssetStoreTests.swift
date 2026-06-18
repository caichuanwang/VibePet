import Foundation
@testable import VibePetCore
import XCTest

final class PetAssetStoreTests: XCTestCase {
    func testWriteThenReadRoundTripsAssetAndAlphaPNG() throws {
        let directory = try TemporaryPetAssetDirectory()
        let store = PetAssetStore(applicationSupportRoot: directory.url)
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let sprite = try makeTestImage(alphaPattern: { x, y in (x + y).isMultiple(of: 2) ? 255 : 96 })
        let asset = PetAsset(
            id: id,
            kind: .sprite2D,
            primaryImageURL: URL(fileURLWithPath: "/placeholder/sprite.png"),
            layers: [],
            boundingInset: .zero,
            metadata: ["generator": "test"]
        )

        let written = try store.write(asset, sprite: sprite)
        let loaded = try store.read(id: id)

        XCTAssertEqual(loaded, written)
        XCTAssertEqual(written.primaryImageURL.lastPathComponent, "sprite.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.url.appendingPathComponent("VibePet/pets/\(id.uuidString)/meta.json").path))
        try assertPNGHasAlpha(at: written.primaryImageURL)
    }

    func testListAndDeleteAffectOnlyRequestedPet() throws {
        let directory = try TemporaryPetAssetDirectory()
        let store = PetAssetStore(applicationSupportRoot: directory.url)
        let firstID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let sprite = try makeTestImage()

        let first = try store.write(makeAsset(id: firstID), sprite: sprite)
        let second = try store.write(makeAsset(id: secondID), sprite: sprite)

        XCTAssertEqual(Set(try store.listIDs()), [firstID, secondID])

        try store.delete(id: firstID)

        XCTAssertNil(try store.read(id: firstID))
        XCTAssertEqual(try store.read(id: secondID), second)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.primaryImageURL.deletingLastPathComponent().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.primaryImageURL.path))
    }

    func testReadingMissingIDReturnsNil() throws {
        let directory = try TemporaryPetAssetDirectory()
        let store = PetAssetStore(applicationSupportRoot: directory.url)

        XCTAssertNil(try store.read(id: UUID()))
    }

    private func makeAsset(id: UUID) -> PetAsset {
        PetAsset(
            id: id,
            kind: .sprite2D,
            primaryImageURL: URL(fileURLWithPath: "/placeholder/\(id.uuidString)/sprite.png"),
            layers: [],
            boundingInset: .zero,
            metadata: [:]
        )
    }
}

private final class TemporaryPetAssetDirectory {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vp-pets-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

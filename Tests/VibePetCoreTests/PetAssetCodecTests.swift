import Foundation
@testable import VibePetCore
import XCTest

final class PetAssetCodecTests: XCTestCase {
    func testPetAssetCodableRoundTripsCodexFolderReference() throws {
        let asset = PetAsset(
            slug: "boba",
            displayName: "Boba",
            description: "A tiny otter sipping bubble tea.",
            source: .imported,
            folderURL: URL(fileURLWithPath: "/tmp/VibePet/pets/boba", isDirectory: true),
            spritesheetURL: URL(fileURLWithPath: "/tmp/VibePet/pets/boba/spritesheet.webp"),
            customAnimations: [
                .idle: SpriteAnimationSpec(row: 0, durationsMs: [10, 20, 30, 40, 50, 60])
            ]
        )

        let data = try JSONEncoder().encode(asset)
        let decoded = try JSONDecoder().decode(PetAsset.self, from: data)

        XCTAssertEqual(decoded, asset)
        XCTAssertEqual(decoded.id, "boba")
    }

    func testPetSourceRawValuesAreStable() throws {
        XCTAssertEqual(PetAsset.Source.imported.rawValue, "imported")
        XCTAssertEqual(PetAsset.Source.shared.rawValue, "shared")

        for source in [PetAsset.Source.imported, .shared] {
            let data = try JSONEncoder().encode(source)
            XCTAssertEqual(try JSONDecoder().decode(PetAsset.Source.self, from: data), source)
        }
    }
}

import Foundation
@testable import VibePetCore
import XCTest

final class PetAssetCodecTests: XCTestCase {
    func testPetAssetCodableRoundTripsAllFields() throws {
        let asset = PetAsset(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            kind: .sprite2D,
            primaryImageURL: URL(fileURLWithPath: "/tmp/VibePet/pets/asset/sprite.png"),
            layers: [
                PetLayer(
                    id: "eyes",
                    imageURL: URL(fileURLWithPath: "/tmp/VibePet/pets/asset/eyes.png"),
                    zIndex: 2,
                    metadata: ["animation": "blink"]
                )
            ],
            boundingInset: PetEdgeInsets(top: 1.25, leading: 2.5, bottom: 3.75, trailing: 4.0),
            metadata: ["generator": "local-cutout", "source": "unit-test"]
        )

        let data = try JSONEncoder().encode(asset)
        let decoded = try JSONDecoder().decode(PetAsset.self, from: data)

        XCTAssertEqual(decoded, asset)
    }

    func testPetKindRawValuesAreStable() throws {
        XCTAssertEqual(PetKind.sprite2D.rawValue, "sprite2D")
        XCTAssertEqual(PetKind.stylized2D.rawValue, "stylized2D")
        XCTAssertEqual(PetKind.model3D.rawValue, "model3D")

        for kind in [PetKind.sprite2D, .stylized2D, .model3D] {
            let data = try JSONEncoder().encode(kind)
            XCTAssertEqual(try JSONDecoder().decode(PetKind.self, from: data), kind)
        }
    }

    func testNoSubjectIsDistinguishable() {
        let error: GenError = .noSubject

        guard case .noSubject = error else {
            return XCTFail("Expected noSubject to be matchable")
        }

        XCTAssertNotEqual(error, .encodingFailed)
    }
}

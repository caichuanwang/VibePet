import XCTest
@testable import VibePetApp
@testable import VibePetCore

final class PetSelectionTests: XCTestCase {
    func testImportedPetBecomesSelectedEvenWhenPreviousSelectionExists() {
        let pets = [
            pet(slug: "alpha"),
            pet(slug: "boba")
        ]

        let selected = PetSelection.resolve(current: "alpha", pets: pets, preferred: "boba")

        XCTAssertEqual(selected, "boba")
    }

    func testMissingSelectedPetFallsBackToFirstAvailablePet() {
        let pets = [
            pet(slug: "alpha"),
            pet(slug: "boba")
        ]

        let selected = PetSelection.resolve(current: "deleted", pets: pets, preferred: nil)

        XCTAssertEqual(selected, "alpha")
    }

    func testKeepsExistingSelectionWhenStillAvailable() {
        let pets = [
            pet(slug: "alpha"),
            pet(slug: "boba")
        ]

        let selected = PetSelection.resolve(current: "boba", pets: pets, preferred: nil)

        XCTAssertEqual(selected, "boba")
    }

    func testNextAdvancesFromCurrentPet() {
        let pets = [
            pet(slug: "alpha"),
            pet(slug: "boba"),
            pet(slug: "coda")
        ]

        let selected = PetSelection.next(current: "boba", pets: pets)

        XCTAssertEqual(selected, "coda")
    }

    func testNextWrapsFromLastPetToFirst() {
        let pets = [
            pet(slug: "alpha"),
            pet(slug: "boba")
        ]

        let selected = PetSelection.next(current: "boba", pets: pets)

        XCTAssertEqual(selected, "alpha")
    }

    func testNextFallsBackToFirstWhenCurrentPetIsMissing() {
        let pets = [
            pet(slug: "alpha"),
            pet(slug: "boba")
        ]

        let selected = PetSelection.next(current: "deleted", pets: pets)

        XCTAssertEqual(selected, "alpha")
    }

    func testNextReturnsNilWhenFewerThanTwoPetsExist() {
        XCTAssertNil(PetSelection.next(current: "alpha", pets: [pet(slug: "alpha")]))
        XCTAssertNil(PetSelection.next(current: nil, pets: []))
    }

    private func pet(slug: String) -> PetAsset {
        PetAsset(
            slug: slug,
            displayName: slug,
            description: "",
            source: .shared,
            folderURL: URL(fileURLWithPath: "/tmp/\(slug)", isDirectory: true),
            spritesheetURL: URL(fileURLWithPath: "/tmp/\(slug)/spritesheet.webp")
        )
    }
}

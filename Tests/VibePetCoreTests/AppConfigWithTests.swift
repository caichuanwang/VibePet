@testable import VibePetCore
import XCTest

final class AppConfigWithTests: XCTestCase {
    private let base = AppConfig(
        activePetID: "pet-1",
        enabledTools: [.claudeCode],
        activeGeneratorID: "local-cutout",
        petPosition: PetPosition(x: 1, y: 2, screenWidth: 800, screenHeight: 600),
        hasCompletedOnboarding: false,
        language: .simplifiedChinese
    )

    func testWithOverridesOnlyGivenField() {
        let updated = base.with(hasCompletedOnboarding: true)
        XCTAssertTrue(updated.hasCompletedOnboarding)
        // Everything else is carried over unchanged.
        XCTAssertEqual(updated.activePetID, base.activePetID)
        XCTAssertEqual(updated.enabledTools, base.enabledTools)
        XCTAssertEqual(updated.activeGeneratorID, base.activeGeneratorID)
        XCTAssertEqual(updated.petPosition, base.petPosition)
        XCTAssertEqual(updated.language, base.language)
    }

    func testWithSetsLanguage() {
        XCTAssertEqual(base.with(language: .english).language, .english)
    }

    func testWithSetsActivePetID() {
        XCTAssertEqual(base.with(activePetID: "pet-2").activePetID, "pet-2")
    }

    func testWithCanClearActivePetID() {
        XCTAssertNil(base.with(activePetID: .some(nil)).activePetID)
    }

    func testWithNoArgumentsReturnsEqualValue() {
        XCTAssertEqual(base.with(), base)
    }
}

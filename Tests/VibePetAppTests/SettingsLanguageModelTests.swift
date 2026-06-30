import XCTest
@testable import VibePetApp
import VibePetCore

final class SettingsLanguageModelTests: XCTestCase {
    func testInitialLanguageReflectsConfig() {
        let config = AppConfig.default.with(language: .english)

        let model = SettingsLanguageModel(config: config)

        XCTAssertEqual(model.selectedLanguage, .english)
    }

    func testSelectingLanguagePersistsToConfig() {
        let model = SettingsLanguageModel(config: .default)

        let updated = model.configAfterSelecting(.english, from: .default)

        XCTAssertEqual(updated.language, .english)
    }
}

import XCTest
@testable import VibePetApp
import VibePetCore

final class AppLocalizerTests: XCTestCase {
    func testSupportedLanguagesAreExactlySimplifiedChineseAndEnglish() {
        XCTAssertEqual(AppLanguage.allCases, [.simplifiedChinese, .english])
        XCTAssertEqual(AppLanguage.simplifiedChinese.rawValue, "zh-Hans")
        XCTAssertEqual(AppLanguage.english.rawValue, "en")
    }

    func testLanguagePickerNamesStayInTheirOwnLanguage() {
        let zhLocalizer = AppLocalizer(language: .simplifiedChinese)
        let enLocalizer = AppLocalizer(language: .english)

        XCTAssertEqual(zhLocalizer.languageDisplayName(.simplifiedChinese), "简体中文")
        XCTAssertEqual(zhLocalizer.languageDisplayName(.english), "English")
        XCTAssertEqual(enLocalizer.languageDisplayName(.simplifiedChinese), "简体中文")
        XCTAssertEqual(enLocalizer.languageDisplayName(.english), "English")
    }

    func testEveryLocalizedKeyHasBothSupportedTranslations() {
        for key in AppLocalizer.Key.allCases {
            XCTAssertFalse(AppLocalizer(language: .simplifiedChinese).text(key).isEmpty, "\(key) is missing Simplified Chinese")
            XCTAssertFalse(AppLocalizer(language: .english).text(key).isEmpty, "\(key) is missing English")
        }
    }

    func testTechnicalIdentifiersRemainExactInHookGuidance() {
        let zh = AppLocalizer(language: .simplifiedChinese).text(.codexTrustGuidance)
        let en = AppLocalizer(language: .english).text(.codexTrustGuidance)

        XCTAssertTrue(zh.contains("Codex"))
        XCTAssertTrue(zh.contains("/hooks"))
        XCTAssertTrue(en.contains("Codex"))
        XCTAssertTrue(en.contains("/hooks"))
    }
}

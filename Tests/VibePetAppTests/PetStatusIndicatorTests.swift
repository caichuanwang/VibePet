import XCTest
import SwiftUI
@testable import VibePetApp

@MainActor
final class PetStatusIndicatorTests: XCTestCase {
    func testStatusIndicatorColorsFollowActivity() {
        XCTAssertEqual(PetActivity.running.statusIndicatorColor, Color(nsColor: .systemGreen))
        XCTAssertEqual(PetActivity.waiting.statusIndicatorColor, Color(nsColor: .systemOrange))
        XCTAssertEqual(PetActivity.idle.statusIndicatorColor, Color.white.opacity(0.42))
    }
}

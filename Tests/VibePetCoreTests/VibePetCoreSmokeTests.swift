import XCTest
@testable import VibePetCore

final class VibePetCoreSmokeTests: XCTestCase {
    func testProtocolVersionIsInitialized() {
        XCTAssertEqual(VibePetCore.protocolVersion, 1)
    }
}

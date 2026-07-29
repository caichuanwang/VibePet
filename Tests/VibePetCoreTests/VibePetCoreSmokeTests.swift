import XCTest
@testable import VibePetCore

final class VibePetCoreSmokeTests: XCTestCase {
    func testProtocolVersionIsInitialized() {
        XCTAssertEqual(VibePetCore.protocolVersion, 1)
    }

    func testHookBinaryVersionMatchesRelease() {
        XCTAssertEqual(VibePetCore.hookBinaryVersion, "0.2.0")
    }
}

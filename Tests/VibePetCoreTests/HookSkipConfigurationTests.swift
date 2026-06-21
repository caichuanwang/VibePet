import XCTest
@testable import VibePetCore

/// The `VIBEPET_SKIP_HOOKS` per-process opt-out: a wrapper can no-op a single child
/// agent's hook without changing global install state.
final class HookSkipConfigurationTests: XCTestCase {
    func testSkipsOnTruthyValues() {
        for value in ["1", "true", "TRUE", "yes", "on", " on "] {
            XCTAssertTrue(
                HookSkipConfiguration.shouldSkip(environment: [HookSkipConfiguration.skipKey: value]),
                "\(value) should be truthy"
            )
        }
    }

    func testDoesNotSkipOnFalsyOrAbsent() {
        XCTAssertFalse(HookSkipConfiguration.shouldSkip(environment: [:]))
        for value in ["0", "false", "no", "off", "", "maybe"] {
            XCTAssertFalse(
                HookSkipConfiguration.shouldSkip(environment: [HookSkipConfiguration.skipKey: value]),
                "\(value) should not be truthy"
            )
        }
    }
}

import CoreGraphics
@testable import VibePetCore
import XCTest

final class ScreenSnapTests: XCTestCase {
    private let visibleFrame = CGRect(x: 0, y: 0, width: 800, height: 600)
    private let spriteSize = CGSize(width: 120, height: 120)

    func testDefaultPlacementIsInsetFromRightAndFlushWithBottom() {
        let frame = ScreenSnap.defaultFrame(spriteSize: spriteSize, in: visibleFrame)

        XCTAssertEqual(frame.origin.x, 656)
        XCTAssertEqual(frame.origin.y, 0)
        XCTAssertEqual(frame.size, spriteSize)
    }

    func testReleaseNearRightEdgeSnapsInsetAndPreservesY() {
        let released = CGRect(x: 670, y: 220, width: 120, height: 120)

        let snapped = ScreenSnap.snap(released, in: visibleFrame)

        XCTAssertEqual(snapped.origin.x, 672)
        XCTAssertEqual(snapped.origin.y, 220)
    }

    func testReleaseAwayFromEdgesDoesNotSnap() {
        let released = CGRect(x: 300, y: 220, width: 120, height: 120)

        let snapped = ScreenSnap.snap(released, in: visibleFrame)

        XCTAssertEqual(snapped, released)
    }

    func testReleaseNearTwoEdgesSettlesIntoCorner() {
        let released = CGRect(x: 670, y: 10, width: 120, height: 120)

        let snapped = ScreenSnap.snap(released, in: visibleFrame)

        XCTAssertEqual(snapped.origin.x, 672)
        XCTAssertEqual(snapped.origin.y, 8)
    }

    func testClampKeepsFrameFullyInsideVisibleFrame() {
        let outside = CGRect(x: 760, y: -20, width: 120, height: 120)

        let clamped = ScreenSnap.clamp(outside, in: visibleFrame)

        XCTAssertEqual(clamped.origin.x, 680)
        XCTAssertEqual(clamped.origin.y, 0)
    }

    func testPressReleaseBelowDragThresholdIsClick() {
        let start = CGPoint(x: 20, y: 20)
        let current = CGPoint(x: 24, y: 23)

        XCTAssertEqual(ScreenSnap.dragIntent(from: start, to: current), .click)
    }

    func testPressReleaseAtDragThresholdIsDrag() {
        let start = CGPoint(x: 20, y: 20)
        let current = CGPoint(x: 26, y: 28)

        XCTAssertEqual(ScreenSnap.dragIntent(from: start, to: current), .drag)
    }
}

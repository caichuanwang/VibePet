import CoreGraphics
import XCTest
@testable import VibePetCore

final class BubbleAnchorTests: XCTestCase {
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let bubbleSize = CGSize(width: 300, height: 160)

    func testLowerRightQuadrantOpensUpAndLeft() {
        // Pet near the bottom-right corner.
        let petFrame = CGRect(x: 850, y: 20, width: 120, height: 120)
        let placement = BubbleAnchor.place(petFrame: petFrame, bubbleSize: bubbleSize, in: visibleFrame)

        XCTAssertEqual(placement.vertical, .up)
        XCTAssertEqual(placement.horizontal, .left)
        // Opens up → bubble sits above the pet body.
        XCTAssertGreaterThanOrEqual(placement.frame.minY, petFrame.maxY)
        // Tail points from the bottom edge of the bubble toward the pet.
        XCTAssertEqual(placement.tail.y, placement.frame.minY)
    }

    func testUpperLeftQuadrantOpensDownAndRight() {
        let petFrame = CGRect(x: 40, y: 660, width: 120, height: 120)
        let placement = BubbleAnchor.place(petFrame: petFrame, bubbleSize: bubbleSize, in: visibleFrame)

        XCTAssertEqual(placement.vertical, .down)
        XCTAssertEqual(placement.horizontal, .right)
        XCTAssertLessThanOrEqual(placement.frame.maxY, petFrame.minY)
        XCTAssertEqual(placement.tail.y, placement.frame.maxY)
    }

    func testBubbleIsClampedWithinVisibleFrame() {
        let petFrame = CGRect(x: 960, y: 20, width: 120, height: 120)
        let placement = BubbleAnchor.place(petFrame: petFrame, bubbleSize: bubbleSize, in: visibleFrame)

        XCTAssertGreaterThanOrEqual(placement.frame.minX, visibleFrame.minX + BubbleAnchor.edgeInset - 0.001)
        XCTAssertLessThanOrEqual(placement.frame.maxX, visibleFrame.maxX - BubbleAnchor.edgeInset + 0.001)
        XCTAssertGreaterThanOrEqual(placement.frame.minY, visibleFrame.minY + BubbleAnchor.edgeInset - 0.001)
        XCTAssertLessThanOrEqual(placement.frame.maxY, visibleFrame.maxY - BubbleAnchor.edgeInset + 0.001)
    }

    func testTailStaysWithinBubbleEdgeAfterClamping() {
        let petFrame = CGRect(x: 980, y: 20, width: 120, height: 120)
        let placement = BubbleAnchor.place(petFrame: petFrame, bubbleSize: bubbleSize, in: visibleFrame)

        XCTAssertGreaterThanOrEqual(placement.tail.x, placement.frame.minX + BubbleAnchor.cornerInset - 0.001)
        XCTAssertLessThanOrEqual(placement.tail.x, placement.frame.maxX - BubbleAnchor.cornerInset + 0.001)
    }

    func testPetPinnedToTopFlipsToOpenDown() {
        // Pet center is in the upper half (would open down) and already flush with
        // the top — opening down must remain feasible within the frame.
        let petFrame = CGRect(x: 40, y: 700, width: 120, height: 120)
        let placement = BubbleAnchor.place(petFrame: petFrame, bubbleSize: bubbleSize, in: visibleFrame)

        XCTAssertEqual(placement.vertical, .down)
        XCTAssertLessThanOrEqual(placement.frame.maxY, visibleFrame.maxY - BubbleAnchor.edgeInset + 0.001)
    }
}

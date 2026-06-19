import XCTest
@testable import VibePetApp

/// M4-7: the pure FIFO queue behind concurrent approval stacking.
final class BubbleQueueTests: XCTestCase {
    private struct Item: Identifiable {
        let id: UUID
        let label: String
    }

    func testFIFOOrderWithEarliestOnTop() {
        var queue = BubbleQueue<Item>()
        let a = Item(id: UUID(), label: "A")
        let b = Item(id: UUID(), label: "B")
        queue.enqueue(a)
        queue.enqueue(b)

        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.front?.id, a.id, "earliest arrival is on top")
        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testRemoveFrontByMatchingIdAdvancesQueue() {
        var queue = BubbleQueue<Item>()
        let a = Item(id: UUID(), label: "A")
        let b = Item(id: UUID(), label: "B")
        queue.enqueue(a)
        queue.enqueue(b)

        XCTAssertEqual(queue.removeFront(id: a.id)?.label, "A")
        XCTAssertEqual(queue.front?.id, b.id)
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testRemoveFrontIgnoresStaleId() {
        var queue = BubbleQueue<Item>()
        let a = Item(id: UUID(), label: "A")
        let b = Item(id: UUID(), label: "B")
        queue.enqueue(a)
        queue.enqueue(b)

        // A stale callback for B (not the front) must not pop A.
        XCTAssertNil(queue.removeFront(id: b.id))
        XCTAssertEqual(queue.front?.id, a.id)
        XCTAssertEqual(queue.count, 2)
    }

    func testDrainEmptiesAndReturnsAll() {
        var queue = BubbleQueue<Item>()
        queue.enqueue(Item(id: UUID(), label: "A"))
        queue.enqueue(Item(id: UUID(), label: "B"))

        let drained = queue.drain()
        XCTAssertEqual(drained.count, 2)
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testPendingCountNeverNegative() {
        let queue = BubbleQueue<Item>()
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertNil(queue.front)
    }
}

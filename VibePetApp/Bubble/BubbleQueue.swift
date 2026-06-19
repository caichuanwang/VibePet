import Foundation

/// FIFO queue of pending response-bearing bubbles keyed by `requestId`
/// (technical design §5.3.5). The front element is the presented card; the rest
/// peek behind it. Pure and UI-independent so the ordering / pop logic is unit
/// tested without AppKit. The earliest arrival stays on top (FIFO).
struct BubbleQueue<Item: Identifiable> where Item.ID == UUID {
    private(set) var items: [Item] = []

    var front: Item? { items.first }
    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    /// Number of cards waiting behind the presented (front) one.
    var pendingCount: Int { max(0, items.count - 1) }

    mutating func enqueue(_ item: Item) {
        items.append(item)
    }

    /// Removes and returns the front iff its id matches — so a duplicate callback
    /// or a stale timeout cannot pop the wrong (already-advanced) item.
    @discardableResult
    mutating func removeFront(id: UUID) -> Item? {
        guard let first = items.first, first.id == id else { return nil }
        return items.removeFirst()
    }

    /// Drains the whole queue (e.g. fail-open when the pet is hidden).
    mutating func drain() -> [Item] {
        let all = items
        items.removeAll()
        return all
    }
}

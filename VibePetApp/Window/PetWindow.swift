import AppKit
import CoreGraphics

final class PetWindow: NSWindow {
    static let defaultSpriteSize = CGSize(width: 120, height: 120)

    init(frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool {
        true
    }
}

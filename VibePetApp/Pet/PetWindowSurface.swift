import AppKit
import SwiftUI
import VibePetCore

/// Production `PetSurface`: renders the pet sprite into the real `PetWindow` and
/// presents notification bubbles in a borderless, transparent, floating window
/// anchored by `PetController` via `BubbleAnchor`. One bubble at a time —
/// stacking/queueing is M4-7.
@MainActor
final class PetWindowSurface: PetSurface {
    private weak var windowController: PetWindowController?
    private var isPetVisible = false
    private var bubbleWindow: NSWindow?

    func bind(windowController: PetWindowController?) {
        self.windowController = windowController
    }

    func setPetVisible(_ visible: Bool) {
        isPetVisible = visible
        if !visible {
            dismissBubble()
        }
    }

    var petFrame: CGRect? {
        isPetVisible ? windowController?.window?.frame : nil
    }

    var visibleFrame: CGRect {
        NSScreen.main?.visibleFrame ?? .zero
    }

    func renderPet(asset: PetAsset?, activity: PetActivity) {
        guard let windowController else { return }
        windowController.setContent(PetView(asset: asset, activity: activity))
        windowController.setHitSprite(asset.flatMap { ImageLoading.cgImage(at: $0.primaryImageURL) })
    }

    func presentBubble(
        content: BubbleContent,
        source: SourceInfo,
        placement: BubbleAnchor.Placement,
        onDismiss: @escaping () -> Void
    ) {
        let tailEdge: SpeechBubble.TailEdge = placement.vertical == .up ? .bottom : .top
        let tailOffsetX = placement.tail.x - placement.frame.minX

        dismissBubble()

        let bubble = SpeechBubble(
            content: content,
            source: source,
            tailEdge: tailEdge,
            tailOffsetX: tailOffsetX,
            onDismiss: onDismiss
        )

        let window = BubbleWindow(contentRect: placement.frame)
        window.contentViewController = NSHostingController(rootView: bubble)
        window.setFrame(placement.frame, display: true)
        window.orderFront(nil)
        bubbleWindow = window
    }

    func dismissBubble() {
        bubbleWindow?.orderOut(nil)
        bubbleWindow = nil
    }
}

/// Borderless, transparent, floating window that hosts a `SpeechBubble`. It never
/// becomes key so it doesn't steal focus from the user's editor / terminal.
private final class BubbleWindow: NSWindow {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

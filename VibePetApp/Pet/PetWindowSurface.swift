import AppKit
import SwiftUI
import VibePetCore

/// Production `PetSurface`: renders the pet sprite into the real `PetWindow` and
/// presents notification / approval bubbles in a borderless, transparent, floating
/// window anchored by `PetController` via `BubbleAnchor`. Queued approvals peek
/// behind the front card (`BubbleStackView`); notifications deferred during a
/// decision show a small count badge on the pet.
@MainActor
final class PetWindowSurface: PetSurface {
    private weak var windowController: PetWindowController?
    private var isPetVisible = false
    private var bubbleWindow: NSWindow?
    private var approvalPresentation: ApprovalPresentation?
    private var badgeWindow: NSWindow?

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

    // MARK: - Approval (decide)

    func presentApproval(
        content: ApprovalContent,
        source: SourceInfo,
        placement: BubbleAnchor.Placement,
        timeout: TimeInterval,
        pendingCount: Int,
        onDecision: @escaping (BridgeResponse) -> Void
    ) {
        dismissBubble()

        let presentation = ApprovalPresentation(pendingCount: pendingCount)
        approvalPresentation = presentation

        // The controller's `placement` is computed from a guessed size; the real
        // card is shorter, so re-anchor to the card's actual fitting size. Otherwise
        // the card centers inside an over-tall window and floats away from the pet.
        let measuringEdge: SpeechBubble.TailEdge = placement.vertical == .up ? .bottom : .top
        let cardSize = Self.fittingSize(
            for: ApprovalCard(
                content: content,
                source: source,
                tailEdge: measuringEdge,
                tailOffsetX: 0,
                timeout: timeout,
                presentation: presentation,
                onDecision: { _ in }
            )
        )
        // Allowance so queued cards can peek beyond the front one.
        let peek = min(pendingCount, 2)
        let bubbleSize = CGSize(
            width: cardSize.width + CGFloat(peek) * 14,
            height: cardSize.height + CGFloat(peek) * 7
        )

        let petFrame = windowController?.window?.frame ?? placement.frame
        let finalPlacement = BubbleAnchor.place(petFrame: petFrame, bubbleSize: bubbleSize, in: visibleFrame)
        let tailEdge: SpeechBubble.TailEdge = finalPlacement.vertical == .up ? .bottom : .top
        let tailOffsetX = finalPlacement.tail.x - finalPlacement.frame.minX

        let stack = BubbleStackView(presentation: presentation, tailEdge: tailEdge) {
            ApprovalCard(
                content: content,
                source: source,
                tailEdge: tailEdge,
                tailOffsetX: tailOffsetX,
                timeout: timeout,
                presentation: presentation,
                onDecision: onDecision
            )
        }

        // Interactive: must become key for buttons + keyboard shortcuts to work.
        let window = BubbleWindow(contentRect: finalPlacement.frame, interactive: true)
        window.contentViewController = NSHostingController(rootView: stack)
        window.setFrame(finalPlacement.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        bubbleWindow = window
    }

    /// Measures a SwiftUI view's content size off-screen so the bubble window can be
    /// sized to hug the card (and therefore the pet).
    private static func fittingSize(for view: some View) -> CGSize {
        let hosting = NSHostingController(rootView: view)
        hosting.view.layoutSubtreeIfNeeded()
        var size = hosting.view.fittingSize
        size.width = min(max(size.width, BubbleTheme.minWidth), BubbleTheme.maxWidth)
        if size.height <= 1 { size.height = 160 }
        return size
    }

    func updatePendingCount(_ count: Int) {
        // Live update so the front card's "还有 N 个待处理" and the peeking stack
        // reflect newly-queued approvals without recreating (which resets countdown).
        approvalPresentation?.pendingCount = count
    }

    func dismissApproval() {
        approvalPresentation = nil
        dismissBubble()
    }

    func updateNotificationBadge(_ count: Int) {
        guard count > 0 else {
            badgeWindow?.orderOut(nil)
            badgeWindow = nil
            return
        }
        guard let petFrame = windowController?.window?.frame else { return }

        let size = CGSize(width: 28, height: 20)
        let frame = CGRect(
            x: petFrame.maxX - size.width + 4,
            y: petFrame.maxY - size.height + 4,
            width: size.width,
            height: size.height
        )

        let badge = NotificationBadge(count: count)
        let window = badgeWindow ?? BubbleWindow(contentRect: frame)
        window.contentViewController = NSHostingController(rootView: badge)
        window.setFrame(frame, display: true)
        window.orderFront(nil)
        badgeWindow = window
    }
}

/// A small red count badge shown on the pet while notifications pile up during a
/// decision (decide > notify, technical design §5.3.5).
private struct NotificationBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 4)
            .background(Color(nsColor: .systemRed), in: Capsule())
            .accessibilityLabel("\(count) 条待查看通知")
    }
}

/// Borderless, transparent, floating window that hosts a bubble. Notification
/// bubbles never become key (so they don't steal focus from the editor/terminal);
/// the interactive approval card must become key so its buttons and keyboard
/// shortcuts (esc / ⌘↩) work.
private final class BubbleWindow: NSWindow {
    private let interactive: Bool

    init(contentRect: CGRect, interactive: Bool = false) {
        self.interactive = interactive
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

    override var canBecomeKey: Bool { interactive }
    override var canBecomeMain: Bool { false }
}

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
    static let bubbleOverlayCollectionBehavior = PetWindow.overlayCollectionBehavior

    private weak var windowController: PetWindowController?
    private var isPetVisible = false
    private var bubbleWindow: NSWindow?
    private var approvalPresentation: ApprovalPresentation?
    private var badgeWindow: NSWindow?
    private var petSwitchTooltipWindow: NSWindow?
    private var lastRenderedPetSlug: String?
    weak var dashboardController: SessionDashboardWindowController?
    var selectedDashboardSessionID: String?
    var selectedDashboardJumpTarget: JumpTarget?

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
        // Anchor bubbles to the screen the pet actually lives on. `NSScreen.main`
        // is the *focused* screen (the one with the key window), so on multi-monitor
        // setups it clamps the bubble onto the wrong display instead of above the
        // pet. The pet window's own `screen` is the display it mostly occupies.
        windowController?.window?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
    }

    func renderPet(asset: PetAsset?, activity: PetActivity) {
        guard let windowController else { return }
        let previousSlug = lastRenderedPetSlug
        let newSlug = asset?.slug
        let switchedPet = previousSlug != nil && previousSlug != newSlug
        lastRenderedPetSlug = newSlug

        let shouldFade = switchedPet && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        windowController.setContent(PetView(asset: asset, activity: activity) { [weak windowController] frame in
            windowController?.setHitSprite(frame)
        }, fade: shouldFade)
        if asset == nil {
            windowController.setHitSprite(nil)
        }
    }

    func showPetSwitchTooltip(name: String) {
        guard let petFrame = windowController?.window?.frame else { return }
        petSwitchTooltipWindow?.orderOut(nil)

        let size = CGSize(width: max(96, min(180, CGFloat(name.count) * 9 + 32)), height: 30)
        let frame = CGRect(
            x: petFrame.midX - size.width / 2,
            y: petFrame.maxY + 8,
            width: size.width,
            height: size.height
        )

        let window = BubbleWindow(contentRect: frame)
        window.contentViewController = NSHostingController(rootView: PetSwitchTooltip(name: name))
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        petSwitchTooltipWindow = window

        Task { @MainActor [weak self, weak window] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard self?.petSwitchTooltipWindow === window else { return }
            window?.orderOut(nil)
            self?.petSwitchTooltipWindow = nil
        }
    }

    func updateDashboardContent() {
        dashboardController?.refreshContent()
    }

    func presentBubble(
        content: BubbleContent,
        source: SourceInfo,
        placement: BubbleAnchor.Placement,
        onJump: @escaping (JumpTarget) -> Void,
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
            onJump: onJump,
            onDismiss: onDismiss
        )

        let window = BubbleWindow(contentRect: placement.frame)
        window.contentViewController = NSHostingController(rootView: bubble)
        window.setFrame(placement.frame, display: true)
        window.orderFrontRegardless()
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
        pendingCount: Int,
        onJump: @escaping (JumpTarget) -> Void,
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
                presentation: presentation,
                onJump: onJump,
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
                presentation: presentation,
                onJump: onJump,
                onDecision: onDecision
            )
        }

        // Interactive: must become key for buttons + keyboard shortcuts to work.
        // `orderFrontRegardless` + `makeKey` shows it on the active Space (incl. a
        // full-screen app's Space) without activating the app and switching Spaces.
        let window = BubbleWindow(contentRect: finalPlacement.frame, interactive: true)
        window.contentViewController = NSHostingController(rootView: stack)
        window.setFrame(finalPlacement.frame, display: true)
        window.orderFrontRegardless()
        window.makeKey()
        bubbleWindow = window
    }

    // MARK: - Question (decide)

    func presentQuestion(
        content: QuestionContent,
        source: SourceInfo,
        conversationContext: QuestionConversationContext?,
        placement: BubbleAnchor.Placement,
        pendingCount: Int,
        onJump: @escaping (JumpTarget) -> Void,
        onAnswer: @escaping (BridgeResponse) -> Void
    ) {
        dismissBubble()

        let presentation = ApprovalPresentation(pendingCount: pendingCount)
        approvalPresentation = presentation

        // Re-anchor to the card's actual fitting size (see presentApproval).
        let measuringEdge: SpeechBubble.TailEdge = placement.vertical == .up ? .bottom : .top
        let cardSize = Self.fittingSize(
            for: QuestionCard(
                content: content,
                source: source,
                conversationContext: conversationContext,
                tailEdge: measuringEdge,
                tailOffsetX: 0,
                presentation: presentation,
                onJump: onJump,
                onAnswer: { _ in }
            )
        )
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
            QuestionCard(
                content: content,
                source: source,
                conversationContext: conversationContext,
                tailEdge: tailEdge,
                tailOffsetX: tailOffsetX,
                presentation: presentation,
                onJump: onJump,
                onAnswer: onAnswer
            )
        }

        // Interactive: must become key for option taps + ⌘↩ submit to work.
        // `orderFrontRegardless` + `makeKey` shows it on the active Space (incl. a
        // full-screen app's Space) without activating the app and switching Spaces.
        let window = BubbleWindow(contentRect: finalPlacement.frame, interactive: true)
        window.contentViewController = NSHostingController(rootView: stack)
        window.setFrame(finalPlacement.frame, display: true)
        window.orderFrontRegardless()
        window.makeKey()
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
        window.orderFrontRegardless()
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

private struct PetSwitchTooltip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(BubbleTheme.dashboardPrimaryText)
            .background(BubbleTheme.dashboardCardBackground, in: Capsule())
            .overlay(
                Capsule().stroke(BubbleTheme.dashboardBorder, lineWidth: 1)
            )
    }
}

/// Borderless, transparent, floating panel that hosts a bubble. Notification
/// bubbles never become key (so they don't steal focus from the editor/terminal);
/// the interactive approval card must become key so its buttons and keyboard
/// shortcuts (esc / ⌘↩) work.
///
/// This is a `.nonactivatingPanel` (not a plain `NSWindow`) so it can become key
/// for its controls *without activating the app*. A regular window made key while a
/// full-screen app is frontmost forces macOS to switch back to the desktop Space —
/// which previously stranded the question/approval bubble on the wrong Space instead
/// of floating it over the full-screen app (matching the pet panel's behavior).
private final class BubbleWindow: NSPanel {
    private let interactive: Bool

    init(contentRect: CGRect, interactive: Bool = false) {
        self.interactive = interactive
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = true
        collectionBehavior = PetWindowSurface.bubbleOverlayCollectionBehavior
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { interactive }
    override var canBecomeMain: Bool { false }
}

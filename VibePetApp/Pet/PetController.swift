import AppKit
import SwiftUI
import VibePetCore

/// The single entry point for pet behavior (technical design §5.2). It owns the
/// `PetStateMachine` and maps `idle / greet / notify / decide` to what the pet
/// surface renders, to the notification bubble lifecycle, and to the blocking
/// approval round trip. Both the startup greeting and bridge-driven traffic flow
/// through here, so there is one source of truth for pet state.
///
/// Rendering is delegated to a `PetSurface` seam so the orchestration is testable
/// without AppKit; the production surface drives the real windows.
@MainActor
final class PetController {
    private var machine = PetStateMachine()
    private let surface: PetSurface
    private var activeAsset: PetAsset?

    /// How long the greeting state lasts before auto-returning to idle. Mirrors the
    /// `PetView` visual animation length; injectable so tests don't wait in realtime.
    private let greetDuration: TimeInterval
    private var greetEndTask: Task<Void, Never>?

    /// Decision deadline before an unanswered approval fails open (`.defer`). This
    /// is the App-side countdown; the CLI read deadline is the ultimate backstop.
    private let decisionTimeout: TimeInterval

    /// FIFO of pending approvals; the front is the presented card. Earliest arrival
    /// is on top (technical design §5.3.5). The queue lives here so concurrent
    /// approvals never clobber each other's continuation.
    private struct PendingDecision: Identifiable {
        let envelope: BridgeEnvelope
        let continuation: CheckedContinuation<BridgeResponse, Never>
        var id: UUID { envelope.requestId }
    }
    private var decisions = BubbleQueue<PendingDecision>()
    private var decisionTimeoutTask: Task<Void, Never>?

    /// Notifications that arrived while a decision was active (decide > notify):
    /// they accumulate as a badge instead of clobbering the approval card.
    private var notificationBadge = 0

    init(
        surface: PetSurface,
        greetDuration: TimeInterval = PetAnimations.greetDuration,
        decisionTimeout: TimeInterval = AppConfig.default.decisionTimeoutSeconds
    ) {
        self.surface = surface
        self.greetDuration = greetDuration
        self.decisionTimeout = decisionTimeout
    }

    /// Updates the active pet sprite and re-renders the current state.
    func setActiveAsset(_ asset: PetAsset?) {
        activeAsset = asset
        render()
    }

    /// Plays the greeting (startup / daily first run) via the state machine, then
    /// schedules a return to idle so `.greet` is transient instead of sticking — the
    /// greeting has no bubble to dismiss, so nothing else would move it back.
    func greet() {
        machine.greet()
        render()

        greetEndTask?.cancel()
        let nanos = UInt64(greetDuration * 1_000_000_000)
        greetEndTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            self?.greetingFinished()
        }
    }

    /// Routes an incoming notification envelope (`completion` / `status`). Response
    /// -bearing content goes through `requestDecision` instead. `decide` has
    /// priority over `notify`: while an approval is active, a notification does not
    /// clobber the card (it accumulates a badge in M4-7).
    func handle(_ envelope: BridgeEnvelope) {
        guard decisions.isEmpty else {
            // decide has priority over notify; tally a badge instead of clobbering.
            notificationBadge += 1
            surface.updateNotificationBadge(notificationBadge)
            return
        }
        guard machine.receive(envelope.content) else {
            return
        }

        guard let petFrame = surface.petFrame else {
            // Pet hidden / no window → nothing to anchor to; drop back to idle.
            machine.bubbleDismissed()
            render()
            return
        }

        let placement = BubbleAnchor.place(
            petFrame: petFrame,
            bubbleSize: bubbleSize(for: envelope.content),
            in: surface.visibleFrame
        )
        render()
        surface.presentBubble(
            content: envelope.content,
            source: envelope.source,
            placement: placement,
            onDismiss: { [weak self] in self?.handleBubbleDismissed() }
        )
    }

    /// Presents an approval bubble and suspends until the user decides (or the
    /// deadline elapses → `.defer`). Called off the main actor by `BridgeServerHost`
    /// for response-bearing envelopes; the returned `BridgeResponse` is paired back
    /// to the request by `requestId` upstream. Concurrent calls are queued FIFO so
    /// they never clobber each other's continuation.
    func requestDecision(for envelope: BridgeEnvelope) async -> BridgeResponse {
        guard envelope.content.needsResponse else {
            // Only response-bearing content (`approval` / `question`) is interactive.
            return .defer
        }

        return await withCheckedContinuation { continuation in
            decisions.enqueue(
                PendingDecision(envelope: envelope, continuation: continuation)
            )
            if decisions.count == 1 {
                presentFrontDecision()
            } else {
                surface.updatePendingCount(decisions.pendingCount)
            }
        }
    }

    /// State the pet should currently display, for the surface to map to a sprite
    /// activity. Exposed for tests.
    var state: PetStateMachine.State {
        machine.state
    }

    /// Number of approvals waiting behind the presented one. Exposed for tests.
    var pendingDecisionCount: Int {
        decisions.pendingCount
    }

    // MARK: - Decide

    private func presentFrontDecision() {
        guard let front = decisions.front else {
            // Queue drained → leave decide and clear any accumulated badge.
            machine.bubbleDismissed()
            surface.dismissApproval()
            notificationBadge = 0
            surface.updateNotificationBadge(0)
            render()
            return
        }

        guard let petFrame = surface.petFrame else {
            // Pet hidden → cannot present an interactive bubble; fail open for all.
            failOpenAllDecisions()
            return
        }

        machine.beginDecision()
        render()

        let placement = BubbleAnchor.place(
            petFrame: petFrame,
            bubbleSize: bubbleSize(for: front.envelope.content),
            in: surface.visibleFrame
        )
        startDecisionTimeout(for: front.id)

        let onDecision: (BridgeResponse) -> Void = { [weak self] response in
            self?.resolveDecision(requestId: front.id, with: response)
        }

        switch front.envelope.content {
        case let .approval(approval):
            surface.presentApproval(
                content: approval,
                source: front.envelope.source,
                placement: placement,
                timeout: decisionTimeout,
                pendingCount: decisions.pendingCount,
                onDecision: onDecision
            )
        case let .question(question):
            surface.presentQuestion(
                content: question,
                source: front.envelope.source,
                placement: placement,
                timeout: decisionTimeout,
                pendingCount: decisions.pendingCount,
                onAnswer: onDecision
            )
        case .completion, .status:
            // Non-interactive content never enters the decision queue (guarded by
            // `requestDecision`); fail open defensively if it ever does.
            resolveDecision(requestId: front.id, with: .defer)
        }
    }

    /// Resolves the front decision iff `requestId` still matches it, so a duplicate
    /// callback or a stale timeout can never resume a continuation twice or resolve
    /// the wrong request (single-resume guard, technical design D2).
    private func resolveDecision(requestId: UUID, with response: BridgeResponse) {
        guard let front = decisions.removeFront(id: requestId) else {
            return
        }
        decisionTimeoutTask?.cancel()
        decisionTimeoutTask = nil
        front.continuation.resume(returning: response)
        presentFrontDecision()
    }

    private func startDecisionTimeout(for requestId: UUID) {
        decisionTimeoutTask?.cancel()
        let nanos = UInt64(decisionTimeout * 1_000_000_000)
        decisionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            self?.resolveDecision(requestId: requestId, with: .defer)
        }
    }

    private func failOpenAllDecisions() {
        let pending = decisions.drain()
        decisionTimeoutTask?.cancel()
        decisionTimeoutTask = nil
        for item in pending {
            item.continuation.resume(returning: .defer)
        }
        machine.bubbleDismissed()
        surface.dismissApproval()
        render()
    }

    private func greetingFinished() {
        machine.greetFinished()
        render()
    }

    private func handleBubbleDismissed() {
        machine.bubbleDismissed()
        surface.dismissBubble()
        render()
    }

    private func render() {
        surface.renderPet(asset: activeAsset, activity: activity(for: machine.state))
    }

    private func activity(for state: PetStateMachine.State) -> PetActivity {
        switch state {
        case .greet:
            return .greeting
        case .decide:
            // Highlight the pet for attention while an approval awaits a decision.
            return .deciding
        case .idle, .notify:
            // notify keeps the resting sprite; the bubble carries the notification.
            return .idle
        }
    }

    private func bubbleSize(for content: BubbleContent) -> CGSize {
        switch content {
        case .status:
            return CGSize(width: 300, height: 64)
        case .completion:
            return CGSize(width: 340, height: 184)
        case .approval:
            // Three sections: source+risk header / preview body / countdown+buttons.
            return CGSize(width: 360, height: 230)
        case .question:
            return CGSize(width: 320, height: 120)
        }
    }
}

/// Rendering seam used by `PetController`. The production implementation drives
/// the real pet window and a borderless bubble window; tests substitute a fake.
@MainActor
protocol PetSurface: AnyObject {
    /// Current pet body frame in screen coordinates, or nil when the pet is hidden.
    var petFrame: CGRect? { get }
    /// Usable screen area for bubble clamping.
    var visibleFrame: CGRect { get }
    func renderPet(asset: PetAsset?, activity: PetActivity)
    func presentBubble(
        content: BubbleContent,
        source: SourceInfo,
        placement: BubbleAnchor.Placement,
        onDismiss: @escaping () -> Void
    )
    func dismissBubble()
    /// Presents an interactive approval card. `onDecision` is invoked exactly once
    /// with the user's choice (or `.defer` from the card's own countdown).
    func presentApproval(
        content: ApprovalContent,
        source: SourceInfo,
        placement: BubbleAnchor.Placement,
        timeout: TimeInterval,
        pendingCount: Int,
        onDecision: @escaping (BridgeResponse) -> Void
    )
    /// Presents an interactive structured-question card. `onAnswer` is invoked
    /// exactly once with `.question(QuestionAnswer)` on submit, or `.defer` from the
    /// card's own countdown / dismissal.
    func presentQuestion(
        content: QuestionContent,
        source: SourceInfo,
        placement: BubbleAnchor.Placement,
        timeout: TimeInterval,
        pendingCount: Int,
        onAnswer: @escaping (BridgeResponse) -> Void
    )
    /// Updates the "还有 N 个待处理" badge while the front card stays presented.
    func updatePendingCount(_ count: Int)
    func dismissApproval()
    /// Updates the small badge counting notifications deferred while deciding.
    func updateNotificationBadge(_ count: Int)
}

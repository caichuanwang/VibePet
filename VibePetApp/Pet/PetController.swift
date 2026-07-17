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
    private let terminalJump: (JumpTarget) -> Void
    private let openDashboard: () -> Void
    private var activeAsset: PetAsset?

    /// How long the greeting state lasts before auto-returning to idle. Mirrors the
    /// `PetView` visual animation length; injectable so tests don't wait in realtime.
    private let greetDuration: TimeInterval
    private let decisionTimeoutProvider: @Sendable (ToolKind) -> TimeInterval
    private var greetEndTask: Task<Void, Never>?
    private var decisionTimeoutTasks: [UUID: Task<Void, Never>] = [:]

    /// FIFO of pending approvals; the front is the presented card. Earliest arrival
    /// is on top (technical design §5.3.5). The queue lives here so concurrent
    /// approvals never clobber each other's continuation.
    private struct PendingDecision: Identifiable {
        let envelope: BridgeEnvelope
        let continuation: CheckedContinuation<BridgeResponse, Never>
        var id: UUID { envelope.requestId }
    }
    private var decisions = BubbleQueue<PendingDecision>()
    private var frontDecisionRenderer: (() -> SessionDashboardCard?)?
    private var frontDashboardCard: SessionDashboardCard?
    private var activeNotificationSessionID: String?
    private var activeNotificationSource: SourceInfo?
    private(set) var sessionStateSnapshot = SessionState()

    /// Notifications that arrived while a decision was active (decide > notify):
    /// they accumulate as a badge instead of clobbering the approval card.
    private var notificationBadge = 0

    init(
        surface: PetSurface,
        greetDuration: TimeInterval = PetAnimations.greetDuration,
        decisionTimeoutProvider: @escaping @Sendable (ToolKind) -> TimeInterval = {
            HookDecisionBudget.appDecisionTimeout(for: $0)
        },
        openDashboard: @escaping () -> Void = {},
        terminalJump: @escaping (JumpTarget) -> Void = { target in
            try? TerminalJumpService().jump(to: target)
        }
    ) {
        self.surface = surface
        self.greetDuration = greetDuration
        self.decisionTimeoutProvider = decisionTimeoutProvider
        self.openDashboard = openDashboard
        self.terminalJump = terminalJump
    }

    /// Updates the active pet sprite and re-renders the current state.
    func setActiveAsset(_ asset: PetAsset?) {
        activeAsset = asset
        render()
    }

    /// Plays the greeting (startup / daily first run) via the state machine, then
    /// schedules a return to idle so `.greet` is transient instead of sticking — the
    /// greeting has no bubble to dismiss, so nothing else would move it back.
    @discardableResult
    func greet() -> Bool {
        guard decisions.isEmpty, machine.state != .decide, machine.state != .notify else {
            return false
        }

        machine.greet()
        render()

        greetEndTask?.cancel()
        let nanos = UInt64(greetDuration * 1_000_000_000)
        greetEndTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            self?.greetingFinished()
        }
        return true
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
        guard !selectedDashboardMatches(source: envelope.source) else {
            dismissNotificationBubbleIfActive(matching: envelope.source)
            return
        }
        guard machine.receive(envelope.content) else {
            return
        }

        guard let petFrame = surface.petFrame else {
            // Pet hidden / no window -> nothing to anchor to; drop back to idle.
            activeNotificationSessionID = nil
            activeNotificationSource = nil
            machine.bubbleDismissed()
            render()
            return
        }

        activeNotificationSessionID = envelope.source.sessionID
        activeNotificationSource = envelope.source
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
            onJump: terminalJump,
            onDismiss: { [weak self] in self?.handleBubbleDismissed() }
        )
    }

    @discardableResult
    func sync(
        with sessionState: SessionState,
        activityOverride: SessionPetActivity? = nil
    ) -> Bool {
        sessionStateSnapshot = sessionState
        switch activityOverride ?? sessionState.derivedPetActivity {
        case .deciding:
            machine.beginDecision()
        case .greeting:
            return greet()
        case .idle:
            if decisions.isEmpty, machine.state != .notify {
                machine.bubbleDismissed()
            }
        }
        surface.renderPet(asset: activeAsset, activity: activity(for: sessionState.petVisualState))
        return false
    }

}

extension PetController {
    /// Presents an approval bubble and suspends until the user decides. Called off the main actor by `BridgeServerHost`
    /// for response-bearing envelopes; the returned `BridgeResponse` is paired back
    /// to the request by `requestId` upstream. Concurrent calls are queued FIFO so
    /// they never clobber each other's continuation.
    func requestDecision(for envelope: BridgeEnvelope) async -> BridgeResponse {
        guard envelope.content.needsResponse else {
            // Only response-bearing content (`approval` / `question`) is interactive.
            return .defer
        }

        guard !decisions.contains(id: envelope.requestId) else {
            return .defer
        }

        return await withCheckedContinuation { continuation in
            decisions.enqueue(
                PendingDecision(envelope: envelope, continuation: continuation)
            )
            scheduleDecisionTimeout(for: envelope)
            if decisions.count == 1 {
                presentFrontDecision()
            } else {
                surface.updatePendingCount(decisions.pendingCount)
                surface.updateDashboardContent()
            }
        }
    }

    /// Fails open one request without disturbing a different FIFO front. Used by
    /// peer disconnect and app shutdown as well as the per-tool decision deadline.
    func cancelDecision(requestId: UUID) {
        let wasFront = decisions.front?.id == requestId
        guard let pending = decisions.remove(id: requestId) else { return }
        decisionTimeoutTasks.removeValue(forKey: requestId)?.cancel()
        pending.continuation.resume(returning: .defer)

        if wasFront {
            frontDecisionRenderer = nil
            frontDashboardCard = nil
            surface.dismissApproval()
            presentFrontDecision()
        } else {
            surface.updatePendingCount(decisions.pendingCount)
            surface.updateDashboardContent()
        }
    }

    func cancelAllDecisions() {
        failOpenAllDecisions()
    }

    private func scheduleDecisionTimeout(for envelope: BridgeEnvelope) {
        let requestId = envelope.requestId
        let configuredTimeout = decisionTimeoutProvider(envelope.source.tool)
        let timeout = configuredTimeout.isFinite ? max(0, configuredTimeout) : 0
        let maximumSeconds = TimeInterval(UInt64.max) / 1_000_000_000
        let nanoseconds = UInt64(min(timeout, maximumSeconds) * 1_000_000_000)
        decisionTimeoutTasks[requestId]?.cancel()
        decisionTimeoutTasks[requestId] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.cancelDecision(requestId: requestId)
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
            frontDecisionRenderer = nil
            machine.bubbleDismissed()
            surface.dismissApproval()
            notificationBadge = 0
            surface.updateNotificationBadge(0)
            surface.updateDashboardContent()
            render()
            return
        }
        if frontDashboardCard?.id != front.id.uuidString {
            frontDashboardCard = nil
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
        let onDecision: (BridgeResponse) -> Void = { [weak self] response in
            self?.resolveDecision(requestId: front.id, with: response)
        }

        switch front.envelope.content {
        case let .approval(approval):
            presentApprovalDecision(approval, front: front, placement: placement, onDecision: onDecision)
        case let .question(question):
            presentQuestionDecision(question, front: front, placement: placement, onDecision: onDecision)
        case .completion, .status:
            // Non-interactive content never enters the decision queue (guarded by
            // `requestDecision`); fail open defensively if it ever does.
            resolveDecision(requestId: front.id, with: .defer)
        }
        surface.updateDashboardContent()
    }

    private func presentApprovalDecision(
        _ approval: ApprovalContent,
        front: PendingDecision,
        placement: BubbleAnchor.Placement,
        onDecision: @escaping (BridgeResponse) -> Void
    ) {
        frontDecisionRenderer = { [weak self, terminalJump] in
            if let cached = self?.frontDashboardCard { return cached }
            let presentation = ApprovalPresentation(pendingCount: self?.decisions.pendingCount ?? 0)
            let card = SessionDashboardCard(
                id: front.id.uuidString,
                view: AnyView(ApprovalCard(
                    content: approval,
                    source: front.envelope.source,
                    tailEdge: .bottom,
                    tailOffsetX: 40,
                    presentation: presentation,
                    onJump: terminalJump,
                    onDecision: onDecision
                )),
                resolve: onDecision
            )
            self?.frontDashboardCard = card
            return card
        }
        guard !selectedDashboardMatches(source: front.envelope.source) else {
            surface.dismissApproval()
            return
        }
        surface.presentApproval(
            content: approval,
            source: front.envelope.source,
            placement: placement,
            pendingCount: decisions.pendingCount,
            onJump: terminalJump,
            onDecision: onDecision
        )
    }

    private func presentQuestionDecision(
        _ question: QuestionContent,
        front: PendingDecision,
        placement: BubbleAnchor.Placement,
        onDecision: @escaping (BridgeResponse) -> Void
    ) {
        let conversationContext = questionConversationContext(for: front.envelope.source)
        frontDecisionRenderer = { [weak self, terminalJump] in
            if let cached = self?.frontDashboardCard { return cached }
            let presentation = ApprovalPresentation(pendingCount: self?.decisions.pendingCount ?? 0)
            let card = SessionDashboardCard(
                id: front.id.uuidString,
                view: AnyView(QuestionCard(
                    content: question,
                    source: front.envelope.source,
                    conversationContext: conversationContext,
                    tailEdge: .bottom,
                    tailOffsetX: 40,
                    presentation: presentation,
                    onJump: terminalJump,
                    onAnswer: onDecision
                )),
                resolve: onDecision
            )
            self?.frontDashboardCard = card
            return card
        }
        guard !selectedDashboardMatches(source: front.envelope.source) else {
            surface.dismissApproval()
            return
        }
        surface.presentQuestion(
            content: question,
            source: front.envelope.source,
            conversationContext: conversationContext,
            placement: placement,
            pendingCount: decisions.pendingCount,
            onJump: terminalJump,
            onAnswer: onDecision
        )
    }

    /// Resolves the front decision iff `requestId` still matches it, so a duplicate
    /// callback or a stale timeout can never resume a continuation twice or resolve
    /// the wrong request (single-resume guard, technical design D2).
    private func resolveDecision(requestId: UUID, with response: BridgeResponse) {
        guard let front = decisions.removeFront(id: requestId) else {
            return
        }
        decisionTimeoutTasks.removeValue(forKey: requestId)?.cancel()
        front.continuation.resume(returning: response)
        frontDecisionRenderer = nil
        frontDashboardCard = nil
        surface.updateDashboardContent()
        presentFrontDecision()
    }

    private func failOpenAllDecisions() {
        let pending = decisions.drain()
        let timeoutTasks = Array(decisionTimeoutTasks.values)
        decisionTimeoutTasks.removeAll()
        timeoutTasks.forEach { $0.cancel() }
        frontDecisionRenderer = nil
        frontDashboardCard = nil
        notificationBadge = 0
        surface.updateNotificationBadge(0)
        surface.updateDashboardContent()
        for item in pending {
            item.continuation.resume(returning: .defer)
        }
        machine.bubbleDismissed()
        surface.dismissApproval()
        render()
    }

    private func questionConversationContext(for source: SourceInfo) -> QuestionConversationContext? {
        QuestionConversationContext(session: sessionStateSnapshot.sessionsByID[source.sessionID])
    }

    private func greetingFinished() {
        machine.greetFinished()
        render()
    }

    private func handleBubbleDismissed() {
        activeNotificationSessionID = nil
        activeNotificationSource = nil
        machine.bubbleDismissed()
        surface.dismissBubble()
        render()
    }

    private func dismissNotificationBubbleIfActive() {
        guard activeNotificationSessionID != nil else {
            return
        }
        activeNotificationSessionID = nil
        activeNotificationSource = nil
        machine.bubbleDismissed()
        surface.dismissBubble()
        render()
    }

    private func dismissNotificationBubbleIfActive(matching source: SourceInfo) {
        guard activeNotificationSessionID == source.sessionID else {
            return
        }
        activeNotificationSessionID = nil
        activeNotificationSource = nil
        machine.bubbleDismissed()
        surface.dismissBubble()
        render()
    }

    private func dismissNotificationBubbleIfActive(matching selection: DashboardSessionSelection) {
        guard let source = activeNotificationSource, selection.matches(source) else {
            return
        }
        activeNotificationSessionID = nil
        activeNotificationSource = nil
        machine.bubbleDismissed()
        surface.dismissBubble()
        render()
    }

    private func selectedDashboardMatches(source: SourceInfo) -> Bool {
        DashboardSessionSelection(
            sessionID: surface.selectedDashboardSessionID,
            jumpTarget: surface.selectedDashboardJumpTarget
        ).matches(source)
    }

    private struct DashboardSessionSelection {
        let sessionID: String?
        let jumpTarget: JumpTarget?

        func matches(_ source: SourceInfo) -> Bool {
            guard let sessionID else { return false }
            if sessionID == source.sessionID { return true }
            guard isDiscoveredSessionID(sessionID, for: source.tool) else { return false }
            return jumpTargetMatches(source: source)
        }

        private func jumpTargetMatches(source: SourceInfo) -> Bool {
            guard let jumpTarget else { return false }
            if let selectedTTY = normalizedNonEmpty(jumpTarget.terminalTTY),
               let sourceTTY = normalizedNonEmpty(source.jumpTarget?.terminalTTY),
               selectedTTY == sourceTTY {
                return true
            }
            if let selectedSession = normalizedNonEmpty(jumpTarget.terminalSessionID),
               let sourceSession = normalizedNonEmpty(source.jumpTarget?.terminalSessionID),
               selectedSession == sourceSession {
                return true
            }
            guard let selectedCWD = normalizedNonEmpty(jumpTarget.workingDirectory),
                  let sourceCWD = normalizedNonEmpty(source.jumpTarget?.workingDirectory ?? source.cwd) else {
                return false
            }
            return selectedCWD == sourceCWD
        }

        private func isDiscoveredSessionID(_ sessionID: String, for tool: ToolKind) -> Bool {
            sessionID.hasPrefix("discovered-\(tool.rawValue)-")
        }

        private func normalizedNonEmpty(_ value: String?) -> String? {
            guard let value else { return nil }
            let normalized = value.replacingOccurrences(of: "/dev/", with: "")
            return normalized.isEmpty ? nil : normalized
        }
    }

    private func render() {
        surface.renderPet(asset: activeAsset, activity: activity(for: machine.state))
    }

    private func activity(for state: PetStateMachine.State) -> PetActivity {
        switch state {
        case .greet:
            return .waving
        case .decide:
            // Highlight the pet for attention while an approval awaits a decision.
            return .waiting
        case .idle, .notify:
            // notify keeps the resting sprite; the bubble carries the notification.
            return .idle
        }
    }

    private func activity(for state: PetVisualState) -> PetActivity {
        switch state {
        case .idle: .idle
        case .running: .running
        case .waiting: .waiting
        case .waving: .waving
        case .failed: .failed
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

    func dashboardCard(for sessionID: String) -> SessionDashboardCard? {
        guard let source = decisions.front?.envelope.source else {
            return nil
        }
        let selection = DashboardSessionSelection(
            sessionID: sessionID,
            jumpTarget: surface.selectedDashboardSessionID == sessionID ? surface.selectedDashboardJumpTarget : nil
        )
        guard selection.matches(source) else {
            return nil
        }
        return frontDecisionRenderer?()
    }

    func dashboardSelectionChanged(sessionID: String?, jumpTarget: JumpTarget? = nil) {
        surface.selectedDashboardSessionID = sessionID
        surface.selectedDashboardJumpTarget = sessionID == nil ? nil : jumpTarget
        if sessionID != nil {
            dismissNotificationBubbleIfActive()
        }
        presentFrontDecision()
    }

    func openDashboardFromPetClick() {
        openDashboard()
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
    var selectedDashboardSessionID: String? { get set }
    var selectedDashboardJumpTarget: JumpTarget? { get set }
    func renderPet(asset: PetAsset?, activity: PetActivity)
    func showPetSwitchTooltip(name: String)
    func updateDashboardContent()
    func presentBubble(
        content: BubbleContent,
        source: SourceInfo,
        placement: BubbleAnchor.Placement,
        onJump: @escaping (JumpTarget) -> Void,
        onDismiss: @escaping () -> Void
    )
    func dismissBubble()
    /// Presents an interactive approval card. `onDecision` is invoked exactly once
    /// with the user's choice or dismissal fallback.
    func presentApproval(
        content: ApprovalContent,
        source: SourceInfo,
        placement: BubbleAnchor.Placement,
        pendingCount: Int,
        onJump: @escaping (JumpTarget) -> Void,
        onDecision: @escaping (BridgeResponse) -> Void
    )
    /// Presents an interactive structured-question card. `onAnswer` is invoked
    /// exactly once with `.question(QuestionAnswer)` on submit, or `.defer` from dismissal.
    func presentQuestion(
        content: QuestionContent,
        source: SourceInfo,
        conversationContext: QuestionConversationContext?,
        placement: BubbleAnchor.Placement,
        pendingCount: Int,
        onJump: @escaping (JumpTarget) -> Void,
        onAnswer: @escaping (BridgeResponse) -> Void
    )
    /// Updates the "还有 N 个待处理" badge while the front card stays presented.
    func updatePendingCount(_ count: Int)
    func dismissApproval()
    /// Updates the small badge counting notifications deferred while deciding.
    func updateNotificationBadge(_ count: Int)
}

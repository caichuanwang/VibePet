import AppKit
import SwiftUI
import VibePetCore

/// The single entry point for pet behavior (technical design §5.2). It owns the
/// `PetStateMachine` and maps `idle / greet / notify` to what the pet surface
/// renders and to the notification bubble lifecycle. Both the startup greeting
/// and bridge-driven notifications flow through here, so there is one source of
/// truth for pet state. The `decide` interaction lands in M4.
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

    init(surface: PetSurface, greetDuration: TimeInterval = PetAnimations.greetDuration) {
        self.surface = surface
        self.greetDuration = greetDuration
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

    /// Routes an incoming bridge envelope. Notification content surfaces a bubble;
    /// response-bearing content (`approval` / `question`) is ignored this milestone.
    func handle(_ envelope: BridgeEnvelope) {
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

    /// State the pet should currently display, for the surface to map to a sprite
    /// activity. Exposed for tests.
    var state: PetStateMachine.State {
        machine.state
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
        case .approval, .question:
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
}

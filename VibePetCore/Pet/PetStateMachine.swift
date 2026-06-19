/// Pure state machine behind the desktop pet (technical design §5.2). Covers
/// `idle` / `greet` / `notify` plus the `decide` state for response-bearing
/// `approval` content (M4; `question` joins in M5). Kept UI-independent in
/// `VibePetCore` so the transitions are unit testable.
public struct PetStateMachine: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case greet
        case notify
        case decide
    }

    public private(set) var state: State

    public init(state: State = .idle) {
        self.state = state
    }

    /// Plays the greeting (startup / daily first run).
    public mutating func greet() {
        state = .greet
    }

    /// Called when the greeting animation completes, returning the pet to its
    /// idle resting state. Greeting is transient: unlike a notification it has no
    /// bubble to dismiss, so the controller schedules this after `greetDuration`.
    /// No-op if the state already moved on (e.g. a notification arrived mid-greet).
    public mutating func greetFinished() {
        if state == .greet {
            state = .idle
        }
    }

    /// Routes incoming bubble content into a non-interactive `notify` bubble.
    /// Returns `true` when accepted; response-bearing content (`approval` /
    /// `question`) is NOT a notification and is routed via `beginDecision()`
    /// instead, leaving the state unchanged here.
    @discardableResult
    public mutating func receive(_ content: BubbleContent) -> Bool {
        guard !content.needsResponse else {
            return false
        }
        state = .notify
        return true
    }

    /// Enters the interactive `decide` state for response-bearing `approval`
    /// content. The pet highlights for attention while the approval bubble awaits
    /// a user decision.
    public mutating func beginDecision() {
        state = .decide
    }

    /// Called when the active greeting / notify / decide bubble dismisses,
    /// returning the pet to its idle resting state.
    public mutating func bubbleDismissed() {
        switch state {
        case .greet, .notify, .decide:
            state = .idle
        case .idle:
            break
        }
    }
}

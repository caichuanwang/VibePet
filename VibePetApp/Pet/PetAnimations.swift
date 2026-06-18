import SwiftUI

/// What the pet is currently doing. M2 only models the `idle`/`greet` subset of
/// the full PetController state machine (technical design §5.2); `notify`/`decide`
/// arrive with the bubble work in M3/M4.
enum PetActivity: Equatable, Sendable {
    case idle
    case greeting
}

/// Centralised animation tuning so motion stays consistent and easy to retheme.
/// Standby motion is AI-free Core Animation on the single sprite (technical
/// design §2.1 末): squash/stretch breathing + a slight sway.
enum PetAnimations {
    // Breathing (squash/stretch).
    static let breathingScale: CGSize = CGSize(width: 1.04, height: 0.97)
    static let breathingDuration: Double = 2.2

    // Sway (slight rotation).
    static let swayAngle: Angle = .degrees(2.2)
    static let swayDuration: Double = 3.1

    // Blink overlay cadence.
    static let blinkInterval: Double = 4.0
    static let blinkDuration: Double = 0.12

    // Greeting bounce.
    static let greetLift: CGFloat = -10
    static let greetDuration: Double = 0.45

    // Reduce Motion fallback.
    static let fadeDuration: Double = 0.35

    /// Repeating idle animation, or a plain fade when Reduce Motion is on.
    static func idleBreathing(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeInOut(duration: fadeDuration)
            : .easeInOut(duration: breathingDuration).repeatForever(autoreverses: true)
    }

    static func idleSway(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeInOut(duration: fadeDuration)
            : .easeInOut(duration: swayDuration).repeatForever(autoreverses: true)
    }

    static func greeting(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeInOut(duration: fadeDuration)
            : .interpolatingSpring(stiffness: 220, damping: 9)
    }
}

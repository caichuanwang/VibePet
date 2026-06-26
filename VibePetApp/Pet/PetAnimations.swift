import Foundation
import SwiftUI
import VibePetCore

enum PetActivity: Equatable, Sendable {
    case idle
    case running
    case waiting
    case waving
    case failed

    var visualState: PetVisualState {
        switch self {
        case .idle: .idle
        case .running: .running
        case .waiting: .waiting
        case .waving: .waving
        case .failed: .failed
        }
    }

    var statusIndicatorColor: Color {
        switch self {
        case .running:
            Color(nsColor: .systemGreen)
        case .waiting:
            Color(nsColor: .systemOrange)
        case .failed:
            Color(nsColor: .systemRed)
        case .idle, .waving:
            Color.white.opacity(0.42)
        }
    }
}

enum PetAnimations {
    static let greetDuration: Double = 0.56
}

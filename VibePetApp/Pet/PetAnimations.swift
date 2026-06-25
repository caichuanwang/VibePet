import Foundation
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
}

enum PetAnimations {
    static let greetDuration: Double = 0.56
}

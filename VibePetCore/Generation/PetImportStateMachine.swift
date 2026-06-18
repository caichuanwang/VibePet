import CoreGraphics
import Foundation

public struct PetImportStateMachine {
    public enum Phase: Equatable, Sendable {
        case idle
        case generating
        case result
        case placed
        case error
    }

    public private(set) var phase: Phase
    public private(set) var history: [Phase]
    public private(set) var sourceName: String?
    public private(set) var progress: Double
    public private(set) var generatedAsset: PetAsset?
    public private(set) var generatedSprite: CGImage?
    public private(set) var suggestedName: String
    public private(set) var placedAssetID: UUID?
    public private(set) var errorMessage: String?

    public init() {
        phase = .idle
        history = [.idle]
        sourceName = nil
        progress = 0
        generatedAsset = nil
        generatedSprite = nil
        suggestedName = ""
        placedAssetID = nil
        errorMessage = nil
    }

    public mutating func startGeneration(sourceName: String) {
        self.sourceName = sourceName
        progress = 0
        generatedAsset = nil
        generatedSprite = nil
        suggestedName = defaultSuggestedName(from: sourceName)
        placedAssetID = nil
        errorMessage = nil
        transition(to: .generating)
    }

    public mutating func updateProgress(_ value: Double) {
        progress = min(max(value, 0), 1)
    }

    public mutating func finishGeneration(asset: PetAsset, sprite: CGImage, suggestedName: String) {
        generatedAsset = asset
        generatedSprite = sprite
        self.suggestedName = suggestedName
        progress = 1
        errorMessage = nil
        transition(to: .result)
    }

    public mutating func failGeneration(_ error: Error) {
        generatedAsset = nil
        generatedSprite = nil
        progress = 0
        errorMessage = Self.readableMessage(for: error)
        transition(to: .error)
    }

    public mutating func retry() {
        progress = 0
        generatedAsset = nil
        generatedSprite = nil
        errorMessage = nil
        transition(to: .generating)
    }

    public mutating func reset() {
        progress = 0
        generatedAsset = nil
        generatedSprite = nil
        suggestedName = ""
        placedAssetID = nil
        errorMessage = nil
        transition(to: .idle)
    }

    public mutating func place(assetID: UUID) {
        placedAssetID = assetID
        transition(to: .placed)
    }

    public static func readableMessage(for error: Error) -> String {
        guard let genError = error as? GenError else {
            return error.localizedDescription
        }

        switch genError {
        case .noSubject:
            return "No subject was found in that photo."
        case .encodingFailed:
            return "The generated sprite could not be encoded."
        case .writeFailed(let message):
            return "The generated pet could not be saved: \(message)"
        case .defaultGeneratorUnavailable(let identifier):
            return "The generator '\(identifier)' is unavailable."
        }
    }

    private mutating func transition(to nextPhase: Phase) {
        phase = nextPhase
        history.append(nextPhase)
    }

    private func defaultSuggestedName(from sourceName: String) -> String {
        URL(fileURLWithPath: sourceName).deletingPathExtension().lastPathComponent
    }
}

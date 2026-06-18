import CoreGraphics
import Foundation
import SwiftUI
import VibePetCore

/// Drives the import → generate panel. The phase logic lives in `VibePetCore`'s
/// unit-tested `PetImportStateMachine`; this view model only adapts it to SwiftUI
/// and wires it to `GenerationService` / `PetAssetStore` / `ConfigStore`.
///
/// "Failure leaves no half-finished asset" is guaranteed upstream: the generator
/// writes the sprite only after a successful cutout and throws before any write
/// on `.noSubject`, so the panel never has to clean up partial assets.
@MainActor
final class PetImportViewModel: ObservableObject {
    @Published private(set) var phase: PetImportStateMachine.Phase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var previewSprite: CGImage?
    @Published var name: String = ""

    /// Called once the pet is placed (active) so the host can show it on the desktop.
    var onPlaced: ((PetAsset) -> Void)?

    private var machine = PetImportStateMachine()
    private var lastSourceImage: CGImage?
    private let generation: GenerationService
    private let configStore: ConfigStore
    private let store: PetAssetStore

    init(
        generation: GenerationService = GenerationService(),
        configStore: ConfigStore = ConfigStore(),
        store: PetAssetStore = PetAssetStore()
    ) {
        self.generation = generation
        self.configStore = configStore
        self.store = store
    }

    // MARK: - Import

    func importImage(at url: URL) {
        let sourceName = url.lastPathComponent
        machine.startGeneration(sourceName: sourceName)
        guard let image = ImageLoading.cgImage(at: url) else {
            machine.failGeneration(PetImportError.unreadableImage)
            sync()
            return
        }
        lastSourceImage = image
        sync()
        Task { await runGeneration(image: image) }
    }

    func retry() {
        guard let image = lastSourceImage else {
            reset()
            return
        }
        machine.retry()
        sync()
        Task { await runGeneration(image: image) }
    }

    func reset() {
        machine.reset()
        previewSprite = nil
        name = ""
        sync()
    }

    // MARK: - Placement

    func place() {
        guard let asset = machine.generatedAsset, let sprite = machine.generatedSprite else {
            return
        }
        let finalAsset = persistNameIfNeeded(asset, sprite: sprite)
        activate(finalAsset)
        machine.place(assetID: finalAsset.id)
        sync()
        onPlaced?(finalAsset)
    }

    // MARK: - Generation

    private func runGeneration(image: CGImage) async {
        do {
            let asset = try await generation.generate(from: image) { [weak self] value in
                Task { @MainActor in
                    self?.machine.updateProgress(value)
                    self?.progress = value
                }
            }
            guard let sprite = ImageLoading.cgImage(at: asset.primaryImageURL) else {
                machine.failGeneration(GenError.encodingFailed)
                sync()
                return
            }
            machine.finishGeneration(asset: asset, sprite: sprite, suggestedName: machine.suggestedName)
            previewSprite = sprite
            name = machine.suggestedName
            sync()
        } catch {
            machine.failGeneration(error)
            sync()
        }
    }

    private func persistNameIfNeeded(_ asset: PetAsset, sprite: CGImage) -> PetAsset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != asset.metadata["name"] else {
            return asset
        }
        var metadata = asset.metadata
        metadata["name"] = trimmed
        let named = PetAsset(
            id: asset.id,
            kind: asset.kind,
            primaryImageURL: asset.primaryImageURL,
            layers: asset.layers,
            boundingInset: asset.boundingInset,
            metadata: metadata
        )
        return (try? store.write(named, sprite: sprite)) ?? asset
    }

    private func activate(_ asset: PetAsset) {
        do {
            let current = try configStore.read()
            try configStore.write(current.with(activePetID: asset.id.uuidString))
        } catch {
            NSLog("VibePet failed to set active pet: \(error)")
        }
    }

    private func sync() {
        phase = machine.phase
        progress = machine.progress
        errorMessage = machine.errorMessage
    }
}

enum PetImportError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "That file could not be read as an image. Try a JPG, PNG, or HEIC."
        }
    }
}

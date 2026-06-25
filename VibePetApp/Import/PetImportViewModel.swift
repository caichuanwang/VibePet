import AppKit
import Foundation
import SwiftUI
import VibePetCore

@MainActor
final class PetImportViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case importing
        case imported(PetAsset)
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var selectedAsset: PetAsset?

    var onPlaced: ((PetAsset) -> Void)?

    private let importer: PetPackageImporter
    private let configStore: ConfigStore

    init(
        importer: PetPackageImporter = PetPackageImporter(),
        configStore: ConfigStore = ConfigStore()
    ) {
        self.importer = importer
        self.configStore = configStore
    }

    func choosePackage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageLoading.acceptedPackageContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        importPackage(from: url)
    }

    func importPackage(from url: URL) {
        phase = .importing
        do {
            let asset = try importer.importPackage(from: url)
            try activate(asset)
            selectedAsset = asset
            phase = .imported(asset)
            onPlaced?(asset)
        } catch let error as PetAssetError {
            phase = .error(ErrorPresenter.present(petAssetError: error).message)
        } catch {
            phase = .error(ErrorPresenter.present(petAssetError: .invalidPackage(error.localizedDescription)).message)
        }
    }

    func reset() {
        phase = .idle
    }

    private func activate(_ asset: PetAsset) throws {
        let current = try configStore.read()
        try configStore.write(current.with(activePetID: asset.slug))
    }
}

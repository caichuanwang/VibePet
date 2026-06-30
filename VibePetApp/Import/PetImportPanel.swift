import SwiftUI
import UniformTypeIdentifiers
import VibePetCore

struct PetImportPanel: View {
    @ObservedObject var viewModel: PetImportViewModel
    var localizer: AppLocalizer = AppLocalizer(language: .simplifiedChinese)

    var body: some View {
        VStack(spacing: 16) {
            switch viewModel.phase {
            case .idle:
                idleView
            case .importing:
                ProgressView(localizer.text(.importInProgress))
                    .controlSize(.large)
            case let .imported(asset):
                importedView(asset)
            case let .error(message):
                errorView(message)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onDrop(of: [UTType.zip.identifier, UTType.folder.identifier, UTType.fileURL.identifier], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                Task { @MainActor in
                    viewModel.importPackage(from: url)
                }
            }
            return true
        }
    }

    private var idleView: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            Text(localizer.text(.importTitle)).font(.headline)
            Text(localizer.text(.importDescription))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(localizer.text(.choosePetFile)) {
                viewModel.choosePackage()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
    }

    private func importedView(_ asset: PetAsset) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            Text(asset.displayName).font(.headline)
            Text(localizer.text(.importSetCurrentPet))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(localizer.text(.importAnother)) {
                viewModel.reset()
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text(localizer.text(.importFailureTitle)).font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(localizer.text(.chooseAnotherFile)) {
                viewModel.choosePackage()
            }
        }
    }
}

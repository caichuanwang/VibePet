import SwiftUI
import UniformTypeIdentifiers
import VibePetCore

struct PetImportPanel: View {
    @ObservedObject var viewModel: PetImportViewModel

    var body: some View {
        VStack(spacing: 16) {
            switch viewModel.phase {
            case .idle:
                idleView
            case .importing:
                ProgressView("正在导入宠物…")
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
            Text("导入 Codex 宠物").font(.headline)
            Text("拖入包含 pet.json 和 spritesheet 的 zip 或文件夹。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("选择宠物…") {
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
            Text("已设为当前宠物。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("再导入一个") {
                viewModel.reset()
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("无法导入").font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("换一个文件…") {
                viewModel.choosePackage()
            }
        }
    }
}

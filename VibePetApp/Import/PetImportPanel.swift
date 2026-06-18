import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VibePetCore

/// Single compact "photo → pet" panel that transforms in place across the
/// `idle → generating → result → placed` (or `error`) states (technical design §5.5).
/// Importing a file auto-starts cutout — there is no separate generate button.
struct PetImportPanel: View {
    @ObservedObject var viewModel: PetImportViewModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            switch viewModel.phase {
            case .idle:
                idleView
            case .generating:
                generatingView
            case .result:
                resultView
            case .placed:
                placedView
            case .error:
                errorView
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    // MARK: - States

    private var idleView: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.6))
                .frame(height: 150)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 34))
                        Text("拖入照片，或")
                        Button("选择文件…") { presentOpenPanel() }
                    }
                    .foregroundStyle(.secondary)
                }
                .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                    handleDrop(providers)
                }
            Text("支持 JPG / PNG / HEIC，导入后自动抠图")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var generatingView: some View {
        VStack(spacing: 14) {
            Text("正在抠图…").font(.headline)
            ProgressView(value: viewModel.progress)
                .progressViewStyle(.linear)
            Text("\(Int(viewModel.progress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(height: 150)
    }

    private var resultView: some View {
        VStack(spacing: 14) {
            spritePreview
                .frame(height: 150)
            TextField("给宠物起个名字（可留空）", text: $viewModel.name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("换一张") { viewModel.reset() }
                Spacer()
                Button("放上桌面") { viewModel.place() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var placedView: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.green)
            Text("宠物已上桌～").font(.headline)
        }
        .frame(height: 150)
    }

    private var errorView: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text(viewModel.errorMessage ?? "出了点问题")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack {
                Button("换一张") { viewModel.reset() }
                Spacer()
                Button("重试") { viewModel.retry() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Preview

    private var spritePreview: some View {
        ZStack {
            CheckerboardBackground()
            if let sprite = viewModel.previewSprite {
                Image(decorative: sprite, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Input

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageLoading.acceptedContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.importImage(at: url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in viewModel.importImage(at: url) }
        }
        return true
    }
}

/// Transparency-revealing checkerboard behind the sprite preview.
private struct CheckerboardBackground: View {
    var square: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            let columns = Int(ceil(size.width / square))
            let rows = Int(ceil(size.height / square))
            for row in 0..<max(rows, 1) {
                for column in 0..<max(columns, 1) where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(
                        x: CGFloat(column) * square,
                        y: CGFloat(row) * square,
                        width: square,
                        height: square
                    )
                    context.fill(Path(rect), with: .color(.gray.opacity(0.22)))
                }
            }
        }
        .background(Color(white: 0.95))
    }
}

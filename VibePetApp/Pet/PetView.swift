import SwiftUI
import VibePetCore

struct PetView: View {
    let asset: PetAsset?
    var activity: PetActivity = .idle
    var onFrameChanged: ((CGImage?) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grid: SpriteSheetGrid?

    var body: some View {
        Group {
            if let asset, let grid {
                SpriteSheetAnimator(
                    asset: asset,
                    grid: grid,
                    activity: activity,
                    reduceMotion: reduceMotion,
                    onFrameChanged: onFrameChanged
                )
            } else {
                PlaceholderPet()
                    .onAppear { onFrameChanged?(Self.emptyHitFrame) }
            }
        }
        .frame(width: Self.spriteSide, height: Self.spriteSide)
        .overlay(alignment: .bottomTrailing) {
            statusIndicator
                .padding(.trailing, 14)
                .padding(.bottom, 12)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .task(id: asset?.spritesheetURL) {
            loadSpritesheet()
        }
    }

    static let spriteSide: CGFloat = 120
    private static let indicatorSide: CGFloat = 10

    fileprivate static let emptyHitFrame: CGImage? = {
        var pixel: UInt8 = 0
        return withUnsafeMutableBytes(of: &pixel) { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 1,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return nil
            }
            return context.makeImage()
        }
    }()

    private var statusIndicator: some View {
        Circle()
            .fill(activity.statusIndicatorColor)
            .frame(width: Self.indicatorSide, height: Self.indicatorSide)
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 2, y: 1)
    }

    private func loadSpritesheet() {
        guard let asset, let image = ImageLoading.cgImage(at: asset.spritesheetURL) else {
            grid = nil
            onFrameChanged?(Self.emptyHitFrame)
            return
        }
        grid = try? SpriteSheetGrid(cgImage: image)
        if grid == nil {
            onFrameChanged?(Self.emptyHitFrame)
        }
    }
}

private struct SpriteSheetAnimator: View {
    let asset: PetAsset
    let grid: SpriteSheetGrid
    let activity: PetActivity
    let reduceMotion: Bool
    var onFrameChanged: ((CGImage?) -> Void)?

    @State private var frameIndex = 0

    private var state: PetVisualState {
        activity.visualState
    }

    private var spec: SpriteAnimationSpec {
        grid.playbackSpec(for: state, asset: asset) ?? SpriteAnimationSpec(row: 0, durationsMs: [280])
    }

    var body: some View {
        Group {
            if let frame = currentFrame {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .onAppear { onFrameChanged?(frame) }
                    .onChange(of: frameIndex) { _, _ in onFrameChanged?(currentFrame) }
            } else {
                PlaceholderPet()
                    .onAppear { onFrameChanged?(PetView.emptyHitFrame) }
            }
        }
        .task(id: animationTaskID) {
            await runAnimationLoop()
        }
    }

    private var animationTaskID: String {
        let durations = spec.durationsMs.map(String.init).joined(separator: ":")
        return "\(asset.slug)-\(state.rawValue)-\(reduceMotion)-\(durations)"
    }

    private var currentFrame: CGImage? {
        let column = reduceMotion ? 0 : frameIndex % max(1, spec.effectiveColumnCount)
        return grid.frame(row: spec.row, column: column)
    }

    private func runAnimationLoop() async {
        frameIndex = 0
        onFrameChanged?(currentFrame)
        guard !reduceMotion, !spec.durationsMs.isEmpty else {
            return
        }
        while !Task.isCancelled {
            let duration = spec.durationsMs[frameIndex % spec.durationsMs.count]
            try? await Task.sleep(nanoseconds: UInt64(duration) * 1_000_000)
            guard !Task.isCancelled else { return }
            frameIndex = (frameIndex + 1) % spec.durationsMs.count
        }
    }
}

private struct PlaceholderPet: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 36))
            Text("选择宠物")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
    }
}

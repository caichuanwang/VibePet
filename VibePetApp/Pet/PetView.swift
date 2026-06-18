import SwiftUI
import VibePetCore

/// The desktop pet itself: renders the active `PetAsset` sprite with transparency
/// preserved and plays the idle / greeting animations (technical design §2.1, §5.2).
struct PetView: View {
    let asset: PetAsset?
    var activity: PetActivity = .idle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sprite: CGImage?
    @State private var blinkLayer: CGImage?
    @State private var isBreathing = false
    @State private var isSwaying = false
    @State private var blinkOn = false
    @State private var isGreeting = false

    private let blinkTimer = Timer.publish(every: PetAnimations.blinkInterval, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let sprite {
                spriteBody(sprite)
            } else {
                PlaceholderPet()
            }
        }
        .frame(width: PetView.spriteSide, height: PetView.spriteSide)
        .onAppear {
            loadImages()
            startIdle()
            if activity == .greeting { playGreeting() }
        }
        .onChange(of: asset) { _, _ in loadImages() }
        .onChange(of: activity) { _, newValue in
            if newValue == .greeting { playGreeting() }
        }
        .onReceive(blinkTimer) { _ in pulseBlink() }
    }

    static let spriteSide: CGFloat = 120

    // MARK: - Body rendering

    private func spriteBody(_ image: CGImage) -> some View {
        ZStack {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)

            if let blinkLayer, blinkOn {
                Image(decorative: blinkLayer, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .scaleEffect(currentScale, anchor: .bottom)
        .rotationEffect(currentRotation, anchor: .bottom)
        .offset(y: isGreeting && !reduceMotion ? PetAnimations.greetLift : 0)
        .opacity(currentOpacity)
    }

    // MARK: - Animation state

    private var currentScale: CGSize {
        guard !reduceMotion, isBreathing else { return CGSize(width: 1, height: 1) }
        return PetAnimations.breathingScale
    }

    private var currentRotation: Angle {
        guard !reduceMotion, isSwaying else { return .zero }
        return PetAnimations.swayAngle
    }

    /// With Reduce Motion on we replace bouncing/spring with a gentle fade
    /// (technical design §5.3 通用): a slow opacity pulse stands in for "alive".
    private var currentOpacity: Double {
        guard reduceMotion else { return 1 }
        return isBreathing ? 0.85 : 1
    }

    private func startIdle() {
        withAnimation(PetAnimations.idleBreathing(reduceMotion: reduceMotion)) {
            isBreathing = true
        }
        withAnimation(PetAnimations.idleSway(reduceMotion: reduceMotion)) {
            isSwaying = true
        }
    }

    private func playGreeting() {
        withAnimation(PetAnimations.greeting(reduceMotion: reduceMotion)) {
            isGreeting = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + PetAnimations.greetDuration) {
            withAnimation(PetAnimations.greeting(reduceMotion: reduceMotion)) {
                isGreeting = false
            }
        }
    }

    private func pulseBlink() {
        // Only blink when the asset actually supplied a blink layer (technical
        // design §2.1 末); otherwise standby renders the base sprite untouched.
        guard blinkLayer != nil, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: PetAnimations.blinkDuration)) { blinkOn = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + PetAnimations.blinkDuration) {
            withAnimation(.easeInOut(duration: PetAnimations.blinkDuration)) { blinkOn = false }
        }
    }

    // MARK: - Image loading

    private func loadImages() {
        guard let asset else {
            sprite = nil
            blinkLayer = nil
            return
        }
        sprite = ImageLoading.cgImage(at: asset.primaryImageURL)
        if let blink = asset.layers.first(where: { $0.id == "blink" }) {
            blinkLayer = ImageLoading.cgImage(at: blink.imageURL)
        } else {
            blinkLayer = nil
        }
    }
}

/// Shown before any pet exists (e.g. during onboarding placeholder states).
private struct PlaceholderPet: View {
    var body: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.25))
            .overlay(Text("🐾").font(.system(size: 44)))
    }
}

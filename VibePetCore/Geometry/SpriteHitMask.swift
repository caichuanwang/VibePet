import CoreGraphics

/// Per-pixel hit region for a sprite, so the transparent parts of the pet window
/// can pass clicks through to whatever is beneath it (technical design §5.1).
///
/// Lives in `VibePetCore` (CoreGraphics only, no AppKit/SwiftUI) so the alpha
/// sampling and aspect-fit coordinate mapping stay unit-testable. The App's
/// hosting view feeds it points in view space and toggles `ignoresMouseEvents`.
public struct SpriteHitMask: Sendable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let sampleStep: Int
    private let samplesWide: Int
    private let samplesHigh: Int
    private let alpha: [UInt8]

    /// Builds the mask by rendering `cgImage` into an RGBA8 buffer and keeping the
    /// alpha channel. Returns nil for a degenerate (zero-size) image.
    public init?(cgImage: CGImage, sampleStep: Int = 1) {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let step = max(1, sampleStep)
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drew = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }

        let samplesWide = (width + step - 1) / step
        let samplesHigh = (height + step - 1) / step
        var sampledAlpha = [UInt8](repeating: 0, count: samplesWide * samplesHigh)
        for sampleY in 0..<samplesHigh {
            for sampleX in 0..<samplesWide {
                var maxAlpha: UInt8 = 0
                let xStart = sampleX * step
                let yStart = sampleY * step
                for y in yStart..<min(yStart + step, height) {
                    for x in xStart..<min(xStart + step, width) {
                        maxAlpha = max(maxAlpha, buffer[y * bytesPerRow + x * 4 + 3])
                    }
                }
                sampledAlpha[sampleY * samplesWide + sampleX] = maxAlpha
            }
        }

        self.pixelWidth = width
        self.pixelHeight = height
        self.sampleStep = step
        self.samplesWide = samplesWide
        self.samplesHigh = samplesHigh
        self.alpha = sampledAlpha
    }

    /// Whether the sprite is opaque at `point`, given the hosting view's `bounds`.
    ///
    /// The sprite is laid out aspect-fit and centred in `bounds` (matching the
    /// SwiftUI `PetView`). `point` is in AppKit view space (bottom-left origin);
    /// the alpha buffer is top-left origin, so the y axis is flipped.
    public func isOpaque(at point: CGPoint, in bounds: CGRect, threshold: UInt8 = 10) -> Bool {
        guard bounds.width > 0, bounds.height > 0 else { return false }

        let imageWidth = CGFloat(pixelWidth)
        let imageHeight = CGFloat(pixelHeight)
        let scale = min(bounds.width / imageWidth, bounds.height / imageHeight)
        let drawnWidth = imageWidth * scale
        let drawnHeight = imageHeight * scale
        let originX = bounds.minX + (bounds.width - drawnWidth) / 2
        let originY = bounds.minY + (bounds.height - drawnHeight) / 2

        guard point.x >= originX, point.x < originX + drawnWidth,
              point.y >= originY, point.y < originY + drawnHeight else {
            return false
        }

        let localX = (point.x - originX) / scale
        let localYFromBottom = (point.y - originY) / scale
        let pixelX = Int(localX)
        let pixelY = Int(imageHeight - localYFromBottom)
        guard pixelX >= 0, pixelX < pixelWidth, pixelY >= 0, pixelY < pixelHeight else {
            return false
        }

        let sampleX = min(samplesWide - 1, pixelX / sampleStep)
        let sampleY = min(samplesHigh - 1, pixelY / sampleStep)
        let index = sampleY * samplesWide + sampleX
        return alpha[index] > threshold
    }
}

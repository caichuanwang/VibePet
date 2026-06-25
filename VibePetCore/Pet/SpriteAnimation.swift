import CoreGraphics
import Foundation

public enum PetVisualState: String, Codable, Equatable, Sendable {
    case idle
    case running
    case waiting
    case waving
    case failed
}

public struct SpriteAnimationSpec: Codable, Equatable, Sendable {
    public let row: Int
    public let durationsMs: [Int]

    public var effectiveColumnCount: Int {
        durationsMs.count
    }

    public init(row: Int, durationsMs: [Int]) {
        self.row = row
        self.durationsMs = durationsMs
    }
}

public enum CodexAnimationRows {
    public static let columns = 8
    public static let rows = 9
    public static let cellWidth = 192
    public static let cellHeight = 208
    public static let atlasWidth = columns * cellWidth
    public static let atlasHeight = rows * cellHeight

    private static let builtInByState: [PetVisualState: SpriteAnimationSpec] = [
        .idle: SpriteAnimationSpec(row: 0, durationsMs: [280, 110, 110, 140, 140, 320]),
        .waving: SpriteAnimationSpec(row: 3, durationsMs: [140, 140, 140, 280]),
        .failed: SpriteAnimationSpec(row: 5, durationsMs: [140, 140, 140, 140, 140, 140, 140, 240]),
        .waiting: SpriteAnimationSpec(row: 6, durationsMs: [150, 150, 150, 150, 150, 260]),
        .running: SpriteAnimationSpec(row: 7, durationsMs: [120, 120, 120, 120, 120, 220])
    ]

    private static let usedColumnsByRow: [Int: Int] = [
        0: 6,
        1: 8,
        2: 8,
        3: 4,
        4: 5,
        5: 8,
        6: 6,
        7: 6,
        8: 6
    ]

    public static func spec(for state: PetVisualState, asset: PetAsset? = nil) -> SpriteAnimationSpec? {
        if let custom = asset?.customAnimations[state], !custom.durationsMs.isEmpty {
            return SpriteAnimationSpec(row: custom.row, durationsMs: Array(custom.durationsMs.prefix(columns)))
        }
        return builtInByState[state]
    }

    public static func usedColumnCount(forRow row: Int) -> Int? {
        usedColumnsByRow[row]
    }
}

public enum SpriteSheetGridError: Error, Equatable, Sendable {
    case invalidDimensions(width: Int, height: Int)
    case missingFrame(row: Int, column: Int)
}

public struct SpriteSheetGrid: Sendable {
    private let framesByIndex: [CGImage]

    public init(cgImage: CGImage) throws {
        guard cgImage.width == CodexAnimationRows.atlasWidth,
              cgImage.height == CodexAnimationRows.atlasHeight else {
            throw SpriteSheetGridError.invalidDimensions(width: cgImage.width, height: cgImage.height)
        }

        var frames: [CGImage] = []
        frames.reserveCapacity(CodexAnimationRows.rows * CodexAnimationRows.columns)
        for row in 0..<CodexAnimationRows.rows {
            for column in 0..<CodexAnimationRows.columns {
                let rect = CGRect(
                    x: column * CodexAnimationRows.cellWidth,
                    y: row * CodexAnimationRows.cellHeight,
                    width: CodexAnimationRows.cellWidth,
                    height: CodexAnimationRows.cellHeight
                )
                guard let frame = cgImage.cropping(to: rect) else {
                    throw SpriteSheetGridError.missingFrame(row: row, column: column)
                }
                frames.append(frame)
            }
        }
        framesByIndex = frames
    }

    public var frameCount: Int {
        framesByIndex.count
    }

    public func frame(row: Int, column: Int) -> CGImage? {
        guard row >= 0, row < CodexAnimationRows.rows,
              column >= 0, column < CodexAnimationRows.columns else {
            return nil
        }
        return framesByIndex[row * CodexAnimationRows.columns + column]
    }

    public func playbackSpec(for state: PetVisualState, asset: PetAsset? = nil) -> SpriteAnimationSpec? {
        guard let base = CodexAnimationRows.spec(for: state, asset: asset) else {
            return nil
        }
        let cappedDurations = Array(base.durationsMs.prefix(CodexAnimationRows.columns))
        guard !cappedDurations.isEmpty else {
            return nil
        }
        var playableCount = cappedDurations.count
        while playableCount > 1, isFrameTransparent(row: base.row, column: playableCount - 1) {
            playableCount -= 1
        }
        return SpriteAnimationSpec(row: base.row, durationsMs: Array(cappedDurations.prefix(playableCount)))
    }

    public func frames(for state: PetVisualState, asset: PetAsset? = nil) -> [CGImage] {
        guard let spec = playbackSpec(for: state, asset: asset) else {
            return []
        }
        return (0..<min(spec.effectiveColumnCount, CodexAnimationRows.columns)).compactMap { column in
            frame(row: spec.row, column: column)
        }
    }

    public func isFrameTransparent(row: Int, column: Int, threshold: UInt8 = 0) -> Bool {
        guard let frame = frame(row: row, column: column) else {
            return true
        }
        return SpriteAlpha.isTransparent(frame, threshold: threshold)
    }
}

enum SpriteAlpha {
    static func isTransparent(_ image: CGImage, threshold: UInt8) -> Bool {
        let bytesPerRow = image.width * 4
        var buffer = [UInt8](repeating: 0, count: image.height * bytesPerRow)
        let drew = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drew else { return true }
        for index in stride(from: 3, to: buffer.count, by: 4) where buffer[index] > threshold {
            return false
        }
        return true
    }
}

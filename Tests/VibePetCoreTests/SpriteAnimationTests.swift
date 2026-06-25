import CoreGraphics
@testable import VibePetCore
import XCTest

final class SpriteAnimationTests: XCTestCase {
    func testBuiltInRowsUseCodexAbsoluteRowsAndDurations() {
        XCTAssertEqual(CodexAnimationRows.spec(for: .idle)?.row, 0)
        XCTAssertEqual(CodexAnimationRows.spec(for: .waving)?.row, 3)
        XCTAssertEqual(CodexAnimationRows.spec(for: .failed)?.row, 5)
        XCTAssertEqual(CodexAnimationRows.spec(for: .waiting)?.row, 6)
        XCTAssertEqual(CodexAnimationRows.spec(for: .running)?.row, 7)

        XCTAssertEqual(CodexAnimationRows.spec(for: .idle)?.durationsMs, [280, 110, 110, 140, 140, 320])
        XCTAssertEqual(CodexAnimationRows.spec(for: .waving)?.durationsMs, [140, 140, 140, 280])
        XCTAssertEqual(CodexAnimationRows.spec(for: .failed)?.durationsMs, [140, 140, 140, 140, 140, 140, 140, 240])
        XCTAssertEqual(CodexAnimationRows.spec(for: .waiting)?.durationsMs, [150, 150, 150, 150, 150, 260])
        XCTAssertEqual(CodexAnimationRows.spec(for: .running)?.durationsMs, [120, 120, 120, 120, 120, 220])
    }

    func testSessionStateDerivesVisualStateWithAttentionPriority() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var state = SessionState()
        XCTAssertEqual(state.petVisualState, .idle)

        state.apply(.sessionStarted(sessionID: "running", timestamp: now, title: "Run", tool: .codex, summary: "Run", jumpTarget: nil))
        XCTAssertEqual(state.petVisualState, .running)

        state.apply(.sessionStarted(sessionID: "waiting", timestamp: now.addingTimeInterval(1), title: "Wait", tool: .claudeCode, summary: "Wait", jumpTarget: nil))
        state.apply(.permissionRequested(sessionID: "waiting", timestamp: now.addingTimeInterval(2), summary: "Approve"))
        XCTAssertEqual(state.petVisualState, .waiting)
    }

    func testSessionStateDerivesFailedWhenLatestVisibleSessionErrored() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var state = SessionState()
        state.apply(.sessionStarted(sessionID: "failed", timestamp: now, title: "Failed", tool: .codex, summary: "Run", jumpTarget: nil))
        state.apply(.sessionCompleted(
            sessionID: "failed",
            timestamp: now.addingTimeInterval(1),
            summary: "Failed",
            isError: true,
            isSessionEnd: false
        ))

        XCTAssertEqual(state.petVisualState, .failed)
    }

    func testAssetDeclaredDurationsOverrideBuiltInRowDurations() throws {
        let asset = PetAsset(
            slug: "custom",
            displayName: "Custom",
            description: "Custom durations",
            source: .imported,
            folderURL: URL(fileURLWithPath: "/tmp/custom", isDirectory: true),
            spritesheetURL: URL(fileURLWithPath: "/tmp/custom/spritesheet.webp"),
            customAnimations: [
                .running: SpriteAnimationSpec(row: 7, durationsMs: [1, 2, 3])
            ]
        )

        let spec = try XCTUnwrap(CodexAnimationRows.spec(for: .running, asset: asset))

        XCTAssertEqual(spec.row, 7)
        XCTAssertEqual(spec.durationsMs, [1, 2, 3])
        XCTAssertEqual(spec.effectiveColumnCount, 3)
    }

    func testAssetDeclaredStateRowOverridesBuiltInRow() throws {
        let asset = PetAsset(
            slug: "custom-row",
            displayName: "Custom Row",
            description: "Custom row mapping",
            source: .imported,
            folderURL: URL(fileURLWithPath: "/tmp/custom-row", isDirectory: true),
            spritesheetURL: URL(fileURLWithPath: "/tmp/custom-row/spritesheet.webp"),
            customAnimations: [
                .running: SpriteAnimationSpec(row: 2, durationsMs: [10, 20])
            ]
        )

        let spec = try XCTUnwrap(CodexAnimationRows.spec(for: .running, asset: asset))

        XCTAssertEqual(spec.row, 2)
        XCTAssertEqual(spec.durationsMs, [10, 20])
    }

    func testSpriteSheetGridSlicesAllCellsAndDetectsTransparentTailCells() throws {
        let atlas = try makeCodexAtlasImage()
        let grid = try SpriteSheetGrid(cgImage: atlas)

        XCTAssertEqual(grid.frameCount, 72)
        XCTAssertEqual(grid.frame(row: 0, column: 0)?.width, 192)
        XCTAssertEqual(grid.frame(row: 8, column: 7)?.height, 208)
        XCTAssertFalse(grid.isFrameTransparent(row: 3, column: 3))
        XCTAssertTrue(grid.isFrameTransparent(row: 3, column: 4))
        XCTAssertEqual(grid.frames(for: .waving).count, 4)
    }

    func testPlaybackSpecTrimsTransparentTailFramesFromCustomDurations() throws {
        let atlas = try makeCodexAtlasImage()
        let grid = try SpriteSheetGrid(cgImage: atlas)
        let asset = PetAsset(
            slug: "custom-tail",
            displayName: "Custom Tail",
            description: "Custom tail",
            source: .imported,
            folderURL: URL(fileURLWithPath: "/tmp/custom-tail", isDirectory: true),
            spritesheetURL: URL(fileURLWithPath: "/tmp/custom-tail/spritesheet.webp"),
            customAnimations: [
                .waving: SpriteAnimationSpec(row: 3, durationsMs: [1, 2, 3, 4, 5, 6, 7, 8])
            ]
        )

        let spec = try XCTUnwrap(grid.playbackSpec(for: .waving, asset: asset))

        XCTAssertEqual(spec.row, 3)
        XCTAssertEqual(spec.durationsMs, [1, 2, 3, 4])
        XCTAssertEqual(grid.frames(for: .waving, asset: asset).count, 4)
    }

    func testSpriteHitMaskSupportsDownsampledCurrentFrameMasks() throws {
        let mask = try XCTUnwrap(SpriteHitMask(cgImage: makeHalfOpaqueImage(), sampleStep: 4))
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        XCTAssertTrue(mask.isOpaque(at: CGPoint(x: 25, y: 50), in: bounds))
        XCTAssertFalse(mask.isOpaque(at: CGPoint(x: 75, y: 50), in: bounds))
    }
}

private func makeCodexAtlasImage() throws -> CGImage {
    let width = 1536
    let height = 1872
    let bytesPerRow = width * 4
    var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
    for row in 0..<9 {
        let usedColumns = CodexAnimationRows.usedColumnCount(forRow: row) ?? 8
        for column in 0..<8 where column < usedColumns {
            for y in 0..<208 {
                for x in 0..<192 {
                    let px = column * 192 + x
                    let py = row * 208 + y
                    let offset = py * bytesPerRow + px * 4
                    buffer[offset] = UInt8((row * 21 + 20) % 255)
                    buffer[offset + 1] = UInt8((column * 31 + 30) % 255)
                    buffer[offset + 2] = 160
                    buffer[offset + 3] = 255
                }
            }
        }
    }
    guard let provider = CGDataProvider(data: Data(buffer) as CFData),
          let image = CGImage(
              width: width,
              height: height,
              bitsPerComponent: 8,
              bitsPerPixel: 32,
              bytesPerRow: bytesPerRow,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
              provider: provider,
              decode: nil,
              shouldInterpolate: false,
              intent: .defaultIntent
          ) else {
        throw SpriteAnimationTestError.creationFailed
    }
    return image
}

private func makeHalfOpaqueImage() throws -> CGImage {
    try makeTestImage(width: 100, height: 100) { x, _ in
        x < 50 ? 255 : 0
    }
}

private enum SpriteAnimationTestError: Error {
    case creationFailed
}

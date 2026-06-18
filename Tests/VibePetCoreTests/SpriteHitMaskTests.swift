import CoreGraphics
@testable import VibePetCore
import XCTest

final class SpriteHitMaskTests: XCTestCase {
    /// A 100x100 image: left half fully opaque, right half fully transparent.
    private func makeHalfOpaqueImage() throws -> CGImage {
        let width = 100
        let height = 100
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width where x < width / 2 {
                let i = y * bytesPerRow + x * 4
                buffer[i] = 255      // R
                buffer[i + 3] = 255  // A
            }
        }
        let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let image = try XCTUnwrap(context?.makeImage())
        return image
    }

    func testOpaqueHalfIsBodyTransparentHalfPassesThrough() throws {
        let mask = try XCTUnwrap(SpriteHitMask(cgImage: try makeHalfOpaqueImage()))
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        // Left half opaque -> body.
        XCTAssertTrue(mask.isOpaque(at: CGPoint(x: 25, y: 50), in: bounds))
        // Right half transparent -> passthrough.
        XCTAssertFalse(mask.isOpaque(at: CGPoint(x: 75, y: 50), in: bounds))
    }

    func testPointsOutsideDrawnSpriteAreNotBody() throws {
        let mask = try XCTUnwrap(SpriteHitMask(cgImage: try makeHalfOpaqueImage()))
        // Letterboxed: square sprite in a wide bounds is centred; far left/right
        // bands fall outside the drawn sprite and must not register as body.
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 100)
        XCTAssertFalse(mask.isOpaque(at: CGPoint(x: 5, y: 50), in: bounds))
        XCTAssertFalse(mask.isOpaque(at: CGPoint(x: 295, y: 50), in: bounds))
        // Centre band maps to the opaque left half of the sprite.
        XCTAssertTrue(mask.isOpaque(at: CGPoint(x: 125, y: 50), in: bounds))
    }

    func testYAxisIsFlippedFromViewToImageSpace() throws {
        // Top-opaque / bottom-transparent image to prove the y flip.
        let width = 100, height = 100, bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        for y in 0..<(height / 2) {        // top rows in image space
            for x in 0..<width {
                buffer[y * bytesPerRow + x * 4 + 3] = 255
            }
        }
        let context = CGContext(
            data: &buffer, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let mask = try XCTUnwrap(SpriteHitMask(cgImage: try XCTUnwrap(context?.makeImage())))
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

        // Image-top is opaque; in AppKit view space (bottom-left origin) that is
        // the HIGH-y region.
        XCTAssertTrue(mask.isOpaque(at: CGPoint(x: 50, y: 90), in: bounds))
        XCTAssertFalse(mask.isOpaque(at: CGPoint(x: 50, y: 10), in: bounds))
    }
}

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

func makeTestImage(width: Int = 4, height: Int = 4, alphaPattern: ((Int, Int) -> UInt8)? = nil) throws -> CGImage {
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * bytesPerPixel
            pixels[offset] = UInt8((x * 41 + 32) % 255)
            pixels[offset + 1] = UInt8((y * 53 + 48) % 255)
            pixels[offset + 2] = 160
            pixels[offset + 3] = alphaPattern?(x, y) ?? 255
        }
    }

    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
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
        throw TestImageError.creationFailed
    }

    return image
}

func makeSolidTestImage(width: Int = 16, height: Int = 16, red: UInt8 = 240, green: UInt8 = 240, blue: UInt8 = 240, alpha: UInt8 = 255) throws -> CGImage {
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

    for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
        pixels[index] = red
        pixels[index + 1] = green
        pixels[index + 2] = blue
        pixels[index + 3] = alpha
    }

    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
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
        throw TestImageError.creationFailed
    }

    return image
}

func assertPNGHasAlpha(at url: URL, file: StaticString = #filePath, line: UInt = #line) throws {
    let data = try Data(contentsOf: url)
    XCTAssertFalse(data.isEmpty, file: file, line: line)

    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        XCTFail("Expected readable PNG at \(url.path)", file: file, line: line)
        return
    }

    XCTAssertTrue(image.alphaInfo.hasAlpha, "Expected PNG to preserve an alpha channel", file: file, line: line)
}

private enum TestImageError: Error {
    case creationFailed
}

private extension CGImageAlphaInfo {
    var hasAlpha: Bool {
        switch self {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        case .none, .noneSkipFirst, .noneSkipLast, .alphaOnly:
            return false
        @unknown default:
            return false
        }
    }
}

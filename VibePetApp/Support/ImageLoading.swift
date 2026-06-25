import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// UI-side helpers for turning file URLs into `CGImage`s.
enum ImageLoading {
    static let acceptedPackageContentTypes: [UTType] = [.zip, .folder]

    static func cgImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// UI-side helpers for turning file URLs into `CGImage`s.
///
/// The cutout pipeline lives in `VibePetCore`; these helpers only exist so the
/// App can load a source photo to feed the generator and reload a written
/// sprite for preview/display.
enum ImageLoading {
    /// File types the import panel accepts as source photos.
    static let acceptedContentTypes: [UTType] = [.jpeg, .png, .heic, .heif]

    static func cgImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

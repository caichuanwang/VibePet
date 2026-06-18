import CoreGraphics
import CoreImage
import Foundation
import Vision

public protocol CutoutProviding: Sendable {
    func cutout(from image: CGImage) async throws -> CGImage
}

public struct LocalCutoutGenerator: PetGenerator {
    public let identifier = "local-cutout"

    private let store: PetAssetStore
    private let cutoutProvider: any CutoutProviding

    public init(store: PetAssetStore = PetAssetStore(), cutoutProvider: any CutoutProviding = VisionCutoutProvider()) {
        self.store = store
        self.cutoutProvider = cutoutProvider
    }

    public func generate(from image: CGImage, progress: @escaping @Sendable (Double) -> Void) async throws -> PetAsset {
        progress(0)
        let maskedImage = try await cutoutProvider.cutout(from: image)
        progress(0.8)

        let id = UUID()
        let asset = PetAsset(
            id: id,
            kind: .sprite2D,
            primaryImageURL: store.spriteURL(for: id),
            layers: [],
            boundingInset: .zero,
            metadata: ["generator": identifier]
        )
        let storedAsset = try store.write(asset, sprite: maskedImage)
        progress(1)
        return storedAsset
    }
}

public struct VisionCutoutProvider: CutoutProviding {
    // Reuse one CIContext instead of allocating per cutout (it is thread-safe).
    private let context = CIContext(options: nil)

    public init() {}

    public func cutout(from image: CGImage) async throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
        try requestHandler.perform([request])

        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else {
            throw GenError.noSubject
        }

        let instance = try largestInstance(in: observation)
        let pixelBuffer = try observation.generateMaskedImage(
            ofInstances: instance,
            from: requestHandler,
            croppedToInstancesExtent: true
        )

        return try makeCGImage(from: pixelBuffer)
    }

    private func largestInstance(in observation: VNInstanceMaskObservation) throws -> IndexSet {
        let counts = countInstances(in: observation.instanceMask)
        let largest = observation.allInstances
            .map { ($0, counts[$0] ?? 0) }
            .max { $0.1 < $1.1 }

        guard let largest, largest.1 > 0 else {
            throw GenError.noSubject
        }

        return IndexSet(integer: largest.0)
    }

    private func countInstances(in pixelBuffer: CVPixelBuffer) -> [Int: Int] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return [:]
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        var counts: [Int: Int] = [:]

        for y in 0..<height {
            switch pixelFormat {
            case kCVPixelFormatType_OneComponent8:
                let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in 0..<width where row[x] > 0 {
                    counts[Int(row[x]), default: 0] += 1
                }
            case kCVPixelFormatType_OneComponent16:
                let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt16.self)
                for x in 0..<width where row[x] > 0 {
                    counts[Int(row[x]), default: 0] += 1
                }
            case kCVPixelFormatType_OneComponent32Float:
                let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
                for x in 0..<width {
                    let label = Int(row[x].rounded())
                    if label > 0 {
                        counts[label, default: 0] += 1
                    }
                }
            default:
                let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in 0..<width where row[x] > 0 {
                    counts[Int(row[x]), default: 0] += 1
                }
            }
        }

        return counts
    }

    private func makeCGImage(from pixelBuffer: CVPixelBuffer) throws -> CGImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let image = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw GenError.encodingFailed
        }
        return image
    }
}

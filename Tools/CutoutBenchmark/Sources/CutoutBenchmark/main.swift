import CoreGraphics
import Foundation
import ImageIO
import VibePetCore

struct Manifest: Decodable {
    let photos: [Photo]
}

struct Photo: Decodable {
    let filename: String
    let labels: [String]
    let usable: Bool?
}

struct PhotoResult: Encodable {
    let filename: String
    let labels: [String]
    let elapsedSeconds: Double
    let usable: Bool
    let generatedAssetID: UUID?
    let error: String?
}

struct LabelSummary: Encodable {
    let denominator: Int
    let usable: Int
    let usableRate: Double
}

struct BenchmarkSummary: Encodable {
    let total: Int
    let generated: Int
    let p50Seconds: Double
    let p95Seconds: Double
    let allUsableRate: Double
    let labels: [String: LabelSummary]
    let thresholds: ThresholdSummary
    let results: [PhotoResult]
}

struct ThresholdSummary: Encodable {
    let p50SecondsLimit: Double
    let p95SecondsLimit: Double
    let clearSubjectUsableRateLimit: Double
    let allUsableRateLimit: Double
    let p50Pass: Bool
    let p95Pass: Bool
    let clearSubjectUsableRatePass: Bool
    let allUsableRatePass: Bool
}

@main
struct CutoutBenchmark {
    static func main() async throws {
        let arguments = CommandLine.arguments.dropFirst()
        let fixturesURL = URL(fileURLWithPath: argumentValue("--fixtures", in: arguments) ?? "Tests/Fixtures/photos", isDirectory: true)
        let outputRoot = URL(fileURLWithPath: argumentValue("--output", in: arguments) ?? "/tmp/vp-cutout-benchmark-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let manifestURL = fixturesURL.appendingPathComponent("manifest.json", isDirectory: false)

        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard !manifest.photos.isEmpty else {
            throw BenchmarkError.invalidManifest("Expected at least 1 photo")
        }

        let store = PetAssetStore(applicationSupportRoot: outputRoot)
        let generator = LocalCutoutGenerator(store: store)
        var results: [PhotoResult] = []

        for photo in manifest.photos {
            let photoURL = fixturesURL.appendingPathComponent(photo.filename, isDirectory: false)
            let start = DispatchTime.now()
            do {
                let image = try loadImage(at: photoURL)
                let asset = try await generator.generate(from: image, progress: { _ in })
                let elapsed = elapsedSeconds(since: start)
                results.append(PhotoResult(
                    filename: photo.filename,
                    labels: photo.labels,
                    elapsedSeconds: elapsed,
                    usable: photo.usable ?? true,
                    generatedAssetID: asset.id,
                    error: nil
                ))
            } catch {
                let elapsed = elapsedSeconds(since: start)
                results.append(PhotoResult(
                    filename: photo.filename,
                    labels: photo.labels,
                    elapsedSeconds: elapsed,
                    usable: false,
                    generatedAssetID: nil,
                    error: String(describing: error)
                ))
            }
        }

        let summary = makeSummary(from: results)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(summary))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func argumentValue(_ name: String, in arguments: ArraySlice<String>) -> String? {
        let values = Array(arguments)
        guard let index = values.firstIndex(of: name), values.indices.contains(index + 1) else {
            return nil
        }
        return values[index + 1]
    }

    private static func loadImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw BenchmarkError.unreadableImage(url.path)
        }
        return image
    }

    private static func elapsedSeconds(since start: DispatchTime) -> Double {
        let nanoseconds = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        return Double(nanoseconds) / 1_000_000_000
    }

    private static func makeSummary(from results: [PhotoResult]) -> BenchmarkSummary {
        let successfulDurations = results.filter { $0.error == nil }.map(\.elapsedSeconds).sorted()
        let p50 = percentile(0.50, in: successfulDurations)
        let p95 = percentile(0.95, in: successfulDurations)
        let allUsable = results.filter(\.usable).count
        var labelBuckets: [String: [PhotoResult]] = [:]

        for result in results {
            for label in result.labels {
                labelBuckets[label, default: []].append(result)
            }
        }

        let labelSummaries = labelBuckets.mapValues { bucket in
            let usableCount = bucket.filter(\.usable).count
            return LabelSummary(
                denominator: bucket.count,
                usable: usableCount,
                usableRate: bucket.isEmpty ? 0 : Double(usableCount) / Double(bucket.count)
            )
        }
        let clearSubjectRate = labelSummaries["clearSubject"]?.usableRate ?? 0
        let allUsableRate = results.isEmpty ? 0 : Double(allUsable) / Double(results.count)

        return BenchmarkSummary(
            total: results.count,
            generated: results.filter { $0.error == nil }.count,
            p50Seconds: p50,
            p95Seconds: p95,
            allUsableRate: allUsableRate,
            labels: labelSummaries,
            thresholds: ThresholdSummary(
                p50SecondsLimit: 3,
                p95SecondsLimit: 8,
                clearSubjectUsableRateLimit: 0.9,
                allUsableRateLimit: 0.8,
                p50Pass: !successfulDurations.isEmpty && p50 <= 3,
                p95Pass: !successfulDurations.isEmpty && p95 <= 8,
                clearSubjectUsableRatePass: clearSubjectRate >= 0.9,
                allUsableRatePass: allUsableRate >= 0.8
            ),
            results: results
        )
    }

    private static func percentile(_ percentile: Double, in values: [Double]) -> Double {
        guard !values.isEmpty else {
            return 0
        }
        let index = min(values.count - 1, Int((Double(values.count - 1) * percentile).rounded(.up)))
        return values[index]
    }
}

enum BenchmarkError: Error, CustomStringConvertible {
    case invalidManifest(String)
    case unreadableImage(String)

    var description: String {
        switch self {
        case .invalidManifest(let message):
            return message
        case .unreadableImage(let path):
            return "Unreadable image: \(path)"
        }
    }
}

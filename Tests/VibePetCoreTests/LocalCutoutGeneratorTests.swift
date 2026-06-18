import Foundation
@testable import VibePetCore
import XCTest

final class LocalCutoutGeneratorTests: XCTestCase {
    func testSuccessfulCutoutWritesAlphaPNGAndReportsProgress() async throws {
        let directory = try TemporaryCutoutDirectory()
        let store = PetAssetStore(applicationSupportRoot: directory.url)
        let output = try makeTestImage(width: 3, height: 3, alphaPattern: { x, y in x == y ? 255 : 80 })
        let generator = LocalCutoutGenerator(
            store: store,
            cutoutProvider: MockCutoutProvider(result: .success(output))
        )
        let progressRecorder = ProgressRecorder()

        let asset = try await generator.generate(from: try makeTestImage(), progress: { value in
            progressRecorder.record(value)
        })
        let progressValues = progressRecorder.values

        XCTAssertEqual(generator.identifier, "local-cutout")
        XCTAssertEqual(asset.kind, .sprite2D)
        XCTAssertEqual(asset.layers, [])
        XCTAssertEqual(asset.metadata["generator"], "local-cutout")
        XCTAssertFalse(progressValues.isEmpty)
        XCTAssertTrue(progressValues.allSatisfy { (0...1).contains($0) })
        try assertPNGHasAlpha(at: asset.primaryImageURL)
    }

    func testNoSubjectThrowsAndDoesNotWritePartialFiles() async throws {
        let directory = try TemporaryCutoutDirectory()
        let store = PetAssetStore(applicationSupportRoot: directory.url)
        let generator = LocalCutoutGenerator(
            store: store,
            cutoutProvider: MockCutoutProvider(result: .failure(.noSubject))
        )

        do {
            _ = try await generator.generate(from: try makeTestImage(), progress: { _ in })
            XCTFail("Expected noSubject")
        } catch GenError.noSubject {
            let petsURL = directory.url.appendingPathComponent("VibePet/pets", isDirectory: true)
            XCTAssertFalse(FileManager.default.fileExists(atPath: petsURL.path))
        } catch {
            XCTFail("Expected noSubject, got \(error)")
        }
    }

    func testVisionProviderThrowsNoSubjectForFlatImage() async throws {
        let provider = VisionCutoutProvider()

        do {
            _ = try await provider.cutout(from: try makeSolidTestImage())
            XCTFail("Expected noSubject")
        } catch GenError.noSubject {
            return
        } catch {
            XCTFail("Expected noSubject, got \(error)")
        }
    }
}

private struct MockCutoutProvider: CutoutProviding {
    let result: Result<CGImage, GenError>

    func cutout(from image: CGImage) async throws -> CGImage {
        try result.get()
    }
}

private final class TemporaryCutoutDirectory {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vp-cutout-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [Double] = []

    var values: [Double] {
        lock.withLock { recordedValues }
    }

    func record(_ value: Double) {
        lock.withLock {
            recordedValues.append(value)
        }
    }
}

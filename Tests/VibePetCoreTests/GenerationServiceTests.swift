import CoreGraphics
import Foundation
@testable import VibePetCore
import XCTest

final class GenerationServiceTests: XCTestCase {
    func testActiveGeneratorIDRoutesToRegisteredGenerator() async throws {
        let image = try makeTestImage()
        let generator = RecordingGenerator(identifier: "local-cutout")
        let service = GenerationService(
            configProvider: { AppConfig.default },
            generators: [generator],
            defaultGeneratorID: "local-cutout"
        )

        let asset = try await service.generate(from: image, progress: { _ in })
        let callCount = await generator.callCount

        XCTAssertEqual(asset.metadata["generator"], "local-cutout")
        XCTAssertEqual(callCount, 1)
    }

    func testUnknownGeneratorFallsBackToDefault() async throws {
        let generator = RecordingGenerator(identifier: "local-cutout")
        let service = GenerationService(
            configProvider: {
                AppConfig(
                    activePetID: nil,
                    enabledTools: [],
                    decisionTimeoutSeconds: 1,
                    activeGeneratorID: "missing-generator",
                    petPosition: .init(x: 0, y: 0, screenWidth: 0, screenHeight: 0)
                )
            },
            generators: [generator],
            defaultGeneratorID: "local-cutout"
        )

        let asset = try await service.generate(from: try makeTestImage(), progress: { _ in })
        let callCount = await generator.callCount

        XCTAssertEqual(asset.metadata["generator"], "local-cutout")
        XCTAssertEqual(callCount, 1)
    }

    func testNewRegisteredGeneratorCanBeSelectedWithoutCallerChanges() async throws {
        let local = RecordingGenerator(identifier: "local-cutout")
        let stylized = RecordingGenerator(identifier: "mock-stylized")
        let service = GenerationService(
            configProvider: {
                AppConfig(
                    activePetID: nil,
                    enabledTools: [],
                    decisionTimeoutSeconds: 1,
                    activeGeneratorID: "mock-stylized",
                    petPosition: .init(x: 0, y: 0, screenWidth: 0, screenHeight: 0)
                )
            },
            generators: [local, stylized],
            defaultGeneratorID: "local-cutout"
        )

        let asset = try await service.generate(from: try makeTestImage(), progress: { _ in })
        let localCallCount = await local.callCount
        let stylizedCallCount = await stylized.callCount

        XCTAssertEqual(asset.metadata["generator"], "mock-stylized")
        XCTAssertEqual(localCallCount, 0)
        XCTAssertEqual(stylizedCallCount, 1)
    }
}

private actor RecordingGenerator: PetGenerator {
    nonisolated let identifier: String
    private(set) var callCount = 0

    init(identifier: String) {
        self.identifier = identifier
    }

    func generate(from image: CGImage, progress: @escaping (Double) -> Void) async throws -> PetAsset {
        callCount += 1
        progress(1)
        return PetAsset(
            id: UUID(),
            kind: .sprite2D,
            primaryImageURL: URL(fileURLWithPath: "/tmp/\(identifier).png"),
            layers: [],
            boundingInset: .zero,
            metadata: ["generator": identifier]
        )
    }
}

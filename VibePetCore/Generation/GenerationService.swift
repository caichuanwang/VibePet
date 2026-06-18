import CoreGraphics
import Foundation

public struct GenerationService: Sendable {
    public static let defaultGeneratorID = "local-cutout"

    private let configProvider: @Sendable () throws -> AppConfig
    private let generators: [String: any PetGenerator]
    private let defaultGeneratorID: String

    public init(
        configStore: ConfigStore = ConfigStore(),
        generators: [any PetGenerator] = [LocalCutoutGenerator()],
        defaultGeneratorID: String = GenerationService.defaultGeneratorID
    ) {
        self.init(
            configProvider: { try configStore.read() },
            generators: generators,
            defaultGeneratorID: defaultGeneratorID
        )
    }

    public init(
        configProvider: @escaping @Sendable () throws -> AppConfig,
        generators: [any PetGenerator],
        defaultGeneratorID: String = GenerationService.defaultGeneratorID
    ) {
        self.configProvider = configProvider
        self.generators = Dictionary(uniqueKeysWithValues: generators.map { ($0.identifier, $0) })
        self.defaultGeneratorID = defaultGeneratorID
    }

    public func generate(from image: CGImage, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> PetAsset {
        let config = try configProvider()
        let generator = generators[config.activeGeneratorID] ?? generators[defaultGeneratorID]

        guard let generator else {
            throw GenError.defaultGeneratorUnavailable(defaultGeneratorID)
        }

        return try await generator.generate(from: image, progress: progress)
    }
}

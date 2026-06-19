import Foundation

public struct ConfigStore: Sendable {
    public let configURL: URL

    private let applicationSupportRoot: URL?
    private let supportDirectoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(applicationSupportRoot: URL? = nil) {
        self.applicationSupportRoot = applicationSupportRoot
        supportDirectoryURL = SupportDirectory.url(applicationSupportRoot: applicationSupportRoot)
        configURL = supportDirectoryURL.appendingPathComponent("config.json", isDirectory: false)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        decoder = JSONDecoder()
    }

    public func read() throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return .default
        }

        let data = try Data(contentsOf: configURL)
        return try decoder.decode(AppConfig.self, from: data)
    }

    public func write(_ config: AppConfig) throws {
        try SupportDirectory.ensure(applicationSupportRoot: applicationSupportRoot)
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: [.atomic])
    }
}

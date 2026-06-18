import XCTest
@testable import VibePetCore

final class ConfigStoreTests: XCTestCase {
    func testMissingConfigReturnsDefault() throws {
        let root = try TemporaryConfigDirectory()
        let store = ConfigStore(applicationSupportRoot: root.url)

        let config = try store.read()

        XCTAssertEqual(config, .default)
    }

    func testWriteThenReadRoundTrips() throws {
        let root = try TemporaryConfigDirectory()
        let store = ConfigStore(applicationSupportRoot: root.url)
        let config = AppConfig(
            activePetID: "pet-1",
            enabledTools: [.claudeCode, .codex],
            decisionTimeoutSeconds: 12,
            activeGeneratorID: "remote-cutout",
            petPosition: PetPosition(x: 144, y: 288, screenWidth: 1728, screenHeight: 1117)
        )

        try store.write(config)

        XCTAssertEqual(try store.read(), config)
    }

    func testAppConfigCodableRoundTrips() throws {
        let config = AppConfig(
            activePetID: nil,
            enabledTools: [.codex],
            decisionTimeoutSeconds: 20,
            activeGeneratorID: "local-cutout",
            petPosition: PetPosition(x: 24, y: 48, screenWidth: 1440, screenHeight: 900)
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        XCTAssertEqual(decoded, config)
    }

    func testConfigFileLivesUnderVibePetSupportDirectory() {
        let root = URL(fileURLWithPath: "/tmp/config-root", isDirectory: true)
        let store = ConfigStore(applicationSupportRoot: root)

        XCTAssertEqual(
            store.configURL.path,
            root.appendingPathComponent("VibePet/config.json").path
        )
    }
}

private final class TemporaryConfigDirectory {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vp-config-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

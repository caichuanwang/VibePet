import Foundation

public struct AppConfig: Codable, Equatable, Sendable {
    public let activePetID: String?
    public let enabledTools: [ToolKind]
    public let decisionTimeoutSeconds: TimeInterval
    public let activeGeneratorID: String
    public let petPosition: PetPosition

    public static let `default` = AppConfig(
        activePetID: nil,
        enabledTools: [.claudeCode, .codex],
        decisionTimeoutSeconds: 20,
        activeGeneratorID: "local-cutout",
        petPosition: PetPosition(x: 24, y: 24, screenWidth: 0, screenHeight: 0)
    )

    public init(
        activePetID: String?,
        enabledTools: [ToolKind],
        decisionTimeoutSeconds: TimeInterval,
        activeGeneratorID: String,
        petPosition: PetPosition
    ) {
        self.activePetID = activePetID
        self.enabledTools = enabledTools
        self.decisionTimeoutSeconds = decisionTimeoutSeconds
        self.activeGeneratorID = activeGeneratorID
        self.petPosition = petPosition
    }
}

public struct PetPosition: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let screenWidth: Double
    public let screenHeight: Double

    public init(x: Double, y: Double, screenWidth: Double, screenHeight: Double) {
        self.x = x
        self.y = y
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
    }
}

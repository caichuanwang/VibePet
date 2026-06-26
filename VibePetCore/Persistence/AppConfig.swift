import Foundation

public struct AppConfig: Codable, Equatable, Sendable {
    public let activePetID: String?
    public let enabledTools: [ToolKind]
    public let activeGeneratorID: String
    public let petPosition: PetPosition
    public let hasCompletedOnboarding: Bool

    public static let `default` = AppConfig(
        activePetID: nil,
        enabledTools: [.claudeCode, .codex],
        activeGeneratorID: "local-cutout",
        petPosition: PetPosition(x: 24, y: 24, screenWidth: 0, screenHeight: 0),
        hasCompletedOnboarding: false
    )

    private enum CodingKeys: String, CodingKey {
        case activePetID
        case enabledTools
        case decisionTimeoutSeconds
        case activeGeneratorID
        case petPosition
        case hasCompletedOnboarding
    }

    public init(
        activePetID: String?,
        enabledTools: [ToolKind],
        activeGeneratorID: String,
        petPosition: PetPosition,
        hasCompletedOnboarding: Bool = false
    ) {
        self.activePetID = activePetID
        self.enabledTools = enabledTools
        self.activeGeneratorID = activeGeneratorID
        self.petPosition = petPosition
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activePetID = try container.decodeIfPresent(String.self, forKey: .activePetID)
        enabledTools = try container.decode([ToolKind].self, forKey: .enabledTools)
        _ = try container.decodeIfPresent(TimeInterval.self, forKey: .decisionTimeoutSeconds)
        activeGeneratorID = try container.decode(String.self, forKey: .activeGeneratorID)
        petPosition = try container.decode(PetPosition.self, forKey: .petPosition)
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(activePetID, forKey: .activePetID)
        try container.encode(enabledTools, forKey: .enabledTools)
        try container.encode(activeGeneratorID, forKey: .activeGeneratorID)
        try container.encode(petPosition, forKey: .petPosition)
        try container.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
    }

    /// Returns a copy with the given fields overridden; unspecified fields are
    /// carried over unchanged. Centralises config mutation so adding a field
    /// doesn't require updating every call site (pass `activePetID: .some(nil)`
    /// to clear the active pet).
    public func with(
        activePetID: String?? = nil,
        enabledTools: [ToolKind]? = nil,
        activeGeneratorID: String? = nil,
        petPosition: PetPosition? = nil,
        hasCompletedOnboarding: Bool? = nil
    ) -> AppConfig {
        AppConfig(
            activePetID: activePetID ?? self.activePetID,
            enabledTools: enabledTools ?? self.enabledTools,
            activeGeneratorID: activeGeneratorID ?? self.activeGeneratorID,
            petPosition: petPosition ?? self.petPosition,
            hasCompletedOnboarding: hasCompletedOnboarding ?? self.hasCompletedOnboarding
        )
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

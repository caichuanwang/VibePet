import Foundation

public struct PetAsset: Codable, Equatable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable {
        case imported
        case shared
    }

    public let slug: String
    public let displayName: String
    public let description: String
    public let source: Source
    public let folderURL: URL
    public let spritesheetURL: URL
    public let customAnimations: [PetVisualState: SpriteAnimationSpec]

    public var id: String { slug }

    public init(
        slug: String,
        displayName: String,
        description: String,
        source: Source,
        folderURL: URL,
        spritesheetURL: URL,
        customAnimations: [PetVisualState: SpriteAnimationSpec] = [:]
    ) {
        self.slug = slug
        self.displayName = displayName
        self.description = description
        self.source = source
        self.folderURL = folderURL
        self.spritesheetURL = spritesheetURL
        self.customAnimations = customAnimations
    }
}

public struct PetAssetIssue: Equatable, Sendable {
    public let slug: String
    public let reason: String

    public init(slug: String, reason: String) {
        self.slug = slug
        self.reason = reason
    }
}

public struct PetAssetParseResult: Equatable, Sendable {
    public let asset: PetAsset?
    public let issue: PetAssetIssue?

    public init(asset: PetAsset?, issue: PetAssetIssue?) {
        self.asset = asset
        self.issue = issue
    }
}

public enum PetAssetError: Error, Equatable, Sendable {
    case invalidPackage(String)
    case writeFailed(String)
}

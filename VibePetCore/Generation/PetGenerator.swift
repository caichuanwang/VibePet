import CoreGraphics
import Foundation

public protocol PetGenerator: Sendable {
    var identifier: String { get }

    func generate(from image: CGImage, progress: @escaping @Sendable (Double) -> Void) async throws -> PetAsset
}

public struct PetAsset: Codable, Equatable, Sendable {
    public let id: UUID
    public let kind: PetKind
    public let primaryImageURL: URL
    public let layers: [PetLayer]
    public let boundingInset: PetEdgeInsets
    public let metadata: [String: String]

    public init(
        id: UUID,
        kind: PetKind,
        primaryImageURL: URL,
        layers: [PetLayer],
        boundingInset: PetEdgeInsets,
        metadata: [String: String]
    ) {
        self.id = id
        self.kind = kind
        self.primaryImageURL = primaryImageURL
        self.layers = layers
        self.boundingInset = boundingInset
        self.metadata = metadata
    }
}

public enum PetKind: String, Codable, CaseIterable, Sendable {
    case sprite2D
    case stylized2D
    case model3D
}

public struct PetLayer: Codable, Equatable, Sendable {
    public let id: String
    public let imageURL: URL
    public let zIndex: Int
    public let metadata: [String: String]

    public init(id: String, imageURL: URL, zIndex: Int, metadata: [String: String]) {
        self.id = id
        self.imageURL = imageURL
        self.zIndex = zIndex
        self.metadata = metadata
    }
}

public struct PetEdgeInsets: Codable, Equatable, Sendable {
    public let top: Double
    public let leading: Double
    public let bottom: Double
    public let trailing: Double

    public static let zero = PetEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)

    public init(top: Double, leading: Double, bottom: Double, trailing: Double) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
}

public enum GenError: Error, Equatable, Sendable {
    case noSubject
    case encodingFailed
    case writeFailed(String)
    case defaultGeneratorUnavailable(String)
}

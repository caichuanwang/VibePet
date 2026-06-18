import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct PetAssetStore: Sendable {
    public let petsDirectoryURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(applicationSupportRoot: URL? = nil) {
        let root = applicationSupportRoot ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        petsDirectoryURL = root
            .appendingPathComponent("VibePet", isDirectory: true)
            .appendingPathComponent("pets", isDirectory: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        decoder = JSONDecoder()
    }

    public func write(_ asset: PetAsset, sprite: CGImage) throws -> PetAsset {
        let id = asset.id
        let petDirectory = directoryURL(for: id)
        let spriteURL = self.spriteURL(for: id)
        let metaURL = petDirectory.appendingPathComponent("meta.json", isDirectory: false)
        let storedAsset = PetAsset(
            id: asset.id,
            kind: asset.kind,
            primaryImageURL: spriteURL,
            layers: asset.layers,
            boundingInset: asset.boundingInset,
            metadata: asset.metadata
        )

        do {
            try FileManager.default.createDirectory(at: petDirectory, withIntermediateDirectories: true)
            try writePNG(sprite, to: spriteURL)
            let metadata = try encoder.encode(storedAsset)
            try metadata.write(to: metaURL, options: [.atomic])
            return storedAsset
        } catch {
            try? FileManager.default.removeItem(at: petDirectory)
            throw GenError.writeFailed(error.localizedDescription)
        }
    }

    public func read(id: UUID) throws -> PetAsset? {
        let metaURL = directoryURL(for: id).appendingPathComponent("meta.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: metaURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: metaURL)
        let asset = try decoder.decode(PetAsset.self, from: data)
        guard FileManager.default.fileExists(atPath: asset.primaryImageURL.path) else {
            return nil
        }

        return asset
    }

    public func listIDs() throws -> [UUID] {
        guard FileManager.default.fileExists(atPath: petsDirectoryURL.path) else {
            return []
        }

        let urls = try FileManager.default.contentsOfDirectory(
            at: petsDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return urls.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return UUID(uuidString: url.lastPathComponent)
        }
        .sorted { $0.uuidString < $1.uuidString }
    }

    public func list() throws -> [PetAsset] {
        try listIDs().compactMap { try read(id: $0) }
    }

    public func delete(id: UUID) throws {
        let petDirectory = directoryURL(for: id)
        guard FileManager.default.fileExists(atPath: petDirectory.path) else {
            return
        }

        try FileManager.default.removeItem(at: petDirectory)
    }

    public func directoryURL(for id: UUID) -> URL {
        petsDirectoryURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func spriteURL(for id: UUID) -> URL {
        directoryURL(for: id).appendingPathComponent("sprite.png", isDirectory: false)
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw GenError.encodingFailed
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw GenError.encodingFailed
        }
    }
}

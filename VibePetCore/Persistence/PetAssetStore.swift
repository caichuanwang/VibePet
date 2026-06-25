import Foundation
import ImageIO

public struct PetAssetStore: Sendable {
    public static let columns = 8
    public static let rows = 9
    public static let cellWidth = 192
    public static let cellHeight = 208
    public static let spritesheetWidth = columns * cellWidth
    public static let spritesheetHeight = rows * cellHeight

    public let petsDirectoryURL: URL
    public let sharedPetsDirectoryURL: URL

    private let decoder: JSONDecoder

    public init(applicationSupportRoot: URL? = nil, sharedPetsRoot: URL? = nil) {
        let root = applicationSupportRoot ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        petsDirectoryURL = root
            .appendingPathComponent("VibePet", isDirectory: true)
            .appendingPathComponent("pets", isDirectory: true)
        sharedPetsDirectoryURL = sharedPetsRoot ?? Self.defaultSharedPetsDirectoryURL()
        decoder = JSONDecoder()
    }

    public func read(slug: String) throws -> PetAsset? {
        try list().first { $0.slug == slug }
    }

    public func listSlugs() throws -> [String] {
        try list().map(\.slug)
    }

    public func list() throws -> [PetAsset] {
        let (assets, _) = try scan()
        return assets
    }

    public func listWithIssues() throws -> (assets: [PetAsset], issues: [PetAssetIssue]) {
        try scan()
    }

    public static func parsePetFolder(_ folderURL: URL, source: PetAsset.Source, slugOverride: String? = nil) -> PetAssetParseResult {
        let fallbackSlug = folderURL.lastPathComponent
        let manifestURL = folderURL.appendingPathComponent("pet.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return PetAssetParseResult(asset: nil, issue: nil)
        }

        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(CodexPetManifest.self, from: data)
            let slug = slugOverride ?? fallbackSlug
            let spritesheetURL = folderURL
                .appendingPathComponent(manifest.spritesheetPath, isDirectory: false)
                .standardizedFileURL
            let standardizedFolder = folderURL.standardizedFileURL
            let folderPath = standardizedFolder.path.hasSuffix("/") ? standardizedFolder.path : standardizedFolder.path + "/"
            guard spritesheetURL.path.hasPrefix(folderPath) else {
                return failure(slug: slug, reason: "spritesheetPath must point inside pet folder")
            }
            guard FileManager.default.fileExists(atPath: spritesheetURL.path) else {
                return failure(slug: slug, reason: "spritesheetPath file is missing: \(manifest.spritesheetPath)")
            }
            guard let imageSource = CGImageSourceCreateWithURL(spritesheetURL as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int else {
                return failure(slug: slug, reason: "spritesheet could not be decoded")
            }
            guard width == spritesheetWidth, height == spritesheetHeight else {
                return failure(
                    slug: slug,
                    reason: "spritesheet must be \(spritesheetWidth)x\(spritesheetHeight), got \(width)x\(height)"
                )
            }

            return PetAssetParseResult(
                asset: PetAsset(
                    slug: slug,
                    displayName: manifest.displayName,
                    description: manifest.description ?? "",
                    source: source,
                    folderURL: folderURL,
                    spritesheetURL: spritesheetURL,
                    customAnimations: manifest.customAnimationsByState
                ),
                issue: nil
            )
        } catch let DecodingError.keyNotFound(key, _) {
            return failure(slug: slugOverride ?? fallbackSlug, reason: "pet.json is missing required field \(key.stringValue)")
        } catch {
            return failure(slug: slugOverride ?? fallbackSlug, reason: "pet.json could not be parsed: \(error.localizedDescription)")
        }
    }

    private static func failure(slug: String, reason: String) -> PetAssetParseResult {
        PetAssetParseResult(asset: nil, issue: PetAssetIssue(slug: slug, reason: reason))
    }

    private func scan() throws -> ([PetAsset], [PetAssetIssue]) {
        var assetsBySlug: [String: PetAsset] = [:]
        var issues: [PetAssetIssue] = []

        let shared = try assets(in: sharedPetsDirectoryURL, source: .shared)
        for result in shared {
            if let asset = result.asset {
                assetsBySlug[asset.slug] = asset
            } else if let issue = result.issue {
                issues.append(issue)
            }
        }

        let imported = try assets(in: petsDirectoryURL, source: .imported)
        for result in imported {
            if let asset = result.asset {
                assetsBySlug[asset.slug] = asset
            } else if let issue = result.issue {
                issues.append(issue)
            }
        }

        return (
            assetsBySlug.values.sorted { lhs, rhs in lhs.slug < rhs.slug },
            issues.sorted { lhs, rhs in lhs.slug < rhs.slug }
        )
    }

    private func assets(in root: URL, source: PetAsset.Source) throws -> [PetAssetParseResult] {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return []
        }
        let folders = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return folders
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { Self.parsePetFolder($0, source: source) }
    }

    private static func defaultSharedPetsDirectoryURL() -> URL {
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap {
            $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true)
        }
        let root = codexHome ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        return root.appendingPathComponent("pets", isDirectory: true)
    }
}

private struct CodexPetManifest: Decodable {
    let id: String
    let displayName: String
    let description: String?
    let spritesheetPath: String
    private let states: [String: StateManifest]?

    var customAnimationsByState: [PetVisualState: SpriteAnimationSpec] {
        guard let states else { return [:] }
        var result: [PetVisualState: SpriteAnimationSpec] = [:]
        for (name, state) in states {
            guard let visualState = PetVisualState(rawValue: name),
                  let row = state.row,
                  let durations = state.durations,
                  !durations.isEmpty else {
                continue
            }
            result[visualState] = SpriteAnimationSpec(row: row, durationsMs: durations)
        }
        return result
    }

    private struct StateManifest: Decodable {
        let row: Int?
        let durations: [Int]?
    }
}

import Foundation

public struct PetPackageImporter: Sendable {
    public let store: PetAssetStore
    private let replacementNameProvider: @Sendable (String) -> String

    public init(
        store: PetAssetStore = PetAssetStore(),
        replacementNameProvider: @escaping @Sendable (String) -> String = { "\($0).replaced-\(UUID().uuidString)" }
    ) {
        self.store = store
        self.replacementNameProvider = replacementNameProvider
    }

    @discardableResult
    public func importPackage(from sourceURL: URL) throws -> PetAsset {
        let workingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibepet-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingRoot) }

        let packageRoot: URL
        let rootSlugOverride: String?
        if sourceURL.pathExtension.lowercased() == "zip" {
            packageRoot = workingRoot.appendingPathComponent("unzipped", isDirectory: true)
            rootSlugOverride = sourceURL.deletingPathExtension().lastPathComponent
            try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)
            try unzip(sourceURL, to: packageRoot)
        } else {
            packageRoot = sourceURL
            rootSlugOverride = nil
        }

        guard let petFolder = try locatePetFolder(under: packageRoot) else {
            throw PetAssetError.invalidPackage("pet.json is missing")
        }
        let validation = PetAssetStore.parsePetFolder(
            petFolder,
            source: .imported,
            slugOverride: petFolder == packageRoot ? rootSlugOverride : nil
        )
        guard let asset = validation.asset else {
            throw PetAssetError.invalidPackage(validation.issue?.reason ?? "invalid pet package")
        }

        let destination = store.petsDirectoryURL.appendingPathComponent(asset.slug, isDirectory: true)
        let staging = workingRoot.appendingPathComponent("staging-\(asset.slug)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let children = try FileManager.default.contentsOfDirectory(
            at: petFolder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for child in children where child.lastPathComponent != "__MACOSX" {
            try FileManager.default.copyItem(at: child, to: staging.appendingPathComponent(child.lastPathComponent))
        }

        try replaceExistingPackage(staging: staging, destination: destination, slug: asset.slug)

        let imported = PetAssetStore.parsePetFolder(destination, source: .imported)
        guard let importedAsset = imported.asset else {
            throw PetAssetError.writeFailed(imported.issue?.reason ?? "imported package could not be read")
        }
        return importedAsset
    }

    private func replaceExistingPackage(staging: URL, destination: URL, slug: String) throws {
        var backup: URL?
        do {
            try FileManager.default.createDirectory(at: store.petsDirectoryURL, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                let backupURL = store.petsDirectoryURL.appendingPathComponent(replacementNameProvider(slug), isDirectory: true)
                try FileManager.default.moveItem(at: destination, to: backupURL)
                backup = backupURL
            }
            try FileManager.default.moveItem(at: staging, to: destination)
            if let backup {
                try? FileManager.default.removeItem(at: backup)
            }
        } catch {
            if !FileManager.default.fileExists(atPath: destination.path), let backup {
                try? FileManager.default.moveItem(at: backup, to: destination)
            }
            throw PetAssetError.writeFailed(error.localizedDescription)
        }
    }

    private func unzip(_ zipURL: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", zipURL.path, "-d", destination.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw PetAssetError.invalidPackage("zip could not be extracted: \(error.localizedDescription)")
        }
        guard process.terminationStatus == 0 else {
            throw PetAssetError.invalidPackage("zip could not be extracted")
        }
    }

    private func locatePetFolder(under root: URL) throws -> URL? {
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("pet.json").path) {
            return root
        }
        let children = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let childFolders = children
            .filter { $0.lastPathComponent != "__MACOSX" }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let petFolders = childFolders.filter {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("pet.json").path)
        }
        return petFolders.count == 1 ? petFolders[0] : nil
    }
}

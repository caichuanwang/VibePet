import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import VibePetApp
@testable import VibePetCore

@MainActor
final class PetImportViewModelTests: XCTestCase {
    func testImportDoesNotOverwriteConfigWithDefaultsWhenReadFails() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vp-import-vm-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let applicationSupportRoot = root.appendingPathComponent("Application Support", isDirectory: true)
        let sharedRoot = root.appendingPathComponent(".codex/pets", isDirectory: true)
        let package = root.appendingPathComponent("boba", isDirectory: true)
        try FileManager.default.createDirectory(at: sharedRoot, withIntermediateDirectories: true)
        try writeAppTestPet(folder: package, id: "boba", displayName: "Boba")

        let configStore = ConfigStore(applicationSupportRoot: applicationSupportRoot)
        try FileManager.default.createDirectory(
            at: configStore.configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{not-json".utf8).write(to: configStore.configURL)
        let viewModel = PetImportViewModel(
            importer: PetPackageImporter(store: PetAssetStore(
                applicationSupportRoot: applicationSupportRoot,
                sharedPetsRoot: sharedRoot
            )),
            configStore: configStore
        )

        viewModel.importPackage(from: package)

        guard case .error = viewModel.phase else {
            return XCTFail("Expected config read failure to surface as an import error")
        }
        XCTAssertNil(viewModel.selectedAsset)
        XCTAssertEqual(String(data: try Data(contentsOf: configStore.configURL), encoding: .utf8), "{not-json")
    }
}

private func writeAppTestPet(folder: URL, id: String, displayName: String) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let manifest = """
    {
      "id": "\(id)",
      "displayName": "\(displayName)",
      "description": "",
      "spritesheetPath": "spritesheet.webp"
    }
    """
    try Data(manifest.utf8).write(to: folder.appendingPathComponent("pet.json"))
    try writeAppTestImage(to: folder.appendingPathComponent("spritesheet.webp"))
}

private func writeAppTestImage(to url: URL) throws {
    let width = 1536
    let height = 1872
    let bytesPerRow = width * 4
    var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
    for offset in stride(from: 0, to: buffer.count, by: 4) {
        buffer[offset] = 12
        buffer[offset + 1] = 140
        buffer[offset + 2] = 180
        buffer[offset + 3] = 255
    }
    guard let provider = CGDataProvider(data: Data(buffer) as CFData),
          let image = CGImage(
              width: width,
              height: height,
              bitsPerComponent: 8,
              bitsPerPixel: 32,
              bytesPerRow: bytesPerRow,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
              provider: provider,
              decode: nil,
              shouldInterpolate: false,
              intent: .defaultIntent
          ),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown)
    }
}

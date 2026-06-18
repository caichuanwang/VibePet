import CoreGraphics
@testable import VibePetCore
import XCTest

final class PetImportStateMachineTests: XCTestCase {
    func testHappyPathTransitionsThroughGeneratingResultAndPlaced() throws {
        var machine = PetImportStateMachine()
        let asset = makeGeneratedAsset()

        machine.startGeneration(sourceName: "cat.png")
        machine.finishGeneration(asset: asset, sprite: try makeTestImage(), suggestedName: "cat")
        machine.place(assetID: asset.id)

        XCTAssertEqual(machine.history, [.idle, .generating, .result, .placed])
    }

    func testGenerationFailureTransitionsToError() {
        var machine = PetImportStateMachine()

        machine.startGeneration(sourceName: "flat.png")
        machine.failGeneration(GenError.noSubject)

        XCTAssertEqual(machine.history, [.idle, .generating, .error])
        XCTAssertEqual(machine.errorMessage, "No subject was found in that photo.")
    }

    func testRetryFromErrorStartsGeneratingAgain() {
        var machine = PetImportStateMachine()

        machine.startGeneration(sourceName: "flat.png")
        machine.failGeneration(GenError.noSubject)
        machine.retry()

        XCTAssertEqual(machine.history, [.idle, .generating, .error, .generating])
    }

    func testFailureDoesNotRecordPlaceableAsset() {
        var machine = PetImportStateMachine()

        machine.startGeneration(sourceName: "flat.png")
        machine.failGeneration(GenError.noSubject)

        XCTAssertNil(machine.generatedAsset)
        XCTAssertNil(machine.generatedSprite)
    }

    private func makeGeneratedAsset() -> PetAsset {
        PetAsset(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            kind: .sprite2D,
            primaryImageURL: URL(fileURLWithPath: "/tmp/generated.png"),
            layers: [],
            boundingInset: .zero,
            metadata: [:]
        )
    }
}

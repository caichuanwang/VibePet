@testable import VibePetApp
import AppKit
import XCTest

final class OverlayWindowBehaviorTests: XCTestCase {
    @MainActor
    func testPetOverlayCollectionBehaviorIsStationaryAcrossSpaces() {
        assertStationaryAllSpaces(PetWindow.overlayCollectionBehavior)
    }

    @MainActor
    func testPetWindowUsesNonactivatingPanelOverlay() {
        let window = PetWindow(frame: CGRect(x: 0, y: 0, width: 120, height: 120))

        let panel: NSPanel = window

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.hidesOnDeactivate)
    }

    @MainActor
    func testBubbleOverlayCollectionBehaviorMatchesPetWindow() {
        assertStationaryAllSpaces(PetWindowSurface.bubbleOverlayCollectionBehavior)
        XCTAssertEqual(PetWindowSurface.bubbleOverlayCollectionBehavior, PetWindow.overlayCollectionBehavior)
    }

    private func assertStationaryAllSpaces(
        _ behavior: NSWindow.CollectionBehavior,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces), file: file, line: line)
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary), file: file, line: line)
        XCTAssertTrue(behavior.contains(.stationary), file: file, line: line)
        XCTAssertTrue(behavior.contains(.ignoresCycle), file: file, line: line)
    }
}

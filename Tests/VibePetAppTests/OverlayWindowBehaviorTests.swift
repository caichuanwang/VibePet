@testable import VibePetApp
import AppKit
import VibePetCore
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

    @MainActor
    func testDashboardPanelUsesStationaryNonactivatingOverlay() {
        let controller = SessionDashboardWindowController(
            state: SessionState(),
            activePetName: "Pixel",
            petFrame: CGRect(x: 0, y: 0, width: 120, height: 120),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            cardProvider: { _ in nil },
            onSelectedSessionChanged: { _, _ in }
        )

        guard let panel = controller.window as? NSPanel else {
            XCTFail("dashboard should be hosted in an NSPanel")
            return
        }
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.hidesOnDeactivate)
        assertStationaryAllSpaces(panel.collectionBehavior)
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

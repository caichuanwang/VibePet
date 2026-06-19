import XCTest
@testable import VibePetApp
@testable import VibePetCore

/// App-layer integration for the M3 notification flow: a real `BridgeServer`
/// (driven by `BridgeServerHost`) receives an envelope sent by a real
/// `BridgeClient`, `PetController` routes it, and a fake `PetSurface` substitutes
/// the AppKit windows so the "bubble appears then auto-dismisses" lifecycle is
/// verifiable headlessly. The literal NSWindow rendering is verified by manual demo.
@MainActor
final class NotificationBubbleFlowTests: XCTestCase {
    func testStartupGreetingFlowsThroughStateMachine() {
        let surface = FakePetSurface()
        let controller = PetController(surface: surface)

        controller.greet()

        XCTAssertEqual(controller.state, .greet)
        XCTAssertEqual(surface.lastActivity, .greeting)
    }

    func testGreetingIsTransientAndReturnsToIdle() async throws {
        let surface = FakePetSurface()
        let controller = PetController(surface: surface, greetDuration: 0.02)

        controller.greet()
        XCTAssertEqual(controller.state, .greet)
        XCTAssertEqual(surface.lastActivity, .greeting)

        // Greeting has no bubble; the controller must schedule its own return to idle.
        try await waitUntil { controller.state == .idle }
        XCTAssertEqual(surface.lastActivity, .idle, "greet must re-render to the resting sprite once it expires")
    }

    func testNotificationPresentsBubbleAndReturnsToIdleOnDismiss() {
        let surface = FakePetSurface()
        let controller = PetController(surface: surface)

        controller.handle(completionEnvelope())

        XCTAssertEqual(controller.state, .notify)
        XCTAssertEqual(surface.presentedBubbles.count, 1)
        XCTAssertEqual(surface.lastActivity, .idle, "notify keeps the resting sprite; the bubble carries the notification")

        // Simulate the bubble's auto-dismiss / hover-expiry callback firing.
        surface.fireDismiss()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(surface.dismissCount, 1)
    }

    func testHiddenPetDropsNotificationWithoutBubble() {
        let surface = FakePetSurface()
        surface.petFrame = nil // pet hidden
        let controller = PetController(surface: surface)

        controller.handle(completionEnvelope())

        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(surface.presentedBubbles.isEmpty)
    }

    func testEnvelopeFromBridgeReachesControllerViaHost() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let surface = FakePetSurface()
        let controller = PetController(surface: surface)
        let host = BridgeServerHost(petController: controller, socketPath: socketPath)

        host.start()
        defer { host.stop() }
        // Wait for the server to be listening without sending an envelope (which
        // would itself produce a bubble); canConnect opens and closes a connection.
        try await waitUntil { BridgeSocketIO.canConnect(to: socketPath.socketURL.path) }

        // Real CLI-side send over the real socket.
        let client = BridgeClient(socketPath: socketPath)
        try await client.sendOneWay(completionEnvelope())

        try await waitUntil { surface.presentedBubbles.count == 1 }
        XCTAssertEqual(controller.state, .notify)
        guard case .completion = surface.presentedBubbles.first?.content else {
            return XCTFail("Expected a completion bubble")
        }
    }

    // MARK: - Helpers

    private func completionEnvelope() -> BridgeEnvelope {
        BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .claudeCode, projectName: "VibePet", sessionShortId: "a1b2c3", cwd: "/tmp/VibePet"),
            content: .completion(CompletionContent(markdownSummary: "新增 3 个测试，全部通过", isError: false))
        )
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Condition not met within \(timeout)s")
    }
}

@MainActor
private final class FakePetSurface: PetSurface {
    struct PresentedBubble {
        let content: BubbleContent
        let source: SourceInfo
        let placement: BubbleAnchor.Placement
    }

    var petFrame: CGRect? = CGRect(x: 800, y: 0, width: 120, height: 120)
    var visibleFrame: CGRect = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private(set) var lastActivity: PetActivity?
    private(set) var presentedBubbles: [PresentedBubble] = []
    private(set) var dismissCount = 0
    private var onDismiss: (() -> Void)?

    func renderPet(asset: PetAsset?, activity: PetActivity) {
        lastActivity = activity
    }

    func presentBubble(
        content: BubbleContent,
        source: SourceInfo,
        placement: BubbleAnchor.Placement,
        onDismiss: @escaping () -> Void
    ) {
        presentedBubbles.append(PresentedBubble(content: content, source: source, placement: placement))
        self.onDismiss = onDismiss
    }

    func dismissBubble() {
        dismissCount += 1
    }

    func fireDismiss() {
        onDismiss?()
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vp-app-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

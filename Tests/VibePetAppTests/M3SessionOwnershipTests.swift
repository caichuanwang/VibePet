import XCTest
@testable import VibePetApp
@testable import VibePetCore

@MainActor
final class M3SessionOwnershipTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testDuplicateAndStaleEventsDoNotPublishAgain() {
        let surface = M3PetSurface()
        let controller = PetController(surface: surface, greetDuration: 60)
        var publishedStates: [SessionState] = []
        let host = makeHost(controller: controller, onChange: { publishedStates.append($0) })
        let started = sessionStarted(summary: "User prompt: Keep one canonical state")

        host.applyForTesting(started)
        host.applyForTesting(started)
        host.applyForTesting(.activityUpdated(
            sessionID: "m3-session",
            timestamp: base.addingTimeInterval(-1),
            summary: "stale"
        ))

        XCTAssertEqual(publishedStates.count, 1)
        XCTAssertEqual(publishedStates.first?.sessionsByID["m3-session"]?.summary, "User prompt: Keep one canonical state")
    }

    func testUnchangedLivenessSweepDoesNotPublish() async {
        let surface = M3PetSurface()
        let controller = PetController(surface: surface, greetDuration: 60)
        var publishedStates: [SessionState] = []
        let host = makeHost(
            controller: controller,
            liveSessionProvider: { state in Set(state.sessionsByID.keys) }
        ) { publishedStates.append($0) }

        host.applyForTesting(sessionStarted(summary: "Running"))
        XCTAssertEqual(publishedStates.count, 1)

        await host.runLivenessSweepOnce()

        XCTAssertEqual(publishedStates.count, 1)
    }

    func testGreetingPublishSynchronizesPetConversationSnapshot() async throws {
        let surface = M3PetSurface()
        let controller = PetController(surface: surface, greetDuration: 60, decisionTimeoutProvider: { _ in 5 })
        var publishedState: SessionState?
        let host = makeHost(controller: controller, onChange: { publishedState = $0 })
        host.applyForTesting(sessionStarted(summary: "User prompt: Preserve context"))

        XCTAssertEqual(controller.sessionStateSnapshot, publishedState)
        XCTAssertEqual(host.sessionStateSnapshot, publishedState)

        let request = questionEnvelope()
        let responseTask = Task { await controller.requestDecision(for: request) }
        try await waitUntil { surface.questionContext != nil }

        XCTAssertEqual(surface.questionContext?.latestUserPrompt, "Preserve context")
        XCTAssertEqual(surface.questionContext?.agentSummary, "User prompt: Preserve context")

        surface.answerQuestion(.defer)
        let response = await responseTask.value
        XCTAssertEqual(response, .defer)
    }

    func testDashboardAndMenuDeriveCountsFromSamePublishedState() {
        let surface = M3PetSurface()
        let controller = PetController(surface: surface, greetDuration: 60)
        var publishedState: SessionState?
        let host = makeHost(controller: controller, onChange: { publishedState = $0 })

        host.applyForTesting(sessionStarted(summary: "Running"))
        host.applyForTesting(.permissionRequested(
            sessionID: "m3-session",
            timestamp: base.addingTimeInterval(1),
            summary: "Approve"
        ))

        guard let state = publishedState else {
            return XCTFail("Expected a published canonical state")
        }
        let dashboard = SessionDashboardProjection(state: state, activePetName: "Pixel", now: base)
        let menu = SessionMenuSummary.derive(from: state)

        XCTAssertEqual(dashboard.totalCount, menu.activeCount)
        XCTAssertEqual(dashboard.attentionCount, menu.attentionCount)
        XCTAssertEqual(dashboard.totalCount, 1)
        XCTAssertEqual(dashboard.attentionCount, 1)
    }

    private func makeHost(
        controller: PetController,
        liveSessionProvider: @escaping @Sendable (SessionState) async -> Set<String> = { _ in [] },
        onChange: @escaping @MainActor (SessionState) -> Void = { _ in }
    ) -> BridgeServerHost {
        BridgeServerHost(
            petController: controller,
            liveSessionProvider: liveSessionProvider,
            activeSessionProvider: { [] },
            livenessInterval: 60,
            terminalJumpResolver: TerminalJumpTargetResolver(
                ghosttySnapshots: { [] },
                terminalSnapshots: { [] }
            ),
            onSessionStateChange: onChange
        )
    }

    private func sessionStarted(summary: String) -> AgentEvent {
        .sessionStarted(
            sessionID: "m3-session",
            timestamp: base,
            title: "VibePet",
            tool: .claudeCode,
            summary: summary,
            jumpTarget: nil
        )
    }

    private func questionEnvelope() -> BridgeEnvelope {
        BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(
                tool: .claudeCode,
                projectName: "VibePet",
                sessionID: "m3-session",
                sessionShortId: "m3",
                cwd: "/tmp/VibePet"
            ),
            content: .question(QuestionContent(
                title: "Choose",
                questions: [QuestionItem(
                    header: "Choice",
                    prompt: "Continue?",
                    options: [QuestionOption(label: "Yes", detail: nil, allowsFreeform: false)],
                    multiSelect: false
                )]
            ))
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition not met within \(timeout)s")
    }
}

@MainActor
private final class M3PetSurface: PetSurface {
    var petFrame: CGRect? = CGRect(x: 800, y: 0, width: 120, height: 120)
    var visibleFrame = CGRect(x: 0, y: 0, width: 1_000, height: 800)
    var selectedDashboardSessionID: String?
    var selectedDashboardJumpTarget: JumpTarget?
    private(set) var questionContext: QuestionConversationContext?
    private var questionAnswer: ((BridgeResponse) -> Void)?

    func renderPet(asset: PetAsset?, activity: PetActivity) {}
    func showPetSwitchTooltip(name: String) {}
    func updateDashboardContent() {}
    func dismissBubble() {}

    func presentBubble(
        content: BubbleContent,
        source: SourceInfo,
        placement: BubbleAnchor.Placement,
        onJump: @escaping (JumpTarget) -> Void,
        onDismiss: @escaping () -> Void
    ) {}

    func presentApproval(
        content: ApprovalContent,
        source: SourceInfo,
        placement: BubbleAnchor.Placement,
        pendingCount: Int,
        onJump: @escaping (JumpTarget) -> Void,
        onDecision: @escaping (BridgeResponse) -> Void
    ) {}

    func presentQuestion(
        content: QuestionContent,
        source: SourceInfo,
        conversationContext: QuestionConversationContext?,
        placement: BubbleAnchor.Placement,
        pendingCount: Int,
        onJump: @escaping (JumpTarget) -> Void,
        onAnswer: @escaping (BridgeResponse) -> Void
    ) {
        questionContext = conversationContext
        questionAnswer = onAnswer
    }

    func updatePendingCount(_ count: Int) {}
    func dismissApproval() {}
    func updateNotificationBadge(_ count: Int) {}

    func answerQuestion(_ response: BridgeResponse) {
        questionAnswer?(response)
    }
}

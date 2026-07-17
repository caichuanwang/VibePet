import XCTest
@testable import VibePetApp
@testable import VibePetCore

@MainActor
final class M1DecisionLifecycleTests: XCTestCase {
    func testDecisionTimeoutFailsOpenAndLateClickDoesNotResumeAgain() async throws {
        let surface = M1PetSurface()
        let controller = PetController(surface: surface, decisionTimeoutProvider: { _ in 0.03 })
        let task = Task { await controller.requestDecision(for: approvalEnvelope()) }
        try await waitUntil { surface.presentedApprovalCount == 1 }
        let lateDecision = surface.decisionHandler

        let response = await task.value
        XCTAssertEqual(response, .defer)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.pendingDecisionCount, 0)

        lateDecision?(.approval(.allowOnce))
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(controller.pendingDecisionCount, 0)
        XCTAssertEqual(controller.state, .idle)
    }

    func testHostDecisionTimeoutClearsCanonicalActionableStateAndUI() async throws {
        let root = try M1AppTemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let surface = M1PetSurface()
        let controller = PetController(surface: surface, decisionTimeoutProvider: { _ in 0.15 })
        let host = BridgeServerHost(petController: controller, socketPath: socketPath)
        host.start()
        defer { host.stop() }
        try await waitUntil { BridgeSocketIO.canConnect(to: socketPath.socketURL.path) }
        let envelope = approvalEnvelope()
        let responseTask = Task.detached {
            let client = try BridgeSocketIO.connect(to: socketPath.socketURL.path, timeout: 1)
            defer { BridgeSocketIO.close(client) }
            try BridgeSocketIO.writeLine(JSONEncoder().encode(envelope), to: client)
            let data = try BridgeSocketIO.readLine(from: client, absoluteTimeout: 1)
            return try JSONDecoder().decode(BridgeResponseEnvelope.self, from: data)
        }
        try await waitUntil {
            host.sessionStateSnapshot.sessionsByID[envelope.source.sessionID]?.phase == .waitingForApproval
                && surface.presentedApprovalCount == 1
        }

        let response = try await responseTask.value
        try await waitUntil {
            host.sessionStateSnapshot.sessionsByID[envelope.source.sessionID]?.phase == .running
                && controller.pendingDecisionCount == 0
        }

        XCTAssertEqual(response.requestId, envelope.requestId)
        XCTAssertEqual(response.response, .defer)
        XCTAssertGreaterThan(surface.approvalDismissCount, 0)
        XCTAssertEqual(surface.notificationBadge, 0)
    }

    func testSameSessionSecondDecisionKeepsCanonicalStateActionableAfterFirstResolves() async throws {
        let root = try M1AppTemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let surface = M1PetSurface()
        let controller = PetController(surface: surface, decisionTimeoutProvider: { _ in 5 })
        let host = BridgeServerHost(petController: controller, socketPath: socketPath)
        host.start()
        defer { host.stop() }
        try await waitUntil { BridgeSocketIO.canConnect(to: socketPath.socketURL.path) }
        let first = approvalEnvelope(command: "first")
        let second = approvalEnvelope(command: "second")
        let firstTask = sendDecision(first, to: socketPath)
        try await waitUntil { surface.presentedApprovalCount == 1 }
        let secondTask = sendDecision(second, to: socketPath)
        try await waitUntil { controller.pendingDecisionCount == 1 }

        surface.fireDecision(.approval(.allowOnce))
        let firstResponse = try await firstTask.value
        XCTAssertEqual(firstResponse.response, .approval(.allowOnce))
        try await waitUntil {
            surface.presentedApprovalCount == 2
                && host.sessionStateSnapshot.sessionsByID[first.source.sessionID]?.phase == .waitingForApproval
        }

        surface.fireDecision(.approval(.allowOnce))
        let secondResponse = try await secondTask.value
        XCTAssertEqual(secondResponse.response, .approval(.allowOnce))
        try await waitUntil {
            host.sessionStateSnapshot.sessionsByID[first.source.sessionID]?.phase == .running
        }
    }

    func testNativeSessionEndFailsOpenAllPendingDecisionsForSession() async throws {
        let root = try M1AppTemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let surface = M1PetSurface()
        let controller = PetController(surface: surface, decisionTimeoutProvider: { _ in 5 })
        let host = BridgeServerHost(petController: controller, socketPath: socketPath)
        host.start()
        defer { host.stop() }
        try await waitUntil { BridgeSocketIO.canConnect(to: socketPath.socketURL.path) }
        let first = approvalEnvelope(command: "first")
        let second = approvalEnvelope(command: "second")
        let firstTask = sendDecision(first, to: socketPath)
        try await waitUntil { surface.presentedApprovalCount == 1 }
        let secondTask = sendDecision(second, to: socketPath)
        try await waitUntil { controller.pendingDecisionCount == 1 }
        let endedAt = Date()
        let sessionEnd = BridgeEnvelope(
            requestId: UUID(),
            source: first.source,
            content: .completion(CompletionContent(markdownSummary: "Session ended", isError: false)),
            agentEvent: .sessionCompleted(
                sessionID: first.source.sessionID,
                timestamp: endedAt,
                summary: "Session ended",
                isError: false,
                isSessionEnd: true
            )
        )

        try await BridgeClient(socketPath: socketPath).sendOneWay(sessionEnd)

        let firstResponse = try await firstTask.value
        let secondResponse = try await secondTask.value
        XCTAssertEqual(firstResponse.response, .defer)
        XCTAssertEqual(secondResponse.response, .defer)
        try await waitUntil {
            let session = host.sessionStateSnapshot.sessionsByID[first.source.sessionID]
            return controller.pendingDecisionCount == 0
                && session?.phase == .completed
                && session?.isSessionEnded == true
        }
        XCTAssertGreaterThan(surface.approvalDismissCount, 0)
        XCTAssertEqual(surface.notificationBadge, 0)
    }

    func testDecisionArrivingAfterNativeSessionEndFailsOpenWithoutPresentation() async throws {
        let root = try M1AppTemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let surface = M1PetSurface()
        let controller = PetController(surface: surface, decisionTimeoutProvider: { _ in 0.1 })
        let host = BridgeServerHost(petController: controller, socketPath: socketPath)
        host.start()
        defer { host.stop() }
        try await waitUntil { BridgeSocketIO.canConnect(to: socketPath.socketURL.path) }
        let lateDecision = approvalEnvelope(command: "late")
        let sessionEnd = BridgeEnvelope(
            requestId: UUID(),
            source: lateDecision.source,
            content: .completion(CompletionContent(markdownSummary: "Session ended", isError: false)),
            agentEvent: .sessionCompleted(
                sessionID: lateDecision.source.sessionID,
                timestamp: .now,
                summary: "Session ended",
                isError: false,
                isSessionEnd: true
            )
        )
        try await BridgeClient(socketPath: socketPath).sendOneWay(sessionEnd)
        try await waitUntil {
            host.sessionStateSnapshot.sessionsByID[lateDecision.source.sessionID]?.isSessionEnded == true
        }
        await host.runLivenessSweepOnce()
        XCTAssertNil(host.sessionStateSnapshot.sessionsByID[lateDecision.source.sessionID])

        let response = try await sendDecision(lateDecision, to: socketPath).value

        XCTAssertEqual(response.response, .defer)
        XCTAssertEqual(surface.presentedApprovalCount, 0)
        XCTAssertEqual(controller.pendingDecisionCount, 0)
        XCTAssertNil(host.sessionStateSnapshot.sessionsByID[lateDecision.source.sessionID])
    }

    func testCancellingNonFrontDecisionPreservesFrontAndFIFO() async throws {
        let surface = M1PetSurface()
        let controller = PetController(surface: surface, decisionTimeoutProvider: { _ in 5 })
        let first = approvalEnvelope(command: "A")
        let second = approvalEnvelope(command: "B")
        let firstTask = Task { await controller.requestDecision(for: first) }
        try await waitUntil { surface.presentedApprovalCount == 1 }
        let secondTask = Task { await controller.requestDecision(for: second) }
        try await waitUntil { controller.pendingDecisionCount == 1 }

        controller.cancelDecision(requestId: second.requestId)
        let secondResponse = await secondTask.value
        XCTAssertEqual(secondResponse, .defer)
        XCTAssertEqual(controller.pendingDecisionCount, 0)
        XCTAssertEqual(surface.presentedApprovalCount, 1)

        surface.fireDecision(.approval(.allowOnce))
        let firstResponse = await firstTask.value
        XCTAssertEqual(firstResponse, .approval(.allowOnce))
    }

    func testCancelAllDecisionsFailsOpenEveryContinuation() async throws {
        let surface = M1PetSurface()
        let controller = PetController(surface: surface, decisionTimeoutProvider: { _ in 5 })
        let firstTask = Task { await controller.requestDecision(for: approvalEnvelope(command: "A")) }
        try await waitUntil { surface.presentedApprovalCount == 1 }
        let secondTask = Task { await controller.requestDecision(for: approvalEnvelope(command: "B")) }
        try await waitUntil { controller.pendingDecisionCount == 1 }

        controller.cancelAllDecisions()

        let firstResponse = await firstTask.value
        let secondResponse = await secondTask.value
        XCTAssertEqual(firstResponse, .defer)
        XCTAssertEqual(secondResponse, .defer)
        XCTAssertEqual(controller.pendingDecisionCount, 0)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(surface.notificationBadge, 0)
    }

    func testDuplicateRequestIDDefersDuplicateWithoutStealingFirstTimeoutOrCallback() async throws {
        let surface = M1PetSurface()
        let controller = PetController(surface: surface, decisionTimeoutProvider: { _ in 5 })
        let envelope = approvalEnvelope()
        let firstTask = Task { await controller.requestDecision(for: envelope) }
        try await waitUntil { surface.presentedApprovalCount == 1 }
        let firstCallback = surface.decisionHandler

        let duplicate = await controller.requestDecision(for: envelope)
        XCTAssertEqual(duplicate, .defer)
        XCTAssertEqual(controller.pendingDecisionCount, 0)
        XCTAssertEqual(surface.presentedApprovalCount, 1)

        firstCallback?(.approval(.allowOnce))
        let firstResponse = await firstTask.value
        XCTAssertEqual(firstResponse, .approval(.allowOnce))
        firstCallback?(.approval(.deny(reason: "late")))
        XCTAssertEqual(controller.state, .idle)
    }

    func testPeerDisconnectCancelsHostDecisionAndClearsActionableState() async throws {
        let root = try M1AppTemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let surface = M1PetSurface()
        let controller = PetController(surface: surface, decisionTimeoutProvider: { _ in 5 })
        let host = BridgeServerHost(petController: controller, socketPath: socketPath)
        host.start()
        defer { host.stop() }
        try await waitUntil { BridgeSocketIO.canConnect(to: socketPath.socketURL.path) }
        let envelope = approvalEnvelope()
        let client = try BridgeSocketIO.connect(to: socketPath.socketURL.path, timeout: 1)
        defer { BridgeSocketIO.close(client) }
        try BridgeSocketIO.writeLine(JSONEncoder().encode(envelope), to: client)
        try await waitUntil {
            host.sessionStateSnapshot.sessionsByID[envelope.source.sessionID]?.phase == .waitingForApproval
                && surface.presentedApprovalCount == 1
        }

        BridgeSocketIO.shutdown(client)

        try await waitUntil {
            let session = host.sessionStateSnapshot.sessionsByID[envelope.source.sessionID]
            return controller.pendingDecisionCount == 0 && session?.phase != .waitingForApproval
        }
        XCTAssertTrue(surface.presentedApprovalCount == 0 || surface.approvalDismissCount > 0)
    }

    func testHostStopFailsOpenPendingDecisionAndDoesNotPublishAfterStop() async throws {
        let root = try M1AppTemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let surface = M1PetSurface()
        let controller = PetController(surface: surface, decisionTimeoutProvider: { _ in 5 })
        var publishCount = 0
        let host = BridgeServerHost(
            petController: controller,
            socketPath: socketPath,
            onSessionStateChange: { _ in publishCount += 1 }
        )
        host.start()
        try await waitUntil { BridgeSocketIO.canConnect(to: socketPath.socketURL.path) }
        let envelope = approvalEnvelope()
        let task = Task.detached {
            do {
                let response = try await BridgeClient(
                    socketPath: socketPath,
                    readTimeout: 1
                ).send(envelope)
                return response.response == .defer
            } catch {
                return true
            }
        }
        try await waitUntil {
            host.sessionStateSnapshot.sessionsByID[envelope.source.sessionID]?.phase == .waitingForApproval
                && surface.presentedApprovalCount == 1
        }

        host.stop()
        let countAfterStop = publishCount
        let didFailOpen = await task.value
        XCTAssertTrue(didFailOpen)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(controller.pendingDecisionCount, 0)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNotEqual(
            host.sessionStateSnapshot.sessionsByID[envelope.source.sessionID]?.phase,
            .waitingForApproval
        )
        XCTAssertEqual(publishCount, countAfterStop)
    }

    func testHostStopCancelsInitialLivenessSweepBeforeSlowProviderReturns() async throws {
        let root = try M1AppTemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let surface = M1PetSurface()
        let controller = PetController(surface: surface)
        let gate = M1ActiveSessionGate()
        var publishCount = 0
        let host = BridgeServerHost(
            petController: controller,
            socketPath: socketPath,
            liveSessionProvider: { state in Set(state.sessionsByID.keys) },
            activeSessionProvider: { await gate.wait() },
            livenessInterval: 60,
            terminalJumpResolver: TerminalJumpTargetResolver(
                ghosttySnapshots: { [] },
                terminalSnapshots: { [] }
            ),
            onSessionStateChange: { _ in publishCount += 1 }
        )
        let discovered = ActiveAgentSession(
            id: "discovered-codex-stop",
            title: "Stopped",
            tool: .codex,
            summary: "Must not be imported",
            jumpTarget: nil
        )

        host.start()
        try await waitUntilAsync { await gate.hasWaiter }
        host.stop()
        await gate.release(with: [discovered])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(host.sessionStateSnapshot.sessionsByID[discovered.id])
        XCTAssertEqual(publishCount, 0)
    }

    func testHostStopBeforeInitialSweepRunsDoesNotInvokeProvider() async throws {
        let root = try M1AppTemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let counter = M1InvocationCounter()
        let host = BridgeServerHost(
            petController: PetController(surface: M1PetSurface()),
            socketPath: socketPath,
            activeSessionProvider: {
                await counter.increment()
                return []
            },
            livenessInterval: 60,
            terminalJumpResolver: TerminalJumpTargetResolver(
                ghosttySnapshots: { [] },
                terminalSnapshots: { [] }
            )
        )

        host.start()
        host.stop()
        try await Task.sleep(nanoseconds: 50_000_000)

        let invocationCount = await counter.value
        XCTAssertEqual(invocationCount, 0)
    }

    func testLivenessSweepDoesNotApplyStaleMissToSessionUpdatedDuringProviderAwait() async throws {
        let gate = M1LiveSessionGate()
        let host = BridgeServerHost(
            petController: PetController(surface: M1PetSurface()),
            liveSessionProvider: { state in await gate.wait(with: state) },
            activeSessionProvider: { [] },
            livenessInterval: 60,
            terminalJumpResolver: TerminalJumpTargetResolver(
                ghosttySnapshots: { [] },
                terminalSnapshots: { [] }
            )
        )
        let startedAt = Date()
        host.applyForTesting(.sessionStarted(
            sessionID: "liveness-race",
            timestamp: startedAt,
            title: "VibePet",
            tool: .codex,
            summary: "started",
            jumpTarget: nil
        ))
        let sweep = Task { await host.runLivenessSweepOnce() }
        try await waitUntilAsync { await gate.hasWaiter }

        host.applyForTesting(.activityUpdated(
            sessionID: "liveness-race",
            timestamp: startedAt.addingTimeInterval(1),
            summary: "still active"
        ))
        await gate.release(with: [])
        await sweep.value

        let session = host.sessionStateSnapshot.sessionsByID["liveness-race"]
        XCTAssertEqual(session?.summary, "still active")
        XCTAssertEqual(session?.processNotSeenCount, 0)
        XCTAssertEqual(session?.isProcessAlive, true)
    }

    private func approvalEnvelope(command: String = "swift test") -> BridgeEnvelope {
        BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(
                tool: .claudeCode,
                projectName: "VibePet",
                sessionID: "m1-session",
                sessionShortId: "m1",
                cwd: "/tmp/VibePet"
            ),
            content: .approval(ApprovalContent(
                title: "运行命令",
                risk: .medium,
                preview: .command(text: command),
                alwaysAllow: nil,
                requiresTerminalApproval: false
            ))
        )
    }

    private func sendDecision(
        _ envelope: BridgeEnvelope,
        to socketPath: SocketPath
    ) -> Task<BridgeResponseEnvelope, Error> {
        Task.detached {
            let client = try BridgeSocketIO.connect(to: socketPath.socketURL.path, timeout: 1)
            defer { BridgeSocketIO.close(client) }
            try BridgeSocketIO.writeLine(JSONEncoder().encode(envelope), to: client)
            let data = try BridgeSocketIO.readLine(from: client, absoluteTimeout: 1)
            return try JSONDecoder().decode(BridgeResponseEnvelope.self, from: data)
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition not met within \(timeout)s")
    }

    private func waitUntilAsync(
        timeout: TimeInterval = 2,
        _ condition: () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition not met within \(timeout)s")
    }
}

@MainActor
private final class M1PetSurface: PetSurface {
    var petFrame: CGRect? = CGRect(x: 800, y: 0, width: 120, height: 120)
    var visibleFrame = CGRect(x: 0, y: 0, width: 1_000, height: 800)
    var selectedDashboardSessionID: String?
    var selectedDashboardJumpTarget: JumpTarget?
    private(set) var presentedApprovalCount = 0
    private(set) var approvalDismissCount = 0
    private(set) var notificationBadge = 0
    private(set) var decisionHandler: ((BridgeResponse) -> Void)?

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
    ) {
        presentedApprovalCount += 1
        decisionHandler = onDecision
    }

    func presentQuestion(
        content: QuestionContent,
        source: SourceInfo,
        conversationContext: QuestionConversationContext?,
        placement: BubbleAnchor.Placement,
        pendingCount: Int,
        onJump: @escaping (JumpTarget) -> Void,
        onAnswer: @escaping (BridgeResponse) -> Void
    ) {
        decisionHandler = onAnswer
    }

    func updatePendingCount(_ count: Int) {}

    func dismissApproval() {
        approvalDismissCount += 1
    }

    func updateNotificationBadge(_ count: Int) {
        notificationBadge = count
    }

    func fireDecision(_ response: BridgeResponse) {
        decisionHandler?(response)
    }
}

private final class M1AppTemporaryDirectory {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vp-m1-app-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private actor M1ActiveSessionGate {
    private(set) var hasWaiter = false
    private var continuation: CheckedContinuation<[ActiveAgentSession], Never>?

    func wait() async -> [ActiveAgentSession] {
        hasWaiter = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func release(with sessions: [ActiveAgentSession]) {
        continuation?.resume(returning: sessions)
        continuation = nil
    }
}

private actor M1LiveSessionGate {
    private(set) var hasWaiter = false
    private var continuation: CheckedContinuation<Set<String>, Never>?

    func wait(with state: SessionState) async -> Set<String> {
        hasWaiter = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func release(with sessionIDs: Set<String>) {
        continuation?.resume(returning: sessionIDs)
        continuation = nil
    }
}

private actor M1InvocationCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

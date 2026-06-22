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

    func testSessionSyncDoesNotDismissVisibleNotificationBubble() {
        let surface = FakePetSurface()
        let controller = PetController(surface: surface)
        let state = SessionState()

        controller.handle(completionEnvelope())
        controller.sync(with: state)

        XCTAssertEqual(controller.state, .notify)
        XCTAssertEqual(surface.dismissCount, 0, "session sync must not dismiss a controller-owned bubble")
        XCTAssertEqual(surface.presentedBubbles.count, 1)
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

    func testSessionStartUpdatesStateAndGreetsWithoutBubble() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let surface = FakePetSurface()
        let controller = PetController(surface: surface, greetDuration: 10)
        let host = BridgeServerHost(petController: controller, socketPath: socketPath)

        host.start()
        defer { host.stop() }
        try await waitUntil { BridgeSocketIO.canConnect(to: socketPath.socketURL.path) }

        let client = BridgeClient(socketPath: socketPath)
        try await client.sendOneWay(sessionStartEnvelope())

        try await waitUntil { host.sessionStateSnapshot.sessionsByID["session-full"] != nil }
        XCTAssertEqual(host.sessionStateSnapshot.sessionsByID["session-full"]?.phase, .running)
        XCTAssertEqual(surface.lastActivity, .greeting)
        XCTAssertTrue(surface.presentedBubbles.isEmpty, "SessionStart is state, not a user-facing bubble")
    }

    // MARK: - Approval (decide) — M4-5 / M4-6

    func testApprovalEntersDecideAndPresentsCard() async throws {
        let surface = FakePetSurface()
        let controller = PetController(surface: surface, decisionTimeout: 10)

        let task = Task { await controller.requestDecision(for: approvalEnvelope()) }
        try await waitUntil { surface.presentedApprovals.count == 1 }

        XCTAssertEqual(controller.state, .decide)
        XCTAssertEqual(surface.lastActivity, .deciding)

        surface.fireDecision(.approval(.allowOnce))
        _ = await task.value
    }

    func testDenyResolvesWithPairedDenyAndReturnsToIdle() async throws {
        let surface = FakePetSurface()
        let controller = PetController(surface: surface, decisionTimeout: 10)

        let task = Task { await controller.requestDecision(for: approvalEnvelope()) }
        try await waitUntil { surface.presentedApprovals.count == 1 }
        surface.fireDecision(.approval(.deny(reason: "no")))

        let response = await task.value
        XCTAssertEqual(response, .approval(.deny(reason: "no")))
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(surface.approvalDismissCount, 1)
    }

    func testAllowOnceResolves() async throws {
        let surface = FakePetSurface()
        let controller = PetController(surface: surface, decisionTimeout: 10)

        let task = Task { await controller.requestDecision(for: approvalEnvelope()) }
        try await waitUntil { surface.presentedApprovals.count == 1 }
        surface.fireDecision(.approval(.allowOnce))

        let response = await task.value
        XCTAssertEqual(response, .approval(.allowOnce))
    }

    func testUnansweredApprovalTimesOutToDefer() async {
        let surface = FakePetSurface()
        let controller = PetController(surface: surface, decisionTimeout: 0.05)

        let response = await controller.requestDecision(for: approvalEnvelope())

        XCTAssertEqual(response, .defer)
        XCTAssertEqual(controller.state, .idle)
    }

    func testHiddenPetFailsOpen() async {
        let surface = FakePetSurface()
        surface.petFrame = nil
        let controller = PetController(surface: surface)

        let response = await controller.requestDecision(for: approvalEnvelope())

        XCTAssertEqual(response, .defer)
        XCTAssertTrue(surface.presentedApprovals.isEmpty)
    }

    func testConcurrentApprovalsQueueFIFOAndPairIndependently() async throws {
        let surface = FakePetSurface()
        let controller = PetController(surface: surface, decisionTimeout: 10)
        let envA = approvalEnvelope(command: "A")
        let envB = approvalEnvelope(command: "B")

        let taskA = Task { await controller.requestDecision(for: envA) }
        try await waitUntil { surface.presentedApprovals.count == 1 }

        let taskB = Task { await controller.requestDecision(for: envB) }
        try await waitUntil { controller.pendingDecisionCount == 1 }
        XCTAssertEqual(surface.lastPendingCount, 1, "queued approval bumps the pending badge")

        // Resolve A; B should then present.
        surface.fireDecision(.approval(.allowOnce))
        let responseA = await taskA.value
        XCTAssertEqual(responseA, .approval(.allowOnce))

        try await waitUntil { surface.presentedApprovals.count == 2 }
        surface.fireDecision(.approval(.deny(reason: nil)))
        let responseB = await taskB.value
        XCTAssertEqual(responseB, .approval(.deny(reason: nil)))
        XCTAssertEqual(controller.state, .idle)
    }

    func testNotificationDuringDecideDoesNotClobberApproval() async throws {
        let surface = FakePetSurface()
        let controller = PetController(surface: surface, decisionTimeout: 10)

        let task = Task { await controller.requestDecision(for: approvalEnvelope()) }
        try await waitUntil { surface.presentedApprovals.count == 1 }

        controller.handle(completionEnvelope()) // notification arrives mid-decision
        controller.handle(completionEnvelope()) // and another

        XCTAssertTrue(surface.presentedBubbles.isEmpty, "decide has priority over notify")
        XCTAssertEqual(surface.notificationBadge, 2, "deferred notifications accumulate a badge")
        XCTAssertEqual(controller.state, .decide)

        surface.fireDecision(.approval(.allowOnce))
        _ = await task.value
        XCTAssertEqual(surface.notificationBadge, 0, "badge clears once the queue drains")
    }

    func testGreetingDoesNotClobberDecision() async throws {
        let surface = FakePetSurface()
        let controller = PetController(surface: surface, decisionTimeout: 10)

        let task = Task { await controller.requestDecision(for: approvalEnvelope()) }
        try await waitUntil { surface.presentedApprovals.count == 1 }

        XCTAssertFalse(controller.greet(), "greet should not preempt decide")
        XCTAssertEqual(controller.state, .decide)
        XCTAssertEqual(surface.lastActivity, .deciding)

        surface.fireDecision(.approval(.allowOnce))
        _ = await task.value
    }

    func testApprovalRoundTripPairsRequestIdViaHost() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let surface = FakePetSurface()
        let controller = PetController(surface: surface, decisionTimeout: 10)
        let host = BridgeServerHost(petController: controller, socketPath: socketPath)

        host.start()
        defer { host.stop() }
        try await waitUntil { BridgeSocketIO.canConnect(to: socketPath.socketURL.path) }

        let envelope = approvalEnvelope()
        let client = BridgeClient(socketPath: socketPath, readTimeout: 5)
        async let responseEnv = client.send(envelope)

        try await waitUntil { surface.presentedApprovals.count == 1 }
        XCTAssertEqual(host.sessionStateSnapshot.sessionsByID[envelope.source.sessionID]?.phase, .waitingForApproval)
        surface.fireDecision(.approval(.deny(reason: "blocked")))

        let result = try await responseEnv
        XCTAssertEqual(result.requestId, envelope.requestId, "response must pair the request by id")
        XCTAssertEqual(result.response, .approval(.deny(reason: "blocked")))
        XCTAssertEqual(host.sessionStateSnapshot.sessionsByID[envelope.source.sessionID]?.phase, .completed)
    }

    func testApprovalTimeoutRepliesDeferAndReturnsSessionToRunning() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let surface = FakePetSurface()
        let controller = PetController(surface: surface, decisionTimeout: 0.05)
        let host = BridgeServerHost(petController: controller, socketPath: socketPath)

        host.start()
        defer { host.stop() }
        try await waitUntil { BridgeSocketIO.canConnect(to: socketPath.socketURL.path) }

        let envelope = approvalEnvelope()
        let result = try await BridgeClient(socketPath: socketPath, readTimeout: 2).send(envelope)

        XCTAssertEqual(result.requestId, envelope.requestId)
        XCTAssertEqual(result.response, .defer)
        XCTAssertEqual(host.sessionStateSnapshot.sessionsByID[envelope.source.sessionID]?.phase, .running)
    }

    func testLivenessSweepReapsSessionAfterTwoMisses() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let surface = FakePetSurface()
        let controller = PetController(surface: surface, greetDuration: 10)
        let host = BridgeServerHost(
            petController: controller,
            socketPath: socketPath,
            liveSessionProvider: { _ in [] },
            livenessInterval: 60
        )

        host.start()
        defer { host.stop() }
        try await waitUntil { BridgeSocketIO.canConnect(to: socketPath.socketURL.path) }

        try await BridgeClient(socketPath: socketPath).sendOneWay(sessionStartEnvelope())
        try await waitUntil { host.sessionStateSnapshot.sessionsByID["session-full"] != nil }

        await host.runLivenessSweepOnce()
        XCTAssertEqual(host.sessionStateSnapshot.sessionsByID["session-full"]?.processNotSeenCount, 1)

        await host.runLivenessSweepOnce()
        let session = host.sessionStateSnapshot.sessionsByID["session-full"]
        XCTAssertNil(session, "reaped sessions should be evicted after the sweep")
        XCTAssertFalse(host.sessionStateSnapshot.visibleSessions.contains { $0.id == "session-full" })
    }

    func testProcessLivenessMatchesTTYInsteadOfToolWideCommandSubstring() {
        var state = SessionState()
        state.apply(.sessionStarted(
            sessionID: "codex-a",
            timestamp: Date(),
            title: "Codex A",
            tool: .codex,
            summary: "Started",
            jumpTarget: JumpTarget(terminalApp: "Terminal", terminalTTY: "/dev/ttys001")
        ))
        state.apply(.sessionStarted(
            sessionID: "codex-b",
            timestamp: Date(),
            title: "Codex B",
            tool: .codex,
            summary: "Started",
            jumpTarget: JumpTarget(terminalApp: "Terminal", terminalTTY: "/dev/ttys002")
        ))

        let alive = AgentProcessLiveness.liveSessionIDs(in: state, rows: [
            AgentProcessLiveness.ProcessRow(tty: "ttys001", command: "/opt/homebrew/bin/codex"),
            AgentProcessLiveness.ProcessRow(tty: "ttys002", command: "/Applications/VibePet.app/Contents/MacOS/VibePetHooks --tool codex"),
        ])

        XCTAssertEqual(alive, ["codex-a"])
    }

    func testProcessLivenessKeepsUnidentifiedSessionsAlive() {
        var state = SessionState()
        state.apply(sessionStartEnvelope().agentEvent!)

        XCTAssertEqual(AgentProcessLiveness.liveSessionIDs(in: state, rows: []), ["session-full"])
    }

    // MARK: - Question (decide) — M5

    func testQuestionEntersDecideAndPresentsCard() async throws {
        let surface = FakePetSurface()
        let controller = PetController(surface: surface, decisionTimeout: 10)

        let task = Task { await controller.requestDecision(for: questionEnvelope()) }
        try await waitUntil { surface.presentedQuestions.count == 1 }

        XCTAssertEqual(controller.state, .decide)
        XCTAssertEqual(surface.lastActivity, .deciding)
        XCTAssertTrue(surface.presentedApprovals.isEmpty, "a question must present a question card, not an approval")

        surface.fireDecision(.question(QuestionAnswer(answers: ["Database": "SQLite"])))
        _ = await task.value
    }

    func testQuestionSubmitResolvesWithPairedAnswer() async throws {
        let surface = FakePetSurface()
        let controller = PetController(surface: surface, decisionTimeout: 10)

        let task = Task { await controller.requestDecision(for: questionEnvelope()) }
        try await waitUntil { surface.presentedQuestions.count == 1 }

        let answer = QuestionAnswer(answers: ["Database": "Postgres"])
        surface.fireDecision(.question(answer))

        let response = await task.value
        XCTAssertEqual(response, .question(answer))
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(surface.approvalDismissCount, 1, "draining the queue dismisses the decide bubble")
    }

    func testUnansweredQuestionTimesOutToDefer() async {
        let surface = FakePetSurface()
        let controller = PetController(surface: surface, decisionTimeout: 0.05)

        let response = await controller.requestDecision(for: questionEnvelope())

        XCTAssertEqual(response, .defer)
        XCTAssertEqual(controller.state, .idle)
    }

    private func questionEnvelope() -> BridgeEnvelope {
        BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .claudeCode, projectName: "VibePet", sessionShortId: "a1b2c3", cwd: "/tmp/VibePet"),
            content: .question(QuestionContent(
                title: "Claude 需要你确认",
                questions: [QuestionItem(
                    header: "Database",
                    prompt: "Which database should we use?",
                    options: [
                        QuestionOption(label: "SQLite", detail: "Lightweight", allowsFreeform: false),
                        QuestionOption(label: "Postgres", detail: nil, allowsFreeform: false),
                    ],
                    multiSelect: false
                )]
            ))
        )
    }

    func testTerminalApprovalResolvesAsDeferOnHandleInTerminal() async throws {
        let surface = FakePetSurface()
        let controller = PetController(surface: surface, decisionTimeout: 10)

        let task = Task { await controller.requestDecision(for: terminalApprovalEnvelope()) }
        try await waitUntil { surface.presentedApprovals.count == 1 }
        XCTAssertEqual(surface.presentedApprovals.first?.content.requiresTerminalApproval, true)

        // The "回终端处理" affordance resolves as a defer (handle natively in terminal).
        surface.fireDecision(.defer)

        let response = await task.value
        XCTAssertEqual(response, .defer)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(surface.approvalDismissCount, 1)
    }

    private func terminalApprovalEnvelope() -> BridgeEnvelope {
        BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .codex, projectName: "VibePet", sessionShortId: "9f8e7d", cwd: "/tmp/VibePet"),
            content: .approval(ApprovalContent(
                title: "需在终端处理",
                risk: .medium,
                preview: .generic(summary: "Pick a deployment target"),
                alwaysAllow: nil,
                requiresTerminalApproval: true
            ))
        )
    }

    private func approvalEnvelope(command: String = "swift test") -> BridgeEnvelope {
        BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .claudeCode, projectName: "VibePet", sessionShortId: "a1b2c3", cwd: "/tmp/VibePet"),
            content: .approval(ApprovalContent(
                title: "运行命令",
                risk: .medium,
                preview: .command(text: command),
                alwaysAllow: nil,
                requiresTerminalApproval: false
            ))
        )
    }

    // MARK: - Codex hook trust activation — M6-5a

    func testCodexEventMarksHookTrustActive() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let store = InstallManifestStore(applicationSupportRoot: root.url)
        var manifest = InstallManifest(hookBinaryVersion: VibePetCore.hookBinaryVersion)
        manifest.tools[ToolKind.codex.rawValue] = ToolInstallRecord(
            installed: true,
            activationState: .installedNeedsTrust,
            settingsPath: "~/.codex/config.toml",
            writtenHooks: ["PermissionRequest", "Stop"],
            backupPath: nil
        )
        try store.write(manifest)

        let surface = FakePetSurface()
        let controller = PetController(surface: surface)
        let host = BridgeServerHost(petController: controller, socketPath: socketPath, manifestStore: store)
        host.start()
        defer { host.stop() }
        try await waitUntil { BridgeSocketIO.canConnect(to: socketPath.socketURL.path) }

        let client = BridgeClient(socketPath: socketPath)
        try await client.sendOneWay(codexCompletionEnvelope())

        try await waitUntil { store.read().tools[ToolKind.codex.rawValue]?.activationState == .trustedActive }
    }

    func testCodexNotifyCompletionCanRekeyByThreadID() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let surface = FakePetSurface()
        let controller = PetController(surface: surface, greetDuration: 10)
        let host = BridgeServerHost(petController: controller, socketPath: socketPath)
        host.start()
        defer { host.stop() }
        try await waitUntil { BridgeSocketIO.canConnect(to: socketPath.socketURL.path) }

        let client = BridgeClient(socketPath: socketPath)
        try await client.sendOneWay(codexSessionStartEnvelope())
        try await waitUntil { host.sessionStateSnapshot.sessionsByID["codex-session-full"] != nil }

        try await client.sendOneWay(codexThreadCompletionEnvelope())
        try await waitUntil {
            host.sessionStateSnapshot.sessionsByID["codex-session-full"]?.phase == .completed
        }

        XCTAssertNil(host.sessionStateSnapshot.sessionsByID["codex-thread-1"])
        XCTAssertEqual(host.sessionStateSnapshot.sessionsByID["codex-session-full"]?.summary, "Done by notify")
    }

    func testCodexNotifyCompletionCanRekeyByUniqueWorkingDirectory() async throws {
        let root = try TemporaryDirectory()
        let socketPath = SocketPath(applicationSupportRoot: root.url)
        let surface = FakePetSurface()
        let controller = PetController(surface: surface, greetDuration: 10)
        let host = BridgeServerHost(petController: controller, socketPath: socketPath)
        host.start()
        defer { host.stop() }
        try await waitUntil { BridgeSocketIO.canConnect(to: socketPath.socketURL.path) }

        let client = BridgeClient(socketPath: socketPath)
        try await client.sendOneWay(codexSessionStartEnvelope(threadID: nil))
        try await waitUntil { host.sessionStateSnapshot.sessionsByID["codex-session-full"] != nil }

        try await client.sendOneWay(codexThreadCompletionEnvelope(threadID: "notify-thread-only"))
        try await waitUntil {
            host.sessionStateSnapshot.sessionsByID["codex-session-full"]?.phase == .completed
        }

        XCTAssertNil(host.sessionStateSnapshot.sessionsByID["notify-thread-only"])
        XCTAssertEqual(host.sessionStateSnapshot.sessionsByID["codex-session-full"]?.summary, "Done by notify")
    }

    private func codexCompletionEnvelope() -> BridgeEnvelope {
        BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .codex, projectName: "VibePet", sessionShortId: "9f8e7d", cwd: "/tmp/VibePet"),
            content: .completion(CompletionContent(markdownSummary: "Done", isError: false))
        )
    }

    private func codexSessionStartEnvelope(threadID: String? = "codex-thread-1") -> BridgeEnvelope {
        let jumpTarget = JumpTarget(terminalApp: "Codex", workingDirectory: "/tmp/VibePet", codexThreadID: threadID)
        let event = AgentEvent.sessionStarted(
            sessionID: "codex-session-full",
            timestamp: Date(),
            title: "VibePet",
            tool: .codex,
            summary: "Started",
            jumpTarget: jumpTarget
        )
        return BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(
                tool: .codex,
                projectName: "VibePet",
                sessionID: "codex-session-full",
                sessionShortId: "codex-",
                cwd: "/tmp/VibePet",
                jumpTarget: jumpTarget
            ),
            content: .status(StatusContent(text: "Started")),
            agentEvent: event
        )
    }

    private func codexThreadCompletionEnvelope(threadID: String = "codex-thread-1") -> BridgeEnvelope {
        let jumpTarget = JumpTarget(terminalApp: "Codex", workingDirectory: "/tmp/VibePet", codexThreadID: threadID)
        return BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(
                tool: .codex,
                projectName: "VibePet",
                sessionID: threadID,
                sessionShortId: "codex-",
                cwd: "/tmp/VibePet",
                jumpTarget: jumpTarget
            ),
            content: .completion(CompletionContent(markdownSummary: "Done by notify", isError: false)),
            agentEvent: .sessionCompleted(
                sessionID: threadID,
                timestamp: Date(),
                summary: "Done by notify",
                isError: false,
                isSessionEnd: false
            )
        )
    }

    // MARK: - Helpers

    private func completionEnvelope() -> BridgeEnvelope {
        BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .claudeCode, projectName: "VibePet", sessionShortId: "a1b2c3", cwd: "/tmp/VibePet"),
            content: .completion(CompletionContent(markdownSummary: "新增 3 个测试，全部通过", isError: false))
        )
    }

    private func sessionStartEnvelope() -> BridgeEnvelope {
        let event = AgentEvent.sessionStarted(
            sessionID: "session-full",
            timestamp: Date(),
            title: "VibePet",
            tool: .claudeCode,
            summary: "Started",
            jumpTarget: nil
        )
        return BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(
                tool: .claudeCode,
                projectName: "VibePet",
                sessionID: "session-full",
                sessionShortId: "sessio",
                cwd: "/tmp/VibePet"
            ),
            content: .status(StatusContent(text: "Started")),
            agentEvent: event
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

    struct PresentedApproval {
        let content: ApprovalContent
        let source: SourceInfo
        let timeout: TimeInterval
        let pendingCount: Int
    }

    struct PresentedQuestion {
        let content: QuestionContent
        let source: SourceInfo
        let timeout: TimeInterval
        let pendingCount: Int
    }

    var petFrame: CGRect? = CGRect(x: 800, y: 0, width: 120, height: 120)
    var visibleFrame: CGRect = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private(set) var lastActivity: PetActivity?
    private(set) var presentedBubbles: [PresentedBubble] = []
    private(set) var dismissCount = 0
    private var onDismiss: (() -> Void)?

    private(set) var presentedApprovals: [PresentedApproval] = []
    private(set) var presentedQuestions: [PresentedQuestion] = []
    private(set) var approvalDismissCount = 0
    private(set) var lastPendingCount = 0
    private var onDecision: ((BridgeResponse) -> Void)?

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

    func presentApproval(
        content: ApprovalContent,
        source: SourceInfo,
        placement: BubbleAnchor.Placement,
        timeout: TimeInterval,
        pendingCount: Int,
        onDecision: @escaping (BridgeResponse) -> Void
    ) {
        presentedApprovals.append(
            PresentedApproval(content: content, source: source, timeout: timeout, pendingCount: pendingCount)
        )
        lastPendingCount = pendingCount
        self.onDecision = onDecision
    }

    func presentQuestion(
        content: QuestionContent,
        source: SourceInfo,
        placement: BubbleAnchor.Placement,
        timeout: TimeInterval,
        pendingCount: Int,
        onAnswer: @escaping (BridgeResponse) -> Void
    ) {
        presentedQuestions.append(
            PresentedQuestion(content: content, source: source, timeout: timeout, pendingCount: pendingCount)
        )
        lastPendingCount = pendingCount
        self.onDecision = onAnswer
    }

    func updatePendingCount(_ count: Int) {
        lastPendingCount = count
    }

    func dismissApproval() {
        approvalDismissCount += 1
    }

    private(set) var notificationBadge = 0

    func updateNotificationBadge(_ count: Int) {
        notificationBadge = count
    }

    func fireDecision(_ response: BridgeResponse) {
        onDecision?(response)
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

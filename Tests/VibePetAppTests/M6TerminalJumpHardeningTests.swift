import XCTest
@testable import VibePetApp
@testable import VibePetCore

@MainActor
final class M6TerminalJumpHardeningTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testGhosttyEmptySnapshotMetadataDoesNotClearExistingTarget() {
        let resolver = TerminalJumpTargetResolver(
            ghosttySnapshots: {
                [.init(sessionID: "ghostty-new", workingDirectory: "", title: "")]
            },
            terminalSnapshots: { [] }
        )
        let session = makeSession(jumpTarget: JumpTarget(
            terminalApp: "Ghostty",
            workspaceName: "VibePet",
            paneTitle: "Precise title",
            workingDirectory: "/work/VibePet",
            terminalSessionID: "ghostty-new",
            terminalTTY: "/dev/ttys010"
        ))

        let update = resolver.resolveJumpTargets(for: [session])[session.id]

        XCTAssertNil(update, "an exact-ID snapshot with empty metadata must not erase precise fields")
    }

    func testGhosttyAmbiguousWeakSnapshotsDoNotUpdateSession() {
        let resolver = TerminalJumpTargetResolver(
            ghosttySnapshots: {
                [
                    .init(sessionID: "ghostty-a", workingDirectory: "/work/VibePet", title: "Codex"),
                    .init(sessionID: "ghostty-b", workingDirectory: "/work/VibePet", title: "Codex"),
                ]
            },
            terminalSnapshots: { [] }
        )
        let session = makeSession(jumpTarget: JumpTarget(
            terminalApp: "Ghostty",
            workspaceName: "VibePet",
            paneTitle: "Codex",
            workingDirectory: "/work/VibePet"
        ))

        XCTAssertTrue(resolver.resolveJumpTargets(for: [session]).isEmpty)
    }

    func testGhosttyUniqueStandardizedLowercasePathMatches() {
        let resolver = TerminalJumpTargetResolver(
            ghosttySnapshots: {
                [.init(sessionID: "ghostty-path", workingDirectory: "/WORK/./VIBEPET", title: "Codex")]
            },
            terminalSnapshots: { [] }
        )
        let session = makeSession(jumpTarget: JumpTarget(
            terminalApp: "Ghostty",
            workspaceName: "Old",
            paneTitle: nil,
            workingDirectory: "/work/vibepet"
        ))

        let update = resolver.resolveJumpTargets(for: [session])[session.id]

        XCTAssertEqual(update?.terminalSessionID, "ghostty-path")
        XCTAssertEqual(update?.workingDirectory, "/WORK/./VIBEPET")
        XCTAssertEqual(update?.paneTitle, "Codex")
    }

    func testTerminalAmbiguousTitleFallbackDoesNotAssignArbitraryTTY() {
        let resolver = TerminalJumpTargetResolver(
            ghosttySnapshots: { [] },
            terminalSnapshots: {
                [.init(tty: "/dev/ttys099", title: "Shared title")]
            }
        )
        let sessions = ["terminal-a", "terminal-b"].map { id in
            AgentSession(
                id: id,
                title: id,
                tool: .claudeCode,
                phase: .running,
                summary: "Running",
                updatedAt: base,
                jumpTarget: JumpTarget(
                    terminalApp: "Terminal",
                    workspaceName: "VibePet",
                    paneTitle: "Shared title",
                    workingDirectory: "/work/VibePet"
                )
            )
        }

        XCTAssertTrue(resolver.resolveJumpTargets(for: sessions).isEmpty)
    }

    func testNotificationSourceAddsPreciseIDAndTTYThenPartialSourcePreservesThem() async throws {
        let host = makeHost()
        host.start()
        defer { host.stop() }
        let socketPath = hostSocketPath
        try await waitUntil { BridgeSocketIO.canConnect(to: socketPath.socketURL.path) }

        let precise = JumpTarget(
            terminalApp: "Ghostty",
            workspaceName: "VibePet",
            paneTitle: "Codex",
            workingDirectory: "/work/VibePet",
            terminalSessionID: "ghostty-precise",
            terminalTTY: "/dev/ttys011"
        )
        try await sendNotification(sourceTarget: precise, socketPath: socketPath)
        try await waitUntil {
            host.sessionStateSnapshot.sessionsByID["m6-session"]?.jumpTarget?.terminalSessionID == "ghostty-precise"
        }

        let partial = JumpTarget(
            terminalApp: "Unknown",
            workspaceName: "",
            paneTitle: nil,
            workingDirectory: nil,
            terminalSessionID: nil,
            terminalTTY: nil
        )
        try await sendNotification(sourceTarget: partial, socketPath: socketPath)
        try await waitUntil {
            host.sessionStateSnapshot.sessionsByID["m6-session"]?.summary == "partial"
        }

        let target = host.sessionStateSnapshot.sessionsByID["m6-session"]?.jumpTarget
        XCTAssertEqual(target?.terminalApp, "Ghostty")
        XCTAssertEqual(target?.terminalSessionID, "ghostty-precise")
        XCTAssertEqual(target?.terminalTTY, "/dev/ttys011")
        XCTAssertEqual(target?.paneTitle, "Codex")
    }

    func testLaterSourceDoesNotOverwriteExistingPreciseIDAndTTY() async throws {
        let host = makeHost()
        host.start()
        defer { host.stop() }
        let socketPath = hostSocketPath
        try await waitUntil { BridgeSocketIO.canConnect(to: socketPath.socketURL.path) }

        try await sendNotification(sourceTarget: JumpTarget(
            terminalApp: "Ghostty",
            workingDirectory: "/work/VibePet",
            terminalSessionID: "original-session",
            terminalTTY: "/dev/ttys011"
        ), socketPath: socketPath)
        try await waitUntil {
            host.sessionStateSnapshot.sessionsByID["m6-session"]?.jumpTarget?.terminalSessionID == "original-session"
        }

        try await sendNotification(sourceTarget: JumpTarget(
            terminalApp: "Ghostty",
            workingDirectory: "/work/VibePet",
            terminalSessionID: "conflicting-session",
            terminalTTY: "/dev/ttys099"
        ), summary: "conflicting", socketPath: socketPath)
        try await waitUntil {
            host.sessionStateSnapshot.sessionsByID["m6-session"]?.summary == "conflicting"
        }

        let target = host.sessionStateSnapshot.sessionsByID["m6-session"]?.jumpTarget
        XCTAssertEqual(target?.terminalSessionID, "original-session")
        XCTAssertEqual(target?.terminalTTY, "/dev/ttys011")
    }

    func testDecisionSourceMergesPreciseIDAndTTY() async throws {
        let surface = M6PetSurface()
        let controller = PetController(surface: surface, decisionTimeoutProvider: { _ in 5 })
        let host = makeHost(controller: controller)
        host.start()
        defer { host.stop() }
        let socketPath = hostSocketPath
        try await waitUntil { BridgeSocketIO.canConnect(to: socketPath.socketURL.path) }
        let precise = JumpTarget(
            terminalApp: "iTerm",
            workspaceName: "VibePet",
            paneTitle: "Claude",
            workingDirectory: "/work/VibePet",
            terminalSessionID: "iterm-session",
            terminalTTY: "/dev/ttys012"
        )
        let envelope = BridgeEnvelope(
            requestId: UUID(),
            source: source(jumpTarget: precise),
            content: .approval(ApprovalContent(
                title: "Approve",
                risk: .medium,
                preview: .command(text: "echo ok"),
                alwaysAllow: nil,
                requiresTerminalApproval: false
            ))
        )
        let responseTask = Task {
            try await BridgeClient(socketPath: socketPath, readTimeout: 2).send(envelope)
        }
        try await waitUntil { surface.decisionHandler != nil }

        let target = host.sessionStateSnapshot.sessionsByID["m6-session"]?.jumpTarget
        XCTAssertEqual(target?.terminalSessionID, "iterm-session")
        XCTAssertEqual(target?.terminalTTY, "/dev/ttys012")
        surface.decisionHandler?(.defer)
        let response = try await responseTask.value
        XCTAssertEqual(response.response, .defer)
    }

    // Existing TerminalJumpServiceTests already cover iTerm ID before TTY,
    // Terminal TTY before title, and the cmux / VS Code paths. Repeating those
    // service contracts here would not add M6 hardening coverage.

    private var hostSocketPath: SocketPath {
        SocketPath(applicationSupportRoot: supportRootURL)
    }

    private var supportRootURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vp-m6-\(ObjectIdentifier(self).hashValue)", isDirectory: true)
    }

    private func makeHost(controller: PetController? = nil) -> BridgeServerHost {
        let controller = controller ?? PetController(surface: M6PetSurface(), decisionTimeoutProvider: { _ in 5 })
        return BridgeServerHost(
            petController: controller,
            socketPath: hostSocketPath,
            liveSessionProvider: { state in Set(state.sessionsByID.keys) },
            activeSessionProvider: { [] },
            livenessInterval: 60,
            terminalJumpResolver: TerminalJumpTargetResolver(
                ghosttySnapshots: { [] },
                terminalSnapshots: { [] }
            )
        )
    }

    private func sendNotification(
        sourceTarget: JumpTarget,
        summary: String? = nil,
        socketPath: SocketPath
    ) async throws {
        let summary = summary ?? (sourceTarget.terminalApp == "Unknown" ? "partial" : "precise")
        let envelope = BridgeEnvelope(
            requestId: UUID(),
            source: source(jumpTarget: sourceTarget),
            content: .status(StatusContent(text: summary)),
            agentEvent: .activityUpdated(sessionID: "m6-session", timestamp: Date(), summary: summary)
        )
        try await BridgeClient(socketPath: socketPath).sendOneWay(envelope)
    }

    private func source(jumpTarget: JumpTarget) -> SourceInfo {
        SourceInfo(
            tool: .claudeCode,
            projectName: "VibePet",
            sessionID: "m6-session",
            sessionShortId: "m6",
            cwd: "/work/VibePet",
            jumpTarget: jumpTarget
        )
    }

    private func makeSession(jumpTarget: JumpTarget) -> AgentSession {
        AgentSession(
            id: "m6-session",
            title: "VibePet",
            tool: .claudeCode,
            phase: .running,
            summary: "Running",
            updatedAt: base,
            jumpTarget: jumpTarget
        )
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
}

@MainActor
private final class M6PetSurface: PetSurface {
    var petFrame: CGRect? = CGRect(x: 800, y: 0, width: 120, height: 120)
    var visibleFrame = CGRect(x: 0, y: 0, width: 1_000, height: 800)
    var selectedDashboardSessionID: String?
    var selectedDashboardJumpTarget: JumpTarget?
    var decisionHandler: ((BridgeResponse) -> Void)?

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
    func dismissApproval() {}
    func updateNotificationBadge(_ count: Int) {}
}

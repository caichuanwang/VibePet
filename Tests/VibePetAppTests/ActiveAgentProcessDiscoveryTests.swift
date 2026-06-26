import XCTest
@testable import VibePetApp
@testable import VibePetCore

final class ActiveAgentProcessDiscoveryTests: XCTestCase {
    func testDiscoversClaudeAndCodexProcessesFromProcessTable() {
        let psOutput = """
          101     1 ttys001 /opt/homebrew/bin/codex
          102     1 ttys002 /Users/test/.local/bin/claude
          103     1 ttys003 /Users/test/Library/Application Support/VibePet/bin/VibePetHooks --tool codex
        """
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return psOutput
            }
            if executablePath == "/usr/sbin/lsof", arguments.contains("101") {
                return "p101\nn/Users/test/Code/VibePet\n"
            }
            if executablePath == "/usr/sbin/lsof", arguments.contains("102") {
                return "p102\nn/Users/test/Code/Service\n"
            }
            return nil
        }

        let sessions = discovery.discover()

        XCTAssertEqual(sessions.map(\.tool), [.codex, .claudeCode])
        XCTAssertEqual(sessions.map(\.id), ["discovered-codex-101", "discovered-claudeCode-102"])
        XCTAssertEqual(sessions[0].title, "VibePet")
        XCTAssertEqual(sessions[0].jumpTarget?.workingDirectory, "/Users/test/Code/VibePet")
        XCTAssertEqual(sessions[0].jumpTarget?.terminalTTY, "ttys001")
        XCTAssertEqual(sessions[1].title, "Service")
        XCTAssertEqual(sessions[1].jumpTarget?.workingDirectory, "/Users/test/Code/Service")
        XCTAssertEqual(sessions[1].jumpTarget?.terminalTTY, "ttys002")
    }

    func testInfersTerminalAppFromParentProcessChain() {
        let psOutput = """
          101   202 ttys001 /opt/homebrew/bin/codex
          202   303 ttys001 -zsh
          303     1 ttys001 /Applications/Ghostty.app/Contents/MacOS/ghostty
        """
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return psOutput
            }
            if executablePath == "/usr/sbin/lsof", arguments.contains("101") {
                return "p101\nn/Users/test/Code/VibePet\n"
            }
            return nil
        }

        let sessions = discovery.discover()

        XCTAssertEqual(sessions.first?.jumpTarget?.terminalApp, "Ghostty")
    }

    func testIgnoresCodexServerAndHelperProcesses() {
        let psOutput = """
          101     1 ?? node /Users/test/.nvm/bin/codex app-server
          102   101 ?? /Users/test/.nvm/lib/node_modules/@openai/codex/vendor/bin/codex app-server
          103   104 ttys001 /Applications/Codex.app/Contents/Resources/cua_node/bin/node_repl
          104   202 ttys001 /opt/homebrew/bin/codex
        """
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return psOutput
            }
            if executablePath == "/usr/sbin/lsof", arguments.contains("104") {
                return "p104\nn/Users/test/Code/VibePet\n"
            }
            return nil
        }

        let sessions = discovery.discover()

        XCTAssertEqual(sessions.map(\.id), ["discovered-codex-104"])
    }

    @MainActor
    func testBridgeHostImportsDiscoveredSessionsIntoDashboardState() async {
        let surface = DiscoveryTestPetSurface()
        let controller = PetController(surface: surface)
        let discovered = ActiveAgentSession(
            id: "discovered-codex-101",
            title: "VibePet",
            tool: .codex,
            summary: "Detected running Codex",
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workingDirectory: "/Users/test/Code/VibePet",
                terminalTTY: "ttys001"
            )
        )
        let host = BridgeServerHost(
            petController: controller,
            liveSessionProvider: { state in Set(state.sessionsByID.keys) },
            activeSessionProvider: { [discovered] in [discovered] },
            livenessInterval: 60
        )

        await host.runLivenessSweepOnce()

        let session = host.sessionStateSnapshot.sessionsByID["discovered-codex-101"]
        XCTAssertEqual(session?.title, "VibePet")
        XCTAssertEqual(session?.tool, .codex)
        XCTAssertEqual(session?.phase, .completed)
        XCTAssertEqual(session?.isProcessAlive, true)
        XCTAssertEqual(host.sessionStateSnapshot.runningCount, 0)
        XCTAssertEqual(session?.jumpTarget?.terminalApp, "Ghostty")
        XCTAssertEqual(SessionDashboardProjection(state: host.sessionStateSnapshot, activePetName: "Pixel").totalCount, 1)
    }

    @MainActor
    func testRepeatedProcessDiscoveryKeepsPlaceholderVisibleWhenLivenessMisses() async {
        let surface = DiscoveryTestPetSurface()
        let controller = PetController(surface: surface)
        let discovered = ActiveAgentSession(
            id: "discovered-codex-101",
            title: "VibePet",
            tool: .codex,
            summary: "Detected running Codex",
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workingDirectory: "/Users/test/Code/VibePet",
                terminalTTY: "ttys001"
            )
        )
        let host = BridgeServerHost(
            petController: controller,
            liveSessionProvider: { _ in [] },
            activeSessionProvider: { [discovered] in [discovered] },
            livenessInterval: 60
        )

        await host.runLivenessSweepOnce()
        await host.runLivenessSweepOnce()

        let session = host.sessionStateSnapshot.sessionsByID["discovered-codex-101"]
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.isProcessAlive, true)
        XCTAssertEqual(session?.processNotSeenCount, 0)
        XCTAssertEqual(SessionDashboardProjection(state: host.sessionStateSnapshot, activePetName: "Pixel").totalCount, 1)
    }

    @MainActor
    func testHookSessionStartReplacesMatchingDiscoveredPlaceholder() async {
        let surface = DiscoveryTestPetSurface()
        let controller = PetController(surface: surface)
        let discovered = ActiveAgentSession(
            id: "discovered-codex-101",
            title: "VibePet",
            tool: .codex,
            summary: "Detected running Codex",
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workingDirectory: "/Users/test/Code/VibePet",
                terminalTTY: "ttys001"
            )
        )
        let host = BridgeServerHost(
            petController: controller,
            liveSessionProvider: { state in Set(state.sessionsByID.keys) },
            activeSessionProvider: { [discovered] in [discovered] },
            livenessInterval: 60
        )

        await host.runLivenessSweepOnce()
        host.applyForTesting(.sessionStarted(
            sessionID: "codex-session-full",
            timestamp: Date(),
            title: "VibePet",
            tool: .codex,
            summary: "Started",
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workingDirectory: "/Users/test/Code/VibePet",
                terminalTTY: "ttys001"
            )
        ))

        XCTAssertNil(host.sessionStateSnapshot.sessionsByID["discovered-codex-101"])
        XCTAssertEqual(host.sessionStateSnapshot.sessionsByID["codex-session-full"]?.phase, .running)
        XCTAssertEqual(host.sessionStateSnapshot.visibleSessions.map(\.id), ["codex-session-full"])
        XCTAssertEqual(SessionDashboardProjection(state: host.sessionStateSnapshot, activePetName: "Pixel").totalCount, 1)
    }

    @MainActor
    func testProcessDiscoveryDoesNotReaddPlaceholderForMatchingHookSession() async {
        let surface = DiscoveryTestPetSurface()
        let controller = PetController(surface: surface)
        let discovered = ActiveAgentSession(
            id: "discovered-codex-101",
            title: "VibePet",
            tool: .codex,
            summary: "Detected running Codex",
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workingDirectory: "/Users/test/Code/VibePet",
                terminalTTY: "ttys001"
            )
        )
        let host = BridgeServerHost(
            petController: controller,
            liveSessionProvider: { state in Set(state.sessionsByID.keys) },
            activeSessionProvider: { [discovered] in [discovered] },
            livenessInterval: 60
        )

        host.applyForTesting(.sessionStarted(
            sessionID: "codex-session-full",
            timestamp: Date(),
            title: "VibePet",
            tool: .codex,
            summary: "Started",
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workingDirectory: "/Users/test/Code/VibePet",
                terminalTTY: "ttys001"
            )
        ))
        await host.runLivenessSweepOnce()

        XCTAssertNil(host.sessionStateSnapshot.sessionsByID["discovered-codex-101"])
        XCTAssertEqual(host.sessionStateSnapshot.visibleSessions.map(\.id), ["codex-session-full"])
    }

    @MainActor
    func testBridgeHostRunsInitialDiscoveryWhenStarted() async throws {
        let root = try DiscoveryTemporaryDirectory()
        let surface = DiscoveryTestPetSurface()
        let controller = PetController(surface: surface)
        let discovered = ActiveAgentSession(
            id: "discovered-claudeCode-102",
            title: "Service",
            tool: .claudeCode,
            summary: "Detected running Claude Code",
            jumpTarget: JumpTarget(terminalApp: "Ghostty", workingDirectory: "/tmp/service", terminalTTY: "ttys002")
        )
        let host = BridgeServerHost(
            petController: controller,
            socketPath: SocketPath(applicationSupportRoot: root.url),
            liveSessionProvider: { state in Set(state.sessionsByID.keys) },
            activeSessionProvider: { [discovered] in [discovered] },
            livenessInterval: 60
        )

        host.start()
        defer { host.stop() }

        try await waitUntil { host.sessionStateSnapshot.sessionsByID["discovered-claudeCode-102"] != nil }
    }
}

@MainActor
private final class DiscoveryTestPetSurface: PetSurface {
    var petFrame: CGRect? = CGRect(x: 0, y: 0, width: 120, height: 120)
    var visibleFrame: CGRect = CGRect(x: 0, y: 0, width: 1000, height: 800)
    var selectedDashboardSessionID: String?
    var selectedDashboardJumpTarget: JumpTarget?

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
        placement: BubbleAnchor.Placement,
        pendingCount: Int,
        onJump: @escaping (JumpTarget) -> Void,
        onAnswer: @escaping (BridgeResponse) -> Void
    ) {}

    func updatePendingCount(_ count: Int) {}
    func dismissApproval() {}
    func dismissQuestion() {}
    func updateNotificationBadge(_ count: Int) {}
}

private func waitUntil(timeout: TimeInterval = 2, _ condition: @MainActor () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return }
        try await Task.sleep(nanoseconds: 25_000_000)
    }
    XCTFail("Condition not met within \(timeout)s")
}

private final class DiscoveryTemporaryDirectory {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vibepet-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

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
                return "p101\nfcwd\nn/Users/test/Code/VibePet\nf20\nn/Users/test/.codex/sessions/2026/07/30/rollout-2026-07-30T10-00-00-11111111-1111-4111-8111-111111111111.jsonl\n"
            }
            if executablePath == "/usr/sbin/lsof", arguments.contains("102") {
                return "p102\nfcwd\nn/Users/test/Code/Service\nf21\nn/Users/test/.claude/projects/-Users-test-Code-Service/22222222-2222-4222-8222-222222222222.jsonl\n"
            }
            return nil
        }

        let sessions = discovery.discover()

        XCTAssertEqual(sessions.map(\.tool), [.codex, .claudeCode])
        XCTAssertEqual(sessions.map(\.nativeSessionID), [
            "11111111-1111-4111-8111-111111111111",
            "22222222-2222-4222-8222-222222222222",
        ])
        XCTAssertEqual(sessions.map(\.id), [
            "discovered-codex-11111111-1111-4111-8111-111111111111",
            "discovered-claudeCode-22222222-2222-4222-8222-222222222222",
        ])
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

    func testInfersCmuxFromParentProcessChain() {
        let psOutput = """
          101   202 ttys005 /Users/test/.local/bin/claude --resume 358f323b-8f28-4f2c-881c-6652b64e58a0
          202   303 ttys005 -/bin/zsh /var/folders/tmp/cmux-surface-resume/claude-FBF59C5C.zsh
          303   304 ttys005 /usr/bin/login -flp test /bin/bash --noprofile --norc -c exec -l /bin/zsh '/var/folders/tmp/cmux-surface-resume/claude-FBF59C5C.zsh'
          304     1 ?? /Applications/cmux.app/Contents/MacOS/cmux
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

        XCTAssertEqual(sessions.first?.jumpTarget?.terminalApp, "cmux")
    }

    func testCmuxHookConfigurationInCommandDoesNotInferCmux() {
        let psOutput = """
          101     1 ttys001 /Users/test/.local/bin/claude --settings {"hooks":{"Stop":[{"hooks":[{"command":"\\"${CMUX_CLAUDE_HOOK_CMUX_BIN:-cmux}\\" hooks feed"}]}]}}
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

        XCTAssertEqual(sessions.first?.jumpTarget?.terminalApp, "Terminal")
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

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.tool, .codex)
    }

    func testExtractsClaudeSessionIDFromResumeWhenTranscriptIsUnavailable() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return "101 1 ttys001 /Users/test/.local/bin/claude --resume 33333333-3333-4333-8333-333333333333"
            }
            if executablePath == "/usr/sbin/lsof", arguments.contains("101") {
                return "p101\nfcwd\nn/Users/test/Code/Service\n"
            }
            return nil
        }

        let session = discovery.discover().first

        XCTAssertEqual(session?.nativeSessionID, "33333333-3333-4333-8333-333333333333")
        XCTAssertEqual(session?.id, "discovered-claudeCode-33333333-3333-4333-8333-333333333333")
    }

    func testDiscoversNoTTYProcessWhenItHasExactTranscriptIdentity() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return "101 1 ?? /Users/test/.local/bin/claude"
            }
            if executablePath == "/usr/sbin/lsof", arguments.contains("101") {
                return "p101\nfcwd\nn/Users/test/Code/Service\nf20\nn/Users/test/.claude/projects/project/44444444-4444-4444-8444-444444444444.jsonl\n"
            }
            return nil
        }

        let session = discovery.discover().first

        XCTAssertEqual(session?.nativeSessionID, "44444444-4444-4444-8444-444444444444")
        XCTAssertNil(session?.jumpTarget?.terminalTTY)
    }

    func testPIDAndWrapperChangesDoNotCreateDuplicateSyntheticIdentity() {
        func discover(psOutput: String) -> [ActiveAgentSession] {
            ActiveAgentProcessDiscovery { executablePath, _ in
                if executablePath == "/bin/ps" { return psOutput }
                if executablePath == "/usr/sbin/lsof" {
                    return "p\nfcwd\nn/Users/test/Code/VibePet\n"
                }
                return nil
            }.discover()
        }

        let first = discover(psOutput: """
          101     1 ttys001 /opt/homebrew/bin/codex
          202   101 ttys001 /Users/test/.nvm/lib/node_modules/@openai/codex/vendor/bin/codex
        """)
        let second = discover(psOutput: """
          303     1 ttys001 /Users/test/.nvm/lib/node_modules/@openai/codex/vendor/bin/codex
        """)

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(first[0].id, second[0].id)
        XCTAssertTrue(first[0].id.hasPrefix("discovered-codex-synthetic-"))
    }

    func testIgnoresHeadlessAgentWithoutExactIdentity() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return "101 1 ?? /Users/test/.local/bin/claude"
            }
            if executablePath == "/usr/sbin/lsof", arguments.contains("101") {
                return "p101\nfcwd\nn/Users/test/Code/Service\n"
            }
            return nil
        }

        XCTAssertEqual(discovery.discover(), [])
    }

    func testCommandOutputDrainsLargeStdoutWithoutDeadlock() {
        let output = ActiveAgentProcessDiscovery.commandOutput(
            executablePath: "/usr/bin/python3",
            arguments: ["-c", "print('x' * 200000)"]
        )

        XCTAssertEqual(output?.count, 200_000)
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

    @MainActor
    func testFailedUnifiedScanDoesNotAccumulateMissingCount() async {
        let host = BridgeServerHost(
            petController: PetController(surface: DiscoveryTestPetSurface()),
            processScanProvider: { .failure },
            livenessInterval: 60
        )
        host.applyForTesting(.sessionStarted(
            sessionID: "existing",
            timestamp: .now,
            title: "Existing",
            tool: .codex,
            summary: "Started",
            jumpTarget: nil
        ))

        await host.runLivenessSweepOnce()
        await host.runLivenessSweepOnce()

        XCTAssertEqual(host.sessionStateSnapshot.sessionsByID["existing"]?.processNotSeenCount, 0)
    }

    @MainActor
    func testSuccessfulEmptyUnifiedScanReapsAfterTwoMisses() async {
        let host = BridgeServerHost(
            petController: PetController(surface: DiscoveryTestPetSurface()),
            processScanProvider: { .success([]) },
            livenessInterval: 60
        )
        host.applyForTesting(.sessionStarted(
            sessionID: "existing",
            timestamp: .now,
            title: "Existing",
            tool: .codex,
            summary: "Started",
            jumpTarget: nil
        ))

        await host.runLivenessSweepOnce()
        XCTAssertEqual(host.sessionStateSnapshot.sessionsByID["existing"]?.processNotSeenCount, 1)
        await host.runLivenessSweepOnce()

        XCTAssertNil(host.sessionStateSnapshot.sessionsByID["existing"])
    }

    @MainActor
    func testUnifiedSweepInvokesProcessProviderOnlyOnce() async {
        let counter = DiscoveryInvocationCounter()
        let host = BridgeServerHost(
            petController: PetController(surface: DiscoveryTestPetSurface()),
            processScanProvider: {
                await counter.increment()
                return .success([])
            },
            livenessInterval: 60
        )

        await host.runLivenessSweepOnce()

        let invocationCount = await counter.value
        XCTAssertEqual(invocationCount, 1)
    }

    @MainActor
    func testDifferentNativeSessionOnSameTTYDoesNotKeepOldSessionAlive() async {
        let newSession = ActiveAgentSession(
            id: "discovered-codex-new-native",
            title: "New",
            tool: .codex,
            summary: "Detected running Codex",
            jumpTarget: JumpTarget(terminalApp: "Terminal", terminalTTY: "ttys001"),
            nativeSessionID: "new-native",
            transcriptPath: "/tmp/new-native.jsonl"
        )
        let host = BridgeServerHost(
            petController: PetController(surface: DiscoveryTestPetSurface()),
            processScanProvider: { .success([newSession]) },
            livenessInterval: 60
        )
        host.applyForTesting(.sessionStarted(
            sessionID: "old-native",
            timestamp: .now,
            title: "Old",
            tool: .codex,
            summary: "Started",
            jumpTarget: JumpTarget(terminalApp: "Terminal", terminalTTY: "ttys001")
        ))

        await host.runLivenessSweepOnce()

        XCTAssertEqual(host.sessionStateSnapshot.sessionsByID["old-native"]?.processNotSeenCount, 1)
        XCTAssertNotNil(host.sessionStateSnapshot.sessionsByID[newSession.id])
    }
}

private actor DiscoveryInvocationCounter {
    private var count = 0

    var value: Int { count }

    func increment() {
        count += 1
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
        conversationContext: QuestionConversationContext?,
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

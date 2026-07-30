import Foundation
import VibePetCore
import XCTest
@testable import VibePetApp

final class SessionDiscoveryCoordinatorTests: XCTestCase {
    func testRecentDiscoveryReadsClaudeAndCodexIdentityWithoutLoadingWholeTranscript() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let codexRoot = root.appendingPathComponent("codex", isDirectory: true)
        let claudeRoot = root.appendingPathComponent("claude", isDirectory: true)
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let codexID = "11111111-1111-4111-8111-111111111111"
        let claudeID = "22222222-2222-4222-8222-222222222222"
        let codexFile = codexRoot.appendingPathComponent("rollout-\(codexID).jsonl")
        let claudeFile = claudeRoot.appendingPathComponent("\(claudeID).jsonl")
        try """
        {"type":"session_meta","payload":{"id":"\(codexID)","cwd":"/Users/test/Code/CodexProject"}}
        {"type":"event_msg","payload":{"type":"user_message","message":"hello"}}
        """.write(to: codexFile, atomically: true, encoding: .utf8)
        try """
        {"type":"user","sessionId":"\(claudeID)","cwd":"/Users/test/Code/ClaudeProject","message":{"role":"user","content":"hello"}}
        """.write(to: claudeFile, atomically: true, encoding: .utf8)

        let discovery = RecentSessionDiscovery(
            codexRootURL: codexRoot,
            claudeRootURL: claudeRoot
        )

        let candidates = discovery.discover(now: .now)

        XCTAssertEqual(
            Set(candidates.map(\.sessionID)),
            Set([codexID, claudeID])
        )
        XCTAssertEqual(
            candidates.first(where: { $0.tool == .codex })?.workingDirectory,
            "/Users/test/Code/CodexProject"
        )
        XCTAssertEqual(
            candidates.first(where: { $0.tool == .claudeCode })?.workingDirectory,
            "/Users/test/Code/ClaudeProject"
        )
    }

    func testStartupDiscoveryEnrichesUniqueWorkingDirectoryMatch() async {
        let nativeID = "33333333-3333-4333-8333-333333333333"
        let active = ActiveAgentSession(
            id: "discovered-codex-synthetic-old",
            title: "VibePet",
            tool: .codex,
            summary: "Detected running Codex",
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workingDirectory: "/Users/test/Code/VibePet",
                terminalTTY: "ttys001"
            ),
            processID: "101"
        )
        let candidate = StartupSessionCandidate(
            tool: .codex,
            sessionID: nativeID,
            transcriptPath: "/Users/test/.codex/sessions/rollout-\(nativeID).jsonl",
            workingDirectory: "/Users/test/Code/VibePet",
            updatedAt: .now
        )
        let coordinator = SessionDiscoveryCoordinator(
            processScanProvider: { .success([active]) },
            localSessionProvider: { [candidate] }
        )

        let result = await coordinator.scan()

        guard case let .success(sessions) = result else {
            return XCTFail("Expected a successful process scan")
        }
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].nativeSessionID, nativeID)
        XCTAssertEqual(sessions[0].id, "discovered-codex-\(nativeID)")
        XCTAssertEqual(sessions[0].transcriptPath, candidate.transcriptPath)
        XCTAssertEqual(sessions[0].jumpTarget?.terminalTTY, "ttys001")
    }

    func testStartupDiscoveryDoesNotGuessAmongMultipleTranscriptsInSameWorkspace() async {
        let active = ActiveAgentSession(
            id: "discovered-claudeCode-synthetic-old",
            title: "Service",
            tool: .claudeCode,
            summary: "Detected running Claude Code",
            jumpTarget: JumpTarget(
                terminalApp: "Terminal",
                workingDirectory: "/Users/test/Code/Service",
                terminalTTY: "ttys002"
            )
        )
        let candidates = [
            StartupSessionCandidate(
                tool: .claudeCode,
                sessionID: "44444444-4444-4444-8444-444444444444",
                transcriptPath: "/tmp/44444444-4444-4444-8444-444444444444.jsonl",
                workingDirectory: "/Users/test/Code/Service",
                updatedAt: .now
            ),
            StartupSessionCandidate(
                tool: .claudeCode,
                sessionID: "55555555-5555-4555-8555-555555555555",
                transcriptPath: "/tmp/55555555-5555-4555-8555-555555555555.jsonl",
                workingDirectory: "/Users/test/Code/Service",
                updatedAt: .now
            ),
        ]
        let coordinator = SessionDiscoveryCoordinator(
            processScanProvider: { .success([active]) },
            localSessionProvider: { candidates }
        )

        let result = await coordinator.scan()

        guard case let .success(sessions) = result else {
            return XCTFail("Expected a successful process scan")
        }
        XCTAssertEqual(sessions, [active])
    }

    func testStartupDiscoveryDoesNotAttachOneTranscriptToTwoProcesses() async {
        let sessions = [
            ActiveAgentSession(
                id: "discovered-codex-synthetic-one",
                title: "VibePet",
                tool: .codex,
                summary: "Detected running Codex",
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workingDirectory: "/Users/test/Code/VibePet",
                    terminalTTY: "ttys001"
                )
            ),
            ActiveAgentSession(
                id: "discovered-codex-synthetic-two",
                title: "VibePet",
                tool: .codex,
                summary: "Detected running Codex",
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workingDirectory: "/Users/test/Code/VibePet",
                    terminalTTY: "ttys002"
                )
            ),
        ]
        let candidate = StartupSessionCandidate(
            tool: .codex,
            sessionID: "66666666-6666-4666-8666-666666666666",
            transcriptPath: "/tmp/66666666-6666-4666-8666-666666666666.jsonl",
            workingDirectory: "/Users/test/Code/VibePet",
            updatedAt: .now
        )
        let coordinator = SessionDiscoveryCoordinator(
            processScanProvider: { .success(sessions) },
            localSessionProvider: { [candidate] }
        )

        let result = await coordinator.scan()

        guard case let .success(discovered) = result else {
            return XCTFail("Expected a successful process scan")
        }
        XCTAssertEqual(discovered, sessions)
    }

    func testFailedProcessScanDoesNotLoadOrConsumeStartupCandidates() async {
        let state = StartupProviderState()
        let nativeID = "77777777-7777-4777-8777-777777777777"
        let active = ActiveAgentSession(
            id: "discovered-codex-synthetic-old",
            title: "VibePet",
            tool: .codex,
            summary: "Detected running Codex",
            jumpTarget: JumpTarget(
                terminalApp: "Terminal",
                workingDirectory: "/Users/test/Code/VibePet",
                terminalTTY: "ttys001"
            )
        )
        let candidate = StartupSessionCandidate(
            tool: .codex,
            sessionID: nativeID,
            transcriptPath: "/tmp/\(nativeID).jsonl",
            workingDirectory: "/Users/test/Code/VibePet",
            updatedAt: .now
        )
        let coordinator = SessionDiscoveryCoordinator(
            processScanProvider: {
                state.nextProcessScan(success: [active])
            },
            localSessionProvider: {
                state.loadCandidates([candidate])
            }
        )

        let first = await coordinator.scan()
        let second = await coordinator.scan()

        XCTAssertEqual(first, .failure)
        guard case let .success(sessions) = second else {
            return XCTFail("Expected the retry to succeed")
        }
        XCTAssertEqual(sessions.first?.nativeSessionID, nativeID)
        XCTAssertEqual(state.localLoadCount, 1)
    }

    func testSuccessfulUnresolvedScanRetriesWhenTranscriptAppearsLater() async {
        let state = DelayedCandidateProviderState()
        let nativeID = "88888888-8888-4888-8888-888888888888"
        let active = ActiveAgentSession(
            id: "discovered-claudeCode-synthetic-old",
            title: "Service",
            tool: .claudeCode,
            summary: "Detected running Claude Code",
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workingDirectory: "/Users/test/Code/Service",
                terminalTTY: "ttys003"
            ),
            processID: "202"
        )
        let candidate = StartupSessionCandidate(
            tool: .claudeCode,
            sessionID: nativeID,
            transcriptPath: "/tmp/\(nativeID).jsonl",
            workingDirectory: "/Users/test/Code/Service",
            updatedAt: .now
        )
        let coordinator = SessionDiscoveryCoordinator(
            processScanProvider: { .success([active]) },
            localSessionProvider: {
                state.nextCandidates(eventual: [candidate])
            },
            candidateRefreshInterval: 0
        )

        let first = await coordinator.scan()
        let second = await coordinator.scan()

        guard case let .success(firstSessions) = first,
              case let .success(secondSessions) = second else {
            return XCTFail("Expected both process scans to succeed")
        }
        XCTAssertNil(firstSessions.first?.nativeSessionID)
        XCTAssertEqual(secondSessions.first?.nativeSessionID, nativeID)
        XCTAssertEqual(
            secondSessions.first?.id,
            "discovered-claudeCode-\(nativeID)"
        )
        XCTAssertEqual(state.localLoadCount, 2)
    }
}

private final class StartupProviderState: @unchecked Sendable {
    private let lock = NSLock()
    private var processScanCount = 0
    private var storedLocalLoadCount = 0

    var localLoadCount: Int {
        lock.withLock { storedLocalLoadCount }
    }

    func nextProcessScan(success: [ActiveAgentSession]) -> ActiveAgentProcessScan {
        lock.withLock {
            processScanCount += 1
            return processScanCount == 1 ? .failure : .success(success)
        }
    }

    func loadCandidates(_ candidates: [StartupSessionCandidate]) -> [StartupSessionCandidate] {
        lock.withLock {
            storedLocalLoadCount += 1
            return candidates
        }
    }
}

private final class DelayedCandidateProviderState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedLocalLoadCount = 0

    var localLoadCount: Int {
        lock.withLock { storedLocalLoadCount }
    }

    func nextCandidates(
        eventual candidates: [StartupSessionCandidate]
    ) -> [StartupSessionCandidate] {
        lock.withLock {
            storedLocalLoadCount += 1
            return storedLocalLoadCount == 1 ? [] : candidates
        }
    }
}

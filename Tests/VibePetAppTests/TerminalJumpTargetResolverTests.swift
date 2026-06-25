import XCTest
@testable import VibePetApp
@testable import VibePetCore

final class TerminalJumpTargetResolverTests: XCTestCase {
    func testGhosttySessionIsCorrectedBySessionIDCwdOrTitle() {
        let resolver = TerminalJumpTargetResolver(
            ghosttySnapshots: {
                [
                    TerminalJumpTargetResolver.GhosttySnapshot(
                        sessionID: "ghostty-1",
                        workingDirectory: "/work/VibePet",
                        title: "Codex"
                    )
                ]
            },
            terminalSnapshots: { [] }
        )
        let session = AgentSession(
            id: "s1",
            title: "VibePet",
            tool: .codex,
            phase: .running,
            summary: "Running",
            updatedAt: Date(),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "Old",
                paneTitle: nil,
                workingDirectory: "/work/VibePet"
            )
        )

        let updates = resolver.resolveJumpTargets(for: [session])

        XCTAssertEqual(updates["s1"]?.terminalSessionID, "ghostty-1")
        XCTAssertEqual(updates["s1"]?.workingDirectory, "/work/VibePet")
        XCTAssertEqual(updates["s1"]?.paneTitle, "Codex")
        XCTAssertEqual(updates["s1"]?.workspaceName, "VibePet")
    }

    func testTerminalSessionIsCorrectedByTTY() {
        let resolver = TerminalJumpTargetResolver(
            ghosttySnapshots: { [] },
            terminalSnapshots: {
                [
                    TerminalJumpTargetResolver.TerminalSnapshot(
                        tty: "/dev/ttys002",
                        title: "Codex"
                    )
                ]
            }
        )
        let session = AgentSession(
            id: "s2",
            title: "VibePet",
            tool: .claudeCode,
            phase: .running,
            summary: "Running",
            updatedAt: Date(),
            jumpTarget: JumpTarget(
                terminalApp: "Terminal",
                workspaceName: "VibePet",
                paneTitle: "Old",
                workingDirectory: "/work/VibePet",
                terminalTTY: "/dev/ttys002"
            )
        )

        let updates = resolver.resolveJumpTargets(for: [session])

        XCTAssertEqual(updates["s2"]?.terminalTTY, "/dev/ttys002")
        XCTAssertEqual(updates["s2"]?.paneTitle, "Codex")
        XCTAssertEqual(updates["s2"]?.workingDirectory, "/work/VibePet")
    }

    func testUnsupportedTerminalsAreSkipped() {
        let ghosttyQueried = LockedValue(false)
        let terminalQueried = LockedValue(false)
        let resolver = TerminalJumpTargetResolver(
            ghosttySnapshots: {
                ghosttyQueried.set(true)
                return []
            },
            terminalSnapshots: {
                terminalQueried.set(true)
                return []
            }
        )
        let sessions = [
            session(id: "iterm", app: "iTerm"),
            session(id: "cmux", app: "cmux"),
            session(id: "code", app: "VS Code"),
            session(id: "unknown", app: "Unknown"),
        ]

        let updates = resolver.resolveJumpTargets(for: sessions)

        XCTAssertTrue(updates.isEmpty)
        XCTAssertFalse(ghosttyQueried.value)
        XCTAssertFalse(terminalQueried.value)
    }

    func testSnapshotFailureReturnsNoUpdates() {
        let resolver = TerminalJumpTargetResolver(
            ghosttySnapshots: { nil },
            terminalSnapshots: { nil }
        )

        let updates = resolver.resolveJumpTargets(for: [
            session(id: "ghostty", app: "Ghostty"),
            session(id: "terminal", app: "Terminal"),
        ])

        XCTAssertTrue(updates.isEmpty)
    }

    func testDefaultAppleScriptRunnerFailsOpenOnTimeout() {
        let started = Date()

        let output = TerminalJumpTargetResolver.runAppleScript(
            "delay 5\nreturn \"late\"",
            timeout: 0.05
        )

        XCTAssertNil(output)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    private func session(id: String, app: String) -> AgentSession {
        AgentSession(
            id: id,
            title: id,
            tool: .codex,
            phase: .running,
            summary: "Running",
            updatedAt: Date(),
            jumpTarget: JumpTarget(
                terminalApp: app,
                workspaceName: "VibePet",
                paneTitle: id,
                workingDirectory: "/work/VibePet",
                terminalTTY: "/dev/ttys001"
            )
        )
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.withLock { storage }
    }

    func set(_ value: Value) {
        lock.withLock {
            storage = value
        }
    }
}

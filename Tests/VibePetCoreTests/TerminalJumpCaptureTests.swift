import XCTest
@testable import VibePetCore

final class TerminalJumpCaptureTests: XCTestCase {
    func testInferTerminalAppPrefersCmuxEnvironment() {
        let app = TerminalJumpCapture.inferTerminalApp(from: [
            "CMUX_WORKSPACE_ID": "workspace",
            "TERM_PROGRAM": "Apple_Terminal",
        ])

        XCTAssertEqual(app, "cmux")
    }

    func testInferTerminalAppUsesTermProgramAndFallbacks() {
        XCTAssertEqual(TerminalJumpCapture.inferTerminalApp(from: ["TERM_PROGRAM": "Apple_Terminal"]), "Terminal")
        XCTAssertEqual(TerminalJumpCapture.inferTerminalApp(from: ["TERM_PROGRAM": "iTerm.app"]), "iTerm")
        XCTAssertEqual(TerminalJumpCapture.inferTerminalApp(from: ["TERM_PROGRAM": "ghostty"]), "Ghostty")
        XCTAssertEqual(TerminalJumpCapture.inferTerminalApp(from: ["TERM_PROGRAM": "vscode"]), "VS Code")
        XCTAssertEqual(TerminalJumpCapture.inferTerminalApp(from: ["ITERM_SESSION_ID": "w0t1p0"]), "iTerm")
        XCTAssertEqual(TerminalJumpCapture.inferTerminalApp(from: ["GHOSTTY_RESOURCES_DIR": "/Applications/Ghostty.app"]), "Ghostty")
        XCTAssertEqual(TerminalJumpCapture.inferTerminalApp(from: [:]), "Unknown")
    }

    func testWorkspaceNameUsesCwdLastPathComponent() {
        XCTAssertEqual(TerminalJumpCapture.workspaceName(from: "/Users/dev/Projects/VibePet"), "VibePet")
        XCTAssertNil(TerminalJumpCapture.workspaceName(from: nil))
    }

    func testCurrentTTYUsesTTYThenPSFallback() {
        var commands: [(String, [String])] = []
        let capture = TerminalJumpCapture(
            commandRunner: { executable, arguments in
                commands.append((executable, arguments))
                if executable == "/usr/bin/tty" {
                    return TerminalJumpCapture.CommandResult(status: 1, stdout: "not a tty\n")
                }
                return TerminalJumpCapture.CommandResult(status: 0, stdout: "ttys007\n")
            }
        )

        XCTAssertEqual(capture.currentTTY(parentProcessID: 42), "/dev/ttys007")
        XCTAssertEqual(commands.map(\.0), ["/usr/bin/tty", "/bin/ps"])
        XCTAssertEqual(commands.last?.1, ["-p", "42", "-o", "tty="])
    }

    func testBuildJumpTargetRunsITermLocatorForAnyRecognizedHook() {
        var locatedApps: [String] = []
        let capture = TerminalJumpCapture(
            currentTTYProvider: { "/dev/ttys001" },
            terminalLocator: { app, tty in
                locatedApps.append(app)
                XCTAssertEqual(tty, "/dev/ttys001")
                return TerminalJumpCapture.LocatorSnapshot(
                    sessionID: "iterm-session",
                    tty: "/dev/ttys001",
                    title: "Codex"
                )
            }
        )

        let target = capture.buildJumpTarget(
            env: ["TERM_PROGRAM": "iTerm.app"],
            cwd: "/Users/dev/Projects/VibePet",
            hookEventName: "PreToolUse"
        )

        XCTAssertEqual(locatedApps, ["iTerm"])
        XCTAssertEqual(target?.terminalApp, "iTerm")
        XCTAssertEqual(target?.workspaceName, "VibePet")
        XCTAssertEqual(target?.workingDirectory, "/Users/dev/Projects/VibePet")
        XCTAssertEqual(target?.terminalSessionID, "iterm-session")
        XCTAssertEqual(target?.terminalTTY, "/dev/ttys001", "process-derived TTY must not be replaced by a frontmost locator")
        XCTAssertEqual(target?.paneTitle, "Codex")
    }

    func testBuildJumpTargetRejectsLocatorMetadataFromDifferentTTY() {
        let capture = TerminalJumpCapture(
            currentTTYProvider: { "/dev/ttys001" },
            terminalLocator: { _, _ in
                TerminalJumpCapture.LocatorSnapshot(
                    sessionID: "wrong-session",
                    tty: "/dev/ttys999",
                    title: "Wrong tab"
                )
            }
        )

        let target = capture.buildJumpTarget(
            env: ["TERM_PROGRAM": "iTerm.app"],
            cwd: "/tmp/project",
            hookEventName: "PreToolUse"
        )

        XCTAssertEqual(target?.terminalTTY, "/dev/ttys001")
        XCTAssertNil(target?.terminalSessionID)
        XCTAssertNil(target?.paneTitle)
    }

    func testDefaultTerminalLocatorPreservesTerminalLeadingEmptySessionField() {
        let snapshot = TerminalJumpCapture.parseLocatorOutput("\t/dev/ttys009\tBuild\n")

        XCTAssertEqual(snapshot?.sessionID, nil)
        XCTAssertEqual(snapshot?.tty, "/dev/ttys009")
        XCTAssertEqual(snapshot?.title, "Build")
    }

    func testDefaultCommandRunnerFailsOpenOnTimeout() {
        let started = Date()

        let result = TerminalJumpCapture.defaultCommandRunner(
            executable: "/bin/sh",
            arguments: ["-c", "sleep 5; echo late"],
            timeout: 0.05
        )

        XCTAssertNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    func testBuildJumpTargetNeverCombinesGhosttyFrontmostIDWithProcessTTY() {
        var locateCount = 0
        let capture = TerminalJumpCapture(
            currentTTYProvider: { "/dev/ttys002" },
            terminalLocator: { _, _ in
                locateCount += 1
                return TerminalJumpCapture.LocatorSnapshot(
                    sessionID: "ghostty-session",
                    tty: nil,
                    title: "Prompt"
                )
            }
        )

        let safe = capture.buildJumpTarget(
            env: ["TERM_PROGRAM": "ghostty"],
            cwd: "/tmp/VibePet",
            hookEventName: "SessionStart"
        )
        let tool = capture.buildJumpTarget(
            env: ["TERM_PROGRAM": "ghostty"],
            cwd: "/tmp/VibePet",
            hookEventName: "PreToolUse"
        )

        XCTAssertEqual(locateCount, 0)
        XCTAssertEqual(safe?.terminalSessionID, nil)
        XCTAssertEqual(safe?.paneTitle, nil)
        XCTAssertEqual(safe?.terminalTTY, "/dev/ttys002")
        XCTAssertEqual(tool?.terminalSessionID, nil)
        XCTAssertEqual(tool?.paneTitle, nil)
        XCTAssertEqual(tool?.terminalTTY, "/dev/ttys002")
    }

    func testBuildJumpTargetSkipsLocatorsForCmuxAndVSCode() {
        var locateCount = 0
        let capture = TerminalJumpCapture(
            currentTTYProvider: { "/dev/ttys003" },
            terminalLocator: { _, _ in
                locateCount += 1
                return nil
            }
        )

        let cmux = capture.buildJumpTarget(
            env: ["CMUX_SURFACE_ID": "surface-1"],
            cwd: "/work/VibePet",
            hookEventName: "PreToolUse"
        )
        let code = capture.buildJumpTarget(
            env: ["TERM_PROGRAM": "vscode"],
            cwd: "/work/VibePet",
            hookEventName: "PreToolUse"
        )

        XCTAssertEqual(locateCount, 0)
        XCTAssertEqual(cmux?.terminalApp, "cmux")
        XCTAssertEqual(cmux?.terminalSessionID, "surface-1")
        XCTAssertEqual(code?.terminalApp, "VS Code")
        XCTAssertEqual(code?.terminalSessionID, nil)
    }
}

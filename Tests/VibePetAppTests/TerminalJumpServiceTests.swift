import XCTest
@testable import VibePetApp
@testable import VibePetCore

final class TerminalJumpServiceTests: XCTestCase {
    func testITermJumpUsesSessionIDBeforeTTY() throws {
        var scripts: [String] = []
        let service = TerminalJumpService(
            applicationResolver: { _ in nil },
            appRunningChecker: { _ in true },
            openAction: { _ in },
            appleScriptRunner: { script in
                scripts.append(script)
                return "matched"
            },
            processRunner: { _, _ in false },
            cmuxFocus: { _ in false }
        )

        try service.jump(to: JumpTarget(
            terminalApp: "iTerm",
            workingDirectory: "/tmp/VibePet",
            terminalSessionID: "session-1",
            terminalTTY: "/dev/ttys001"
        ))

        XCTAssertEqual(scripts.count, 1)
        XCTAssertTrue(scripts[0].contains("id of aSession as text"))
        XCTAssertTrue(scripts[0].contains("session-1"))
        XCTAssertTrue(scripts[0].contains("/dev/ttys001"))
    }

    func testTerminalJumpUsesTTYBeforeTitle() throws {
        var script = ""
        let service = TerminalJumpService(
            applicationResolver: { _ in nil },
            appRunningChecker: { _ in true },
            openAction: { _ in },
            appleScriptRunner: {
                script = $0
                return "matched"
            },
            processRunner: { _, _ in false },
            cmuxFocus: { _ in false }
        )

        try service.jump(to: JumpTarget(
            terminalApp: "Terminal",
            paneTitle: "Codex",
            terminalTTY: "/dev/ttys002"
        ))

        XCTAssertTrue(script.contains("tty of aTab as text"))
        XCTAssertTrue(script.contains("/dev/ttys002"))
        XCTAssertTrue(script.contains("custom title of aTab as text"))
        XCTAssertTrue(script.contains("Codex"))
    }

    func testTerminalJumpSelectsMatchedTabDirectly() throws {
        var script = ""
        let service = TerminalJumpService(
            applicationResolver: { _ in nil },
            appRunningChecker: { _ in true },
            openAction: { _ in },
            appleScriptRunner: {
                script = $0
                return "matched"
            },
            processRunner: { _, _ in false },
            cmuxFocus: { _ in false }
        )

        try service.jump(to: JumpTarget(terminalApp: "Terminal", terminalTTY: "/dev/ttys002"))

        XCTAssertTrue(script.contains("set selected of aTab to true"))
        XCTAssertTrue(script.contains("set frontmost of aWindow to true"))
    }

    func testGhosttyJumpUsesSessionThenCwdAndTitle() throws {
        var script = ""
        let service = TerminalJumpService(
            applicationResolver: { _ in nil },
            appRunningChecker: { _ in true },
            openAction: { _ in },
            appleScriptRunner: {
                script = $0
                return "matched"
            },
            processRunner: { _, _ in false },
            cmuxFocus: { _ in false }
        )

        try service.jump(to: JumpTarget(
            terminalApp: "Ghostty",
            paneTitle: "Codex",
            workingDirectory: "/tmp/VibePet",
            terminalSessionID: "ghostty-1"
        ))

        XCTAssertTrue(script.contains("id of aTerminal as text"))
        XCTAssertTrue(script.contains("ghostty-1"))
        XCTAssertTrue(script.contains("/tmp/VibePet"))
        XCTAssertTrue(script.contains("Codex"))
    }

    func testGhosttyJumpSelectsTabAndVerifiesFocusedTerminal() throws {
        var script = ""
        let service = TerminalJumpService(
            applicationResolver: { _ in nil },
            appRunningChecker: { _ in true },
            openAction: { _ in },
            appleScriptRunner: {
                script = $0
                return "matched"
            },
            processRunner: { _, _ in false },
            cmuxFocus: { _ in false }
        )

        try service.jump(to: JumpTarget(terminalApp: "Ghostty", terminalSessionID: "ghostty-1"))

        XCTAssertTrue(script.contains("set targetWindow to missing value"))
        XCTAssertTrue(script.contains("select tab targetTab"))
        XCTAssertTrue(script.contains("id of focused terminal of selected tab of front window as text"))
        XCTAssertTrue(script.contains("ghostty-1"))
    }

    func testCmuxJumpUsesSurfaceFocus() throws {
        var focusedSurfaceID: String?
        var opened: [[String]] = []
        let service = TerminalJumpService(
            applicationResolver: { _ in nil },
            appRunningChecker: { _ in true },
            openAction: { opened.append($0) },
            appleScriptRunner: { _ in "" },
            processRunner: { _, _ in false },
            cmuxFocus: {
                focusedSurfaceID = $0
                return true
            }
        )

        try service.jump(to: JumpTarget(terminalApp: "cmux", terminalSessionID: "surface-1"))

        XCTAssertEqual(focusedSurfaceID, "surface-1")
        XCTAssertEqual(opened, [["-b", "com.cmuxterm.app"]])
    }

    func testVSCodeJumpRunsCodeReuseWindow() throws {
        var processCalls: [(String, [String])] = []
        let service = TerminalJumpService(
            applicationResolver: { _ in nil },
            appRunningChecker: { _ in false },
            openAction: { _ in },
            appleScriptRunner: { _ in "" },
            processRunner: {
                processCalls.append(($0, $1))
                return true
            },
            cmuxFocus: { _ in false }
        )

        try service.jump(to: JumpTarget(terminalApp: "VS Code", workingDirectory: "/tmp/VibePet"))

        XCTAssertEqual(processCalls.count, 1)
        XCTAssertEqual(processCalls[0].0, "code")
        XCTAssertEqual(processCalls[0].1, ["-r", "/tmp/VibePet"])
    }

    func testFallbackActivatesAppBeforeOpeningCwd() throws {
        var opened: [[String]] = []
        let service = TerminalJumpService(
            applicationResolver: { _ in nil },
            appRunningChecker: { _ in true },
            openAction: { opened.append($0) },
            appleScriptRunner: { _ in "" },
            processRunner: { _, _ in false },
            cmuxFocus: { _ in false }
        )

        try service.jump(to: JumpTarget(
            terminalApp: "iTerm",
            workingDirectory: "/tmp/VibePet",
            terminalSessionID: "missing"
        ))

        XCTAssertEqual(opened, [["-b", "com.googlecode.iterm2"]])
    }

    func testUnknownTerminalOpensCwdFallback() throws {
        var opened: [[String]] = []
        let service = TerminalJumpService(
            applicationResolver: { _ in nil },
            appRunningChecker: { _ in false },
            openAction: { opened.append($0) },
            appleScriptRunner: { _ in "" },
            processRunner: { _, _ in false },
            cmuxFocus: { _ in false }
        )

        try service.jump(to: JumpTarget(terminalApp: "Unknown", workingDirectory: "/tmp/VibePet"))

        XCTAssertEqual(opened, [["/tmp/VibePet"]])
    }

    func testDefaultAppleScriptRunnerFailsOpenOnTimeout() throws {
        let started = Date()

        let output = try TerminalJumpService.defaultAppleScriptRunner(
            script: "delay 5\nreturn \"late\"",
            timeout: 0.05
        )

        XCTAssertEqual(output, "")
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }
}

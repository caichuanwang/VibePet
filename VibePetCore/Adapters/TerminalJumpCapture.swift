import Foundation

public struct TerminalJumpCapture: @unchecked Sendable {
    public struct CommandResult: Sendable {
        public var status: Int32
        public var stdout: String

        public init(status: Int32, stdout: String) {
            self.status = status
            self.stdout = stdout
        }
    }

    public struct LocatorSnapshot: Equatable, Sendable {
        public var sessionID: String?
        public var tty: String?
        public var title: String?

        public init(sessionID: String?, tty: String?, title: String?) {
            self.sessionID = sessionID.flatMap(Self.nonEmpty)
            self.tty = tty.flatMap(Self.nonEmpty)
            self.title = title.flatMap(Self.nonEmpty)
        }

        private static func nonEmpty(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    public typealias CommandRunner = (_ executable: String, _ arguments: [String]) -> CommandResult?
    public typealias CurrentTTYProvider = () -> String?
    public typealias TerminalLocator = (_ terminalApp: String, _ terminalTTY: String?) -> LocatorSnapshot?

    private let commandRunner: CommandRunner
    private let currentTTYProvider: CurrentTTYProvider?
    private let terminalLocator: TerminalLocator

    public init(
        commandRunner: @escaping CommandRunner = { executable, arguments in
            Self.defaultCommandRunner(executable: executable, arguments: arguments)
        },
        currentTTYProvider: CurrentTTYProvider? = nil,
        terminalLocator: @escaping TerminalLocator = Self.defaultTerminalLocator(for:matchingTTY:)
    ) {
        self.commandRunner = commandRunner
        self.currentTTYProvider = currentTTYProvider
        self.terminalLocator = terminalLocator
    }

    public static let live = TerminalJumpCapture()

    public static func inferTerminalApp(from env: [String: String]) -> String {
        if nonEmpty(env["CMUX_WORKSPACE_ID"]) != nil || nonEmpty(env["CMUX_SOCKET_PATH"]) != nil || nonEmpty(env["CMUX_SURFACE_ID"]) != nil {
            return "cmux"
        }

        if let termProgram = nonEmpty(env["TERM_PROGRAM"])?.lowercased() {
            if termProgram == "apple_terminal" {
                return "Terminal"
            }
            if termProgram == "iterm.app" || termProgram == "iterm2" || termProgram == "iterm" {
                return "iTerm"
            }
            if termProgram.contains("ghostty") {
                return "Ghostty"
            }
            if termProgram.contains("vscode") {
                return "VS Code"
            }
        }

        if nonEmpty(env["ITERM_SESSION_ID"]) != nil || nonEmpty(env["LC_TERMINAL"])?.lowercased() == "iterm2" {
            return "iTerm"
        }
        if nonEmpty(env["GHOSTTY_RESOURCES_DIR"]) != nil {
            return "Ghostty"
        }
        return "Unknown"
    }

    public static func workspaceName(from cwd: String?) -> String? {
        guard let cwd = nonEmpty(cwd) else { return nil }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return nonEmpty(name)
    }

    public func currentTTY(parentProcessID: Int32 = getppid()) -> String? {
        if let provided = currentTTYProvider {
            return normalizeTTY(provided())
        }

        if let result = commandRunner("/usr/bin/tty", []),
           result.status == 0,
           let tty = normalizeTTY(result.stdout) {
            return tty
        }

        if let result = commandRunner("/bin/ps", ["-p", "\(parentProcessID)", "-o", "tty="]),
           result.status == 0,
           let tty = normalizeTTY(result.stdout) {
            return tty
        }

        return nil
    }

    public func buildJumpTarget(
        env: [String: String],
        cwd: String?,
        hookEventName: String?
    ) -> JumpTarget? {
        let terminalApp = Self.inferTerminalApp(from: env)
        let workingDirectory = Self.nonEmpty(cwd)
        let workspaceName = Self.workspaceName(from: workingDirectory)
        let tty = currentTTY()
        var snapshot: LocatorSnapshot?

        switch terminalApp {
        case "iTerm", "Terminal":
            if let tty,
               let candidate = terminalLocator(terminalApp, tty),
               normalizeTTY(candidate.tty) == tty {
                snapshot = candidate
            }
        default:
            snapshot = nil
        }

        let sessionID = terminalApp == "cmux" ? Self.nonEmpty(env["CMUX_SURFACE_ID"]) : snapshot?.sessionID
        // A process-derived TTY identifies the hook's actual terminal. A frontmost
        // locator result may enrich its session/title, but may never replace that TTY.
        let terminalTTY = tty ?? snapshot?.tty
        let paneTitle = snapshot?.title

        guard terminalApp != "Unknown" || workingDirectory != nil || terminalTTY != nil else {
            return nil
        }

        return JumpTarget(
            terminalApp: terminalApp,
            workspaceName: workspaceName,
            paneTitle: paneTitle,
            workingDirectory: workingDirectory,
            terminalSessionID: sessionID,
            terminalTTY: terminalTTY
        )
    }

    public static func defaultCommandRunner(
        executable: String,
        arguments: [String],
        timeout: TimeInterval = 1.5
    ) -> CommandResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            guard wait(for: process, timeout: timeout) else {
                return nil
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: data, encoding: .utf8) ?? ""
            return CommandResult(status: process.terminationStatus, stdout: stdout)
        } catch {
            return nil
        }
    }

    public static func defaultTerminalLocator(for terminalApp: String, matchingTTY: String? = nil) -> LocatorSnapshot? {
        let escapedTTY = escapeAppleScript(matchingTTY)
        let script: String
        switch terminalApp {
        case "iTerm":
            script = """
            tell application "iTerm"
                if not (it is running) then return ""
                if "\(escapedTTY)" is not "" then
                    repeat with aWindow in windows
                        repeat with aTab in tabs of aWindow
                            repeat with s in sessions of aTab
                                if (tty of s as text) is "\(escapedTTY)" then
                                    return (id of s as text) & "\t" & (tty of s as text) & "\t" & (name of s as text)
                                end if
                            end repeat
                        end repeat
                    end repeat
                    return ""
                end if
                set s to current session of current window
                return (id of s as text) & "\t" & (tty of s as text) & "\t" & (name of s as text)
            end tell
            """
        case "Terminal":
            script = """
            tell application "Terminal"
                if not (it is running) then return ""
                if "\(escapedTTY)" is not "" then
                    repeat with aWindow in windows
                        repeat with t in tabs of aWindow
                            if (tty of t as text) is "\(escapedTTY)" then
                                return "\t" & (tty of t as text) & "\t" & (custom title of t as text)
                            end if
                        end repeat
                    end repeat
                    return ""
                end if
                set t to selected tab of front window
                return "\t" & (tty of t as text) & "\t" & (custom title of t as text)
            end tell
            """
        case "Ghostty":
            script = """
            tell application "Ghostty"
                if not (it is running) then return ""
                set t to focused terminal of selected tab of front window
                return (id of t as text) & "\t\t" & (name of t as text)
            end tell
            """
        default:
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            guard wait(for: process, timeout: 1.5) else {
                return nil
            }
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return parseLocatorOutput(text)
        } catch {
            return nil
        }
    }

    private static func escapeAppleScript(_ value: String?) -> String {
        (value ?? "")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    public static func parseLocatorOutput(_ output: String) -> LocatorSnapshot? {
        let parts = output.trimmingCharacters(in: .newlines).components(separatedBy: "\t")
        guard !parts.isEmpty else { return nil }
        return LocatorSnapshot(
            sessionID: parts.indices.contains(0) ? parts[0] : nil,
            tty: parts.indices.contains(1) ? parts[1] : nil,
            title: parts.indices.contains(2) ? parts[2] : nil
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizeTTY(_ value: String?) -> String? {
        guard let trimmed = Self.nonEmpty(value), trimmed.lowercased() != "not a tty" else {
            return nil
        }
        if trimmed.hasPrefix("/dev/") {
            return trimmed
        }
        if trimmed.hasPrefix("tty") {
            return "/dev/\(trimmed)"
        }
        return nil
    }

    @discardableResult
    private static func wait(for process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                Thread.sleep(forTimeInterval: 0.02)
                if process.isRunning {
                    process.interrupt()
                }
                return false
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return true
    }
}

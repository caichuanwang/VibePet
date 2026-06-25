import AppKit
import Foundation
import VibePetCore

enum TerminalJumpError: Error, Equatable {
    case unsupportedTerminal(String)
}

struct TerminalJumpService {
    typealias ApplicationResolver = (String) -> URL?
    typealias AppRunningChecker = (String) -> Bool
    typealias OpenAction = ([String]) throws -> Void
    typealias AppleScriptRunner = (String) throws -> String
    typealias ProcessRunner = (String, [String]) -> Bool
    typealias CmuxFocus = (String) -> Bool

    private struct Descriptor {
        var displayName: String
        var bundleID: String
        var aliases: Set<String>
    }

    private static let descriptors: [Descriptor] = [
        Descriptor(displayName: "iTerm", bundleID: "com.googlecode.iterm2", aliases: ["iterm", "iterm2", "iterm.app"]),
        Descriptor(displayName: "Terminal", bundleID: "com.apple.Terminal", aliases: ["terminal", "apple_terminal"]),
        Descriptor(displayName: "Ghostty", bundleID: "com.mitchellh.ghostty", aliases: ["ghostty"]),
        Descriptor(displayName: "cmux", bundleID: "com.cmuxterm.app", aliases: ["cmux"]),
        Descriptor(displayName: "VS Code", bundleID: "com.microsoft.VSCode", aliases: ["vs code", "vscode", "code", "visual studio code"]),
    ]
    private static let ghosttyFocusSettleDelay = 0.08
    private static let ghosttyWindowActivationDelay = 0.04
    private static let ghosttyFocusAttempts = 3

    private let applicationResolver: ApplicationResolver
    private let appRunningChecker: AppRunningChecker
    private let openAction: OpenAction
    private let appleScriptRunner: AppleScriptRunner
    private let processRunner: ProcessRunner
    private let cmuxFocus: CmuxFocus

    init(
        applicationResolver: @escaping ApplicationResolver = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
        appRunningChecker: @escaping AppRunningChecker = { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty },
        openAction: @escaping OpenAction = Self.defaultOpenAction(arguments:),
        appleScriptRunner: @escaping AppleScriptRunner = { script in
            try Self.defaultAppleScriptRunner(script: script)
        },
        processRunner: @escaping ProcessRunner = Self.defaultProcessRunner(executable:arguments:),
        cmuxFocus: @escaping CmuxFocus = Self.defaultCmuxFocus(surfaceID:)
    ) {
        self.applicationResolver = applicationResolver
        self.appRunningChecker = appRunningChecker
        self.openAction = openAction
        self.appleScriptRunner = appleScriptRunner
        self.processRunner = processRunner
        self.cmuxFocus = cmuxFocus
    }

    func jump(to target: JumpTarget) throws {
        let descriptor = descriptor(for: target.terminalApp)

        switch normalized(target.terminalApp) {
        case "iterm":
            if try jumpToITerm(target) { return }
        case "terminal":
            if try jumpToTerminal(target) { return }
        case "ghostty":
            if try jumpToGhostty(target) { return }
        case "cmux":
            if let surfaceID = nonEmpty(target.terminalSessionID), cmuxFocus(surfaceID) {
                try? openAction(["-b", "com.cmuxterm.app"])
                return
            }
        case "vs code", "vscode", "code", "visual studio code":
            if let cwd = nonEmpty(target.workingDirectory), processRunner("code", ["-r", cwd]) {
                return
            }
        default:
            break
        }

        try fallback(to: target, descriptor: descriptor)
    }

    private func jumpToITerm(_ target: JumpTarget) throws -> Bool {
        let script = """
        tell application "iTerm"
            if not (it is running) then return ""
            activate
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        set matched to false
                        if "\(escapeAppleScript(target.terminalSessionID))" is not "" and (id of aSession as text) is "\(escapeAppleScript(target.terminalSessionID))" then set matched to true
                        if not matched and "\(escapeAppleScript(target.terminalTTY))" is not "" and (tty of aSession as text) is "\(escapeAppleScript(target.terminalTTY))" then set matched to true
                        if matched then
                            select aWindow
                            tell aWindow to select aTab
                            select aSession
                            return "matched"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return ""
        """
        return try appleScriptRunner(script) == "matched"
    }

    private func jumpToTerminal(_ target: JumpTarget) throws -> Bool {
        let script = """
        tell application "Terminal"
            if not (it is running) then return ""
            activate
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    if "\(escapeAppleScript(target.terminalTTY))" is not "" and (tty of aTab as text) is "\(escapeAppleScript(target.terminalTTY))" then
                        set selected of aTab to true
                        set frontmost of aWindow to true
                        return "matched"
                    end if
                    if "\(escapeAppleScript(target.paneTitle))" is not "" and (custom title of aTab as text) contains "\(escapeAppleScript(target.paneTitle))" then
                        set selected of aTab to true
                        set frontmost of aWindow to true
                        return "matched"
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """
        return try appleScriptRunner(script) == "matched"
    }

    private func jumpToGhostty(_ target: JumpTarget) throws -> Bool {
        let terminalSessionID = escapeAppleScript(target.terminalSessionID)
        let workingDirectory = escapeAppleScript(target.workingDirectory)
        let paneTitle = escapeAppleScript(target.paneTitle)

        let script = """
        tell application "Ghostty"
            if not (it is running) then return ""
            activate

            set targetWindow to missing value
            set targetTab to missing value
            set targetTerminal to missing value

            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aTerminal in terminals of aTab
                        if "\(terminalSessionID)" is not "" and (id of aTerminal as text) is "\(terminalSessionID)" then
                            set targetWindow to aWindow
                            set targetTab to aTab
                            set targetTerminal to aTerminal
                            exit repeat
                        end if
                    end repeat
                    if targetTerminal is not missing value then exit repeat
                end repeat
                if targetTerminal is not missing value then exit repeat
            end repeat

            if targetTerminal is missing value and "\(workingDirectory)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            if (working directory of aTerminal as text) is "\(workingDirectory)" then
                                set targetWindow to aWindow
                                set targetTab to aTab
                                set targetTerminal to aTerminal
                                exit repeat
                            end if
                        end repeat
                        if targetTerminal is not missing value then exit repeat
                    end repeat
                    if targetTerminal is not missing value then exit repeat
                end repeat
            end if

            if targetTerminal is missing value and "\(paneTitle)" is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aTerminal in terminals of aTab
                            if (name of aTerminal as text) contains "\(paneTitle)" then
                                set targetWindow to aWindow
                                set targetTab to aTab
                                set targetTerminal to aTerminal
                                exit repeat
                            end if
                        end repeat
                        if targetTerminal is not missing value then exit repeat
                    end repeat
                    if targetTerminal is not missing value then exit repeat
                end repeat
            end if

            if targetTerminal is missing value then return ""

            if "\(terminalSessionID)" is "" then
                if targetWindow is not missing value then
                    activate window targetWindow
                    delay \(Self.ghosttyWindowActivationDelay)
                end if
                if targetTab is not missing value then
                    select tab targetTab
                    delay \(Self.ghosttyWindowActivationDelay)
                end if
                focus targetTerminal
                delay \(Self.ghosttyFocusSettleDelay)
                return "matched"
            end if

            repeat \(Self.ghosttyFocusAttempts) times
                if targetWindow is not missing value then
                    activate window targetWindow
                    delay \(Self.ghosttyWindowActivationDelay)
                end if
                if targetTab is not missing value then
                    select tab targetTab
                    delay \(Self.ghosttyWindowActivationDelay)
                end if
                focus targetTerminal
                delay \(Self.ghosttyFocusSettleDelay)
                try
                    if (id of focused terminal of selected tab of front window as text) is "\(terminalSessionID)" then
                        return "matched"
                    end if
                end try
            end repeat
        end tell
        return ""
        """
        return try appleScriptRunner(script) == "matched"
    }

    private func fallback(to target: JumpTarget, descriptor: Descriptor?) throws {
        if let descriptor, appRunningChecker(descriptor.bundleID) || applicationResolver(descriptor.bundleID) != nil {
            try openAction(["-b", descriptor.bundleID])
            return
        }
        if let cwd = nonEmpty(target.workingDirectory) {
            try openAction([cwd])
            return
        }
        throw TerminalJumpError.unsupportedTerminal(target.terminalApp)
    }

    private func descriptor(for app: String) -> Descriptor? {
        let name = normalized(app)
        return Self.descriptors.first { descriptor in
            descriptor.aliases.contains(name) || normalized(descriptor.displayName) == name
        }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func escapeAppleScript(_ value: String?) -> String {
        nonEmpty(value)?
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") ?? ""
    }

    private static func defaultOpenAction(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        try process.run()
        _ = wait(for: process, timeout: 1.5)
    }

    static func defaultAppleScriptRunner(script: String, timeout: TimeInterval = 3) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        guard wait(for: process, timeout: timeout) else { return "" }
        guard process.terminationStatus == 0 else { return "" }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func defaultProcessRunner(executable: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            guard wait(for: process, timeout: 2) else { return false }
            return process.terminationStatus == 0
        } catch {
            return false
        }
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

    private static func defaultCmuxFocus(surfaceID: String) -> Bool {
        guard let socketPath = resolveCmuxSocketPath() else {
            return false
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            return false
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { bytes in
            for (index, byte) in pathBytes.enumerated() {
                bytes[index] = UInt8(bitPattern: byte)
            }
        }

        let connected = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return false }

        let request = #"{"jsonrpc":"2.0","method":"surface.focus","params":{"surface_id":"\#(surfaceID)"},"id":1}"# + "\n"
        let sent = request.withCString { pointer in
            Darwin.send(fd, pointer, strlen(pointer), 0)
        }
        return sent > 0
    }

    private static func resolveCmuxSocketPath() -> String? {
        let fileManager = FileManager.default
        let redirected = (try? String(contentsOfFile: "/tmp/cmux-last-socket-path", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [
            redirected,
            NSHomeDirectory() + "/Library/Application Support/cmux/cmux.sock",
            "/tmp/cmux.sock",
        ].compactMap { $0 }

        return candidates.first { !$0.isEmpty && fileManager.fileExists(atPath: $0) }
    }
}

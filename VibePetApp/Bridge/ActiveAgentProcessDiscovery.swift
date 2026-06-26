import Foundation
import VibePetCore

struct ActiveAgentSession: Equatable, Sendable {
    var id: String
    var title: String
    var tool: ToolKind
    var summary: String
    var jumpTarget: JumpTarget?
}

struct ActiveAgentProcessDiscovery: Sendable {
    typealias CommandRunner = @Sendable (_ executablePath: String, _ arguments: [String]) -> String?

    private final class OutputBox: @unchecked Sendable {
        var data = Data()
    }

    private struct ProcessRow: Sendable {
        var pid: String
        var parentPID: String
        var terminalTTY: String?
        var command: String
    }

    private let commandRunner: CommandRunner

    init(commandRunner: @escaping CommandRunner = Self.commandOutput) {
        self.commandRunner = commandRunner
    }

    func discover() -> [ActiveAgentSession] {
        let processes = runningProcesses()
        guard !processes.isEmpty else {
            return []
        }
        let processesByPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })

        return processes.compactMap { process in
            guard process.terminalTTY != nil, !isVibePetHookCommand(process.command) else {
                return nil
            }

            if isCodexCommand(process.command) {
                return makeSession(for: process, tool: .codex, processesByPID: processesByPID)
            }
            if isClaudeCommand(process.command) {
                return makeSession(for: process, tool: .claudeCode, processesByPID: processesByPID)
            }
            return nil
        }
    }

    private func runningProcesses() -> [ProcessRow] {
        guard let output = commandRunner("/bin/ps", ["-Ao", "pid=,ppid=,tty=,command="]) else {
            return []
        }

        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> ProcessRow? in
                let parts = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(maxSplits: 3, whereSeparator: \.isWhitespace)
                guard parts.count == 4 else { return nil }
                let command = String(parts[3]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !command.isEmpty else { return nil }
                return ProcessRow(
                    pid: String(parts[0]),
                    parentPID: String(parts[1]),
                    terminalTTY: Self.normalizedTTY(String(parts[2])),
                    command: command
                )
            }
    }

    private func makeSession(
        for process: ProcessRow,
        tool: ToolKind,
        processesByPID: [String: ProcessRow]
    ) -> ActiveAgentSession {
        let cwd = lsofOutput(pid: process.pid).flatMap(workingDirectory(from:))
        let terminalApp = terminalApp(for: process, processesByPID: processesByPID) ?? "Terminal"
        let title = cwd.flatMap { URL(fileURLWithPath: $0).lastPathComponent.nilIfEmpty } ?? toolTitle(tool)
        return ActiveAgentSession(
            id: "discovered-\(tool.rawValue)-\(process.pid)",
            title: title,
            tool: tool,
            summary: "Detected running \(toolTitle(tool))",
            jumpTarget: JumpTarget(
                terminalApp: terminalApp,
                workingDirectory: cwd,
                terminalTTY: process.terminalTTY
            )
        )
    }

    private func terminalApp(for process: ProcessRow, processesByPID: [String: ProcessRow]) -> String? {
        if let app = terminalApp(from: process.command) {
            return app
        }

        var visited: Set<String> = [process.pid]
        var currentParentPID = process.parentPID
        while let parent = processesByPID[currentParentPID], visited.insert(parent.pid).inserted {
            if let app = terminalApp(from: parent.command) {
                return app
            }
            currentParentPID = parent.parentPID
        }
        return nil
    }

    private func lsofOutput(pid: String) -> String? {
        commandRunner("/usr/sbin/lsof", ["-a", "-p", pid, "-d", "cwd", "-Fn"])
    }

    private func workingDirectory(from output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .lazy
            .map(String.init)
            .first { $0.hasPrefix("n/") }?
            .dropFirst()
            .description
            .nilIfEmpty
    }

    private func terminalApp(from command: String) -> String? {
        let lowercased = command.lowercased()
        if isCmuxHostCommand(lowercased) { return "cmux" }
        if lowercased.contains("ghostty") { return "Ghostty" }
        if lowercased.contains("iterm") { return "iTerm" }
        if lowercased.contains("terminal") { return "Terminal" }
        return nil
    }

    private func isCmuxHostCommand(_ lowercasedCommand: String) -> Bool {
        lowercasedCommand.contains("/applications/cmux.app/contents/macos/cmux")
            || lowercasedCommand.contains("/cmux.app/contents/macos/cmux")
            || lowercasedCommand.contains("/cmux-surface-resume/")
    }

    private func isCodexCommand(_ command: String) -> Bool {
        let lowercased = command.lowercased()
        if lowercased.contains(" app-server") || lowercased.contains("node_repl") {
            return false
        }
        guard let firstToken = lowercased.split(separator: " ").first.map(String.init) else {
            return false
        }
        return firstToken == "codex"
            || firstToken.hasSuffix("/codex")
            || lowercased.contains("/@openai/codex/")
    }

    private func isClaudeCommand(_ command: String) -> Bool {
        let lowercased = command.lowercased()
        guard let firstToken = lowercased.split(separator: " ").first.map(String.init) else {
            return false
        }
        return firstToken == "claude"
            || firstToken.hasSuffix("/claude")
            || lowercased.contains("/.local/bin/claude")
    }

    private func isVibePetHookCommand(_ command: String) -> Bool {
        command.lowercased().contains("vibepethooks")
    }

    private func toolTitle(_ tool: ToolKind) -> String {
        switch tool {
        case .claudeCode:
            "Claude Code"
        case .codex:
            "Codex"
        }
    }

    private static func commandOutput(executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let exitGroup = DispatchGroup()
        let outputGroup = DispatchGroup()
        let outputBox = OutputBox()

        do {
            exitGroup.enter()
            process.terminationHandler = { _ in exitGroup.leave() }
            outputGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                outputBox.data = pipe.fileHandleForReading.readDataToEndOfFile()
                outputGroup.leave()
            }
            try process.run()
            guard exitGroup.wait(timeout: .now() + 0.5) == .success else {
                process.terminate()
                return nil
            }
            guard process.terminationStatus == 0 else {
                return nil
            }
            _ = outputGroup.wait(timeout: .now() + 0.1)
            let output = String(data: outputBox.data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.nilIfEmpty
        } catch {
            return nil
        }
    }

    private static func normalizedTTY(_ tty: String) -> String? {
        guard tty != "??" else { return nil }
        return tty.replacingOccurrences(of: "/dev/", with: "")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

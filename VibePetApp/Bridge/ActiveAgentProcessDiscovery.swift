import Foundation
import VibePetCore

struct ActiveAgentSession: Equatable, Sendable {
    var id: String
    var title: String
    var tool: ToolKind
    var summary: String
    var jumpTarget: JumpTarget?
    var nativeSessionID: String? = nil
    var transcriptPath: String? = nil
    var processID: String? = nil
    var parentProcessID: String? = nil
}

enum ActiveAgentProcessScan: Equatable, Sendable {
    case success([ActiveAgentSession])
    case failure
}

/// A single process-table snapshot used for both discovery and liveness.
/// Adapted from open-vibe-island's `ActiveAgentProcessDiscovery`, narrowed to
/// Claude Code and Codex.
struct ActiveAgentProcessDiscovery: Sendable {
    typealias CommandRunner = @Sendable (_ executablePath: String, _ arguments: [String]) -> String?

    private static let processCommandTimeout: TimeInterval = 2
    private static let lsofCommandTimeout: TimeInterval = 0.25

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

    func scan() -> ActiveAgentProcessScan {
        guard let processes = runningProcesses() else {
            return .failure
        }
        guard !processes.isEmpty else {
            return .success([])
        }

        let processesByPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        var sessions: [ActiveAgentSession] = []
        var claimedKeys: Set<String> = []

        for process in processes where !isVibePetHookCommand(process.command) {
            let tool: ToolKind
            if isCodexCommand(process.command) {
                tool = .codex
            } else if isClaudeCommand(process.command) {
                tool = .claudeCode
            } else {
                continue
            }

            let lsof = lsofOutput(pid: process.pid)
            let cwd = lsof.flatMap(workingDirectory(from:))
            let transcriptPath: String?
            let nativeSessionID: String?
            switch tool {
            case .codex:
                transcriptPath = lsof.flatMap(bestCodexTranscriptPath(in:))
                nativeSessionID = transcriptPath.flatMap(firstUUID(in:))
            case .claudeCode:
                transcriptPath = lsof.flatMap {
                    bestClaudeTranscriptPath(in: $0, workingDirectory: cwd)
                }
                nativeSessionID = transcriptPath.flatMap(firstUUID(in:))
                    ?? claudeSessionID(from: process.command)
            }

            // Headless sessions are valid only when the process exposes a precise
            // native identity. A cwd alone is too broad and commonly belongs to helpers.
            guard process.terminalTTY != nil || nativeSessionID != nil || transcriptPath != nil else {
                continue
            }

            let identity = claimIdentity(
                tool: tool,
                nativeSessionID: nativeSessionID,
                transcriptPath: transcriptPath,
                terminalTTY: process.terminalTTY,
                workingDirectory: cwd
            )
            guard claimedKeys.insert(identity).inserted else {
                continue
            }

            let terminalApp = terminalApp(for: process, processesByPID: processesByPID) ?? "Terminal"
            let title = cwd.flatMap { URL(fileURLWithPath: $0).lastPathComponent.nilIfEmpty }
                ?? toolTitle(tool)
            let id: String
            if let nativeSessionID {
                id = "discovered-\(tool.rawValue)-\(nativeSessionID)"
            } else {
                id = "discovered-\(tool.rawValue)-synthetic-\(Self.stableHash(identity))"
            }
            sessions.append(ActiveAgentSession(
                id: id,
                title: title,
                tool: tool,
                summary: "Detected running \(toolTitle(tool))",
                jumpTarget: JumpTarget(
                    terminalApp: terminalApp,
                    workingDirectory: cwd,
                    terminalTTY: process.terminalTTY
                ),
                nativeSessionID: nativeSessionID,
                transcriptPath: transcriptPath,
                processID: process.pid,
                parentProcessID: process.parentPID
            ))
        }

        return .success(sessions)
    }

    func discover() -> [ActiveAgentSession] {
        guard case let .success(sessions) = scan() else {
            return []
        }
        return sessions
    }

    private func runningProcesses() -> [ProcessRow]? {
        guard let output = commandRunner("/bin/ps", ["-Ao", "pid=,ppid=,tty=,command="]) else {
            return nil
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

    private func claimIdentity(
        tool: ToolKind,
        nativeSessionID: String?,
        transcriptPath: String?,
        terminalTTY: String?,
        workingDirectory: String?
    ) -> String {
        if let nativeSessionID {
            return "\(tool.rawValue):native:\(nativeSessionID.lowercased())"
        }
        if let transcriptPath {
            return "\(tool.rawValue):transcript:\(transcriptPath)"
        }
        return [
            tool.rawValue,
            terminalTTY.map { "tty:\($0)" } ?? "tty:-",
            workingDirectory.map { "cwd:\(Self.normalizedWorkingDirectory($0))" } ?? "cwd:-",
        ].joined(separator: "|")
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
        commandRunner("/usr/sbin/lsof", ["-a", "-p", pid, "-Fn"])
    }

    private func workingDirectory(from output: String) -> String? {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        for index in lines.indices where lines[index] == "fcwd" {
            let next = lines.index(after: index)
            guard lines.indices.contains(next), lines[next].hasPrefix("n/") else { continue }
            return String(lines[next].dropFirst()).nilIfEmpty
        }

        // Retain compatibility with older injected fixtures that only returned cwd.
        return lines.lazy
            .first { $0.hasPrefix("n/") && !$0.hasSuffix(".jsonl") }?
            .dropFirst()
            .description
            .nilIfEmpty
    }

    private func bestCodexTranscriptPath(in output: String) -> String? {
        allMatchingPaths(in: output, containing: "/.codex/sessions/", suffix: ".jsonl")
            .max { codexRolloutSortKey(for: $0) < codexRolloutSortKey(for: $1) }
    }

    private func codexRolloutSortKey(for path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    private func bestClaudeTranscriptPath(in output: String, workingDirectory: String?) -> String? {
        let paths = allMatchingPaths(in: output, containing: "/.claude/projects/", suffix: ".jsonl")
        guard paths.count > 1 else { return paths.first }
        if let workingDirectory {
            let encodedCWD = workingDirectory.replacingOccurrences(of: "/", with: "-")
            if let preferred = paths.first(where: { $0.contains(encodedCWD) }) {
                return preferred
            }
        }
        return paths.first
    }

    private func allMatchingPaths(in output: String, containing fragment: String, suffix: String) -> [String] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.first == "n" else { return nil }
            let path = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return path.contains(fragment) && path.hasSuffix(suffix) ? path : nil
        }
    }

    private func firstUUID(in text: String) -> String? {
        let pattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }
        return String(text[matchRange]).lowercased()
    }

    private func claudeSessionID(from command: String) -> String? {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        for index in tokens.indices {
            let token = tokens[index]
            if token == "--resume" || token == "-r" || token == "--session-id" {
                let next = tokens.index(after: index)
                if tokens.indices.contains(next), let id = firstUUID(in: tokens[next]) {
                    return id
                }
            }
            if token.hasPrefix("--resume=") || token.hasPrefix("--session-id=") {
                let value = String(token.split(separator: "=", maxSplits: 1).last ?? "")
                if let id = firstUUID(in: value) { return id }
            }
        }
        return nil
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
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// Concurrently drains stdout while waiting for termination so output larger
    /// than the pipe capacity cannot block the child process.
    static func commandOutput(executablePath: String, arguments: [String]) -> String? {
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
            let timeout = executablePath == "/usr/sbin/lsof"
                ? lsofCommandTimeout
                : processCommandTimeout
            guard exitGroup.wait(timeout: .now() + timeout) == .success else {
                process.terminate()
                _ = outputGroup.wait(timeout: .now() + timeout)
                return nil
            }
            guard process.terminationStatus == 0,
                  outputGroup.wait(timeout: .now() + timeout) == .success else {
                return nil
            }
            return String(data: outputBox.data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    static func normalizedTTY(_ tty: String) -> String? {
        guard tty != "??" else { return nil }
        return tty.replacingOccurrences(of: "/dev/", with: "")
    }

    static func normalizedWorkingDirectory(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

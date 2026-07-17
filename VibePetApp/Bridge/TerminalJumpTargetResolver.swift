import Foundation
import VibePetCore

struct TerminalJumpTargetResolver: Sendable {
    struct GhosttySnapshot: Sendable {
        var sessionID: String
        var workingDirectory: String
        var title: String
    }

    struct TerminalSnapshot: Sendable {
        var tty: String
        var title: String
    }

    typealias GhosttySnapshotProvider = @Sendable () -> [GhosttySnapshot]?
    typealias TerminalSnapshotProvider = @Sendable () -> [TerminalSnapshot]?

    private let ghosttySnapshots: GhosttySnapshotProvider
    private let terminalSnapshots: TerminalSnapshotProvider

    init(
        ghosttySnapshots: @escaping GhosttySnapshotProvider = Self.fetchGhosttySnapshots,
        terminalSnapshots: @escaping TerminalSnapshotProvider = Self.fetchTerminalSnapshots
    ) {
        self.ghosttySnapshots = ghosttySnapshots
        self.terminalSnapshots = terminalSnapshots
    }

    func resolveJumpTargets(for sessions: [AgentSession]) -> [String: JumpTarget] {
        let ghosttySessions = sessions.filter { normalized($0.jumpTarget?.terminalApp) == "ghostty" }
        let terminalSessions = sessions.filter { normalized($0.jumpTarget?.terminalApp) == "terminal" }
        guard !ghosttySessions.isEmpty || !terminalSessions.isEmpty else {
            return [:]
        }

        var updates: [String: JumpTarget] = [:]

        if !ghosttySessions.isEmpty, let snapshots = ghosttySnapshots() {
            for (session, snapshot) in matchGhostty(snapshots: snapshots, sessions: ghosttySessions) {
                if let corrected = correctedGhosttyTarget(for: session, snapshot: snapshot) {
                    updates[session.id] = corrected
                }
            }
        }

        if !terminalSessions.isEmpty, let snapshots = terminalSnapshots() {
            for (session, snapshot) in matchTerminal(snapshots: snapshots, sessions: terminalSessions) {
                if let corrected = correctedTerminalTarget(for: session, snapshot: snapshot) {
                    updates[session.id] = corrected
                }
            }
        }

        return updates
    }

    private func matchGhostty(
        snapshots: [GhosttySnapshot],
        sessions: [AgentSession]
    ) -> [(AgentSession, GhosttySnapshot)] {
        var result: [(AgentSession, GhosttySnapshot)] = []
        var usedSessionIDs: Set<String> = []
        var usedSnapshotIDs: Set<String> = []

        func assignExactIDs() {
            for snapshot in snapshots where !usedSnapshotIDs.contains(snapshot.sessionID) {
                let matches = sessions.filter {
                    !usedSessionIDs.contains($0.id)
                        && nonEmpty($0.jumpTarget?.terminalSessionID) == snapshot.sessionID
                }
                guard matches.count == 1, let session = matches.first else { continue }
                result.append((session, snapshot))
                usedSessionIDs.insert(session.id)
                usedSnapshotIDs.insert(snapshot.sessionID)
            }
        }

        func assignUniqueWeakMatches(where predicate: (AgentSession, GhosttySnapshot) -> Bool) {
            for snapshot in snapshots where !usedSnapshotIDs.contains(snapshot.sessionID) {
                let candidates = sessions.filter {
                    !usedSessionIDs.contains($0.id) && predicate($0, snapshot)
                }
                guard candidates.count == 1, let session = candidates.first else { continue }
                let competingSnapshots = snapshots.filter {
                    !usedSnapshotIDs.contains($0.sessionID) && predicate(session, $0)
                }
                guard competingSnapshots.count == 1 else { continue }
                result.append((session, snapshot))
                usedSessionIDs.insert(session.id)
                usedSnapshotIDs.insert(snapshot.sessionID)
            }
        }

        assignExactIDs()
        assignUniqueWeakMatches {
            guard let sessionPath = normalizedPath($0.jumpTarget?.workingDirectory),
                  let snapshotPath = normalizedPath($1.workingDirectory) else { return false }
            return sessionPath == snapshotPath
        }
        assignUniqueWeakMatches {
            guard let title = nonEmpty($0.jumpTarget?.paneTitle),
                  let snapshotTitle = nonEmpty($1.title) else { return false }
            return snapshotTitle.localizedCaseInsensitiveContains(title)
        }

        return result
    }

    private func correctedGhosttyTarget(for session: AgentSession, snapshot: GhosttySnapshot) -> JumpTarget? {
        var target = session.jumpTarget ?? JumpTarget(terminalApp: "Ghostty")
        var changed = false

        changed = set(&target.terminalApp, "Ghostty") || changed
        changed = set(&target.terminalSessionID, snapshot.sessionID) || changed
        if let workingDirectory = nonEmpty(snapshot.workingDirectory) {
            changed = set(&target.workingDirectory, workingDirectory) || changed
            changed = set(
                &target.workspaceName,
                URL(fileURLWithPath: workingDirectory).standardizedFileURL.lastPathComponent
            ) || changed
        }
        if let title = nonEmpty(snapshot.title) {
            changed = set(&target.paneTitle, title) || changed
        }

        return changed ? target : nil
    }

    private func matchTerminal(
        snapshots: [TerminalSnapshot],
        sessions: [AgentSession]
    ) -> [(AgentSession, TerminalSnapshot)] {
        var result: [(AgentSession, TerminalSnapshot)] = []
        var usedSessionIDs: Set<String> = []
        var usedTTYs: Set<String> = []

        func assignUnique(where predicate: (AgentSession, TerminalSnapshot) -> Bool) {
            for snapshot in snapshots where !usedTTYs.contains(snapshot.tty) {
                let candidates = sessions.filter {
                    !usedSessionIDs.contains($0.id) && predicate($0, snapshot)
                }
                guard candidates.count == 1, let session = candidates.first else { continue }
                let competingSnapshots = snapshots.filter {
                    !usedTTYs.contains($0.tty) && predicate(session, $0)
                }
                guard competingSnapshots.count == 1 else { continue }
                result.append((session, snapshot))
                usedSessionIDs.insert(session.id)
                usedTTYs.insert(snapshot.tty)
            }
        }

        assignUnique { normalizedTTY($0.jumpTarget?.terminalTTY) == normalizedTTY($1.tty) }
        assignUnique {
            guard let title = nonEmpty($0.jumpTarget?.paneTitle) else { return false }
            return $1.title.localizedCaseInsensitiveContains(title)
        }

        return result
    }

    private func correctedTerminalTarget(for session: AgentSession, snapshot: TerminalSnapshot) -> JumpTarget? {
        guard var target = session.jumpTarget else { return nil }
        var changed = false

        changed = set(&target.terminalApp, "Terminal") || changed
        changed = set(&target.terminalTTY, snapshot.tty) || changed
        changed = set(&target.paneTitle, snapshot.title) || changed

        return changed ? target : nil
    }

    private func set(_ field: inout String, _ value: String) -> Bool {
        guard field != value else { return false }
        field = value
        return true
    }

    private func set(_ field: inout String?, _ value: String?) -> Bool {
        let value = nonEmpty(value)
        guard field != value else { return false }
        field = value
        return true
    }

    private func normalized(_ value: String?) -> String {
        nonEmpty(value)?.lowercased() ?? ""
    }

    private func normalizedPath(_ value: String?) -> String? {
        nonEmpty(value).map {
            URL(fileURLWithPath: $0).standardizedFileURL.path.lowercased()
        }
    }

    private func normalizedTTY(_ value: String?) -> String? {
        nonEmpty(value)?.replacingOccurrences(of: "/dev/", with: "")
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func fetchGhosttySnapshots() -> [GhosttySnapshot]? {
        let script = """
        set recordSeparator to ASCII character 30
        set fieldSeparator to ASCII character 31
        set rows to {}
        tell application "Ghostty"
            if not (it is running) then return ""
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aTerminal in terminals of aTab
                        set end of rows to (id of aTerminal as text) & fieldSeparator & (working directory of aTerminal as text) & fieldSeparator & (name of aTerminal as text)
                    end repeat
                end repeat
            end repeat
        end tell
        set AppleScript's text item delimiters to recordSeparator
        return rows as text
        """
        guard let output = runAppleScript(script) else { return nil }
        return output
            .components(separatedBy: "\u{1E}")
            .compactMap { row in
                let fields = row.components(separatedBy: "\u{1F}")
                guard fields.count == 3, !fields[0].isEmpty else {
                    return nil
                }
                return GhosttySnapshot(sessionID: fields[0], workingDirectory: fields[1], title: fields[2])
            }
    }

    private static func fetchTerminalSnapshots() -> [TerminalSnapshot]? {
        let script = """
        set recordSeparator to ASCII character 30
        set fieldSeparator to ASCII character 31
        set rows to {}
        tell application "Terminal"
            if not (it is running) then return ""
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    set end of rows to (tty of aTab as text) & fieldSeparator & (custom title of aTab as text)
                end repeat
            end repeat
        end tell
        set AppleScript's text item delimiters to recordSeparator
        return rows as text
        """
        guard let output = runAppleScript(script) else { return nil }
        return output
            .components(separatedBy: "\u{1E}")
            .compactMap { row in
                let fields = row.components(separatedBy: "\u{1F}")
                guard fields.count == 2, !fields[0].isEmpty else {
                    return nil
                }
                return TerminalSnapshot(tty: fields[0], title: fields[1])
            }
    }

    static func runAppleScript(_ script: String, timeout: TimeInterval = 3) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            guard wait(for: process, timeout: timeout) else {
                return nil
            }
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines)
        } catch {
            return nil
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
}

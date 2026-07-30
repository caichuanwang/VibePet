import Foundation
import VibePetCore

struct StartupSessionCandidate: Equatable, Sendable {
    var tool: ToolKind
    var sessionID: String
    var transcriptPath: String
    var workingDirectory: String
    var updatedAt: Date
}

struct RecentSessionDiscovery: Sendable {
    private struct CandidateFile {
        var url: URL
        var modifiedAt: Date
    }

    static var defaultCodexRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    static var defaultClaudeRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    private let codexRootURL: URL
    private let claudeRootURL: URL
    private let maxAge: TimeInterval
    private let maxFilesPerTool: Int

    init(
        codexRootURL: URL = Self.defaultCodexRootURL,
        claudeRootURL: URL = Self.defaultClaudeRootURL,
        maxAge: TimeInterval = 86_400,
        maxFilesPerTool: Int = 40
    ) {
        self.codexRootURL = codexRootURL
        self.claudeRootURL = claudeRootURL
        self.maxAge = maxAge
        self.maxFilesPerTool = maxFilesPerTool
    }

    func discover(now: Date = .now) -> [StartupSessionCandidate] {
        let codex = recentFiles(
            below: codexRootURL,
            now: now,
            accepts: {
                $0.lastPathComponent.hasPrefix("rollout-")
                    && $0.pathExtension == "jsonl"
            }
        ).compactMap(parseCodexCandidate)
        let claude = recentFiles(
            below: claudeRootURL,
            now: now,
            accepts: {
                $0.pathExtension == "jsonl"
                    && !$0.path.contains("/subagents/")
            }
        ).compactMap(parseClaudeCandidate)

        var newestByIdentity: [String: StartupSessionCandidate] = [:]
        for candidate in (codex + claude).sorted(by: { $0.updatedAt > $1.updatedAt }) {
            let key = "\(candidate.tool.rawValue):\(candidate.sessionID.lowercased())"
            if newestByIdentity[key] == nil {
                newestByIdentity[key] = candidate
            }
        }
        return newestByIdentity.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func recentFiles(
        below rootURL: URL,
        now: Date,
        accepts: (URL) -> Bool
    ) -> [CandidateFile] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: rootURL.path),
              let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let cutoff = now.addingTimeInterval(-maxAge)
        var files: [CandidateFile] = []
        for case let fileURL as URL in enumerator where accepts(fileURL) {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            ),
            values.isRegularFile == true,
            let modifiedAt = values.contentModificationDate,
            modifiedAt >= cutoff else {
                continue
            }
            files.append(CandidateFile(url: fileURL, modifiedAt: modifiedAt))
        }

        return Array(
            files
                .sorted {
                    if $0.modifiedAt == $1.modifiedAt {
                        return $0.url.path < $1.url.path
                    }
                    return $0.modifiedAt > $1.modifiedAt
                }
                .prefix(maxFilesPerTool)
        )
    }

    private func parseCodexCandidate(_ file: CandidateFile) -> StartupSessionCandidate? {
        var candidate: StartupSessionCandidate?
        streamLines(at: file.url) { line in
            guard let object = jsonObject(for: line),
                  object["type"] as? String == "session_meta",
                  let payload = object["payload"] as? [String: Any],
                  let sessionID = normalizedSessionID(payload["id"] as? String),
                  let cwd = normalizedNonEmpty(payload["cwd"] as? String) else {
                return true
            }
            candidate = StartupSessionCandidate(
                tool: .codex,
                sessionID: sessionID,
                transcriptPath: file.url.path,
                workingDirectory: cwd,
                updatedAt: file.modifiedAt
            )
            return false
        }
        return candidate
    }

    private func parseClaudeCandidate(_ file: CandidateFile) -> StartupSessionCandidate? {
        var sessionID = normalizedSessionID(
            file.url.deletingPathExtension().lastPathComponent
        )
        var workingDirectory: String?

        streamLines(at: file.url) { line in
            guard let object = jsonObject(for: line) else {
                return true
            }
            sessionID = normalizedSessionID(object["sessionId"] as? String) ?? sessionID
            workingDirectory = normalizedNonEmpty(object["cwd"] as? String) ?? workingDirectory
            return sessionID == nil || workingDirectory == nil
        }

        guard let sessionID, let workingDirectory else {
            return nil
        }
        return StartupSessionCandidate(
            tool: .claudeCode,
            sessionID: sessionID,
            transcriptPath: file.url.path,
            workingDirectory: workingDirectory,
            updatedAt: file.modifiedAt
        )
    }

    private func streamLines(at fileURL: URL, consume: (String) -> Bool) {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return
        }
        defer { try? fileHandle.close() }

        var buffer = Data()
        while let chunk = try? fileHandle.read(upToCount: 64 * 1_024),
              !chunk.isEmpty {
            buffer.append(chunk)
            while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer.prefix(upTo: newlineIndex)
                buffer.removeSubrange(...newlineIndex)
                guard lineData.isEmpty || consume(String(decoding: lineData, as: UTF8.self)) else {
                    return
                }
            }
        }

        if !buffer.isEmpty {
            _ = consume(String(decoding: buffer, as: UTF8.self))
        }
    }

    private func jsonObject(for line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func normalizedSessionID(_ value: String?) -> String? {
        guard let value = normalizedNonEmpty(value),
              UUID(uuidString: value) != nil else {
            return nil
        }
        return value.lowercased()
    }

    private func normalizedNonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

actor SessionDiscoveryCoordinator {
    typealias ProcessScanProvider = @Sendable () -> ActiveAgentProcessScan
    typealias LocalSessionProvider = @Sendable () -> [StartupSessionCandidate]

    private let processScanProvider: ProcessScanProvider
    private let localSessionProvider: LocalSessionProvider
    private let candidateRefreshInterval: TimeInterval
    private let candidateRetryWindow: TimeInterval
    private let nowProvider: @Sendable () -> Date
    private var startupCandidates: [StartupSessionCandidate]?
    private var candidatesLoadedAt: Date?
    private var unresolvedProcessKeys: Set<String> = []
    private var candidateRetryDeadline: Date?
    private var lastEnrichmentHadUnresolvedSessions = false

    init(
        processScanProvider: @escaping ProcessScanProvider = {
            ActiveAgentProcessDiscovery().scan()
        },
        localSessionProvider: @escaping LocalSessionProvider = {
            RecentSessionDiscovery().discover()
        },
        candidateRefreshInterval: TimeInterval = 2,
        candidateRetryWindow: TimeInterval = 30,
        nowProvider: @escaping @Sendable () -> Date = { .now }
    ) {
        self.processScanProvider = processScanProvider
        self.localSessionProvider = localSessionProvider
        self.candidateRefreshInterval = candidateRefreshInterval
        self.candidateRetryWindow = candidateRetryWindow
        self.nowProvider = nowProvider
    }

    func scan() async -> ActiveAgentProcessScan {
        let processProvider = processScanProvider
        let processScan = await Task.detached(priority: .utility) {
            processProvider()
        }.value
        guard case let .success(activeSessions) = processScan else {
            return .failure
        }

        let currentUnresolvedProcessKeys = Set(
            activeSessions
                .filter { $0.nativeSessionID == nil }
                .map(Self.processKey)
        )
        guard !currentUnresolvedProcessKeys.isEmpty else {
            unresolvedProcessKeys = []
            candidateRetryDeadline = nil
            lastEnrichmentHadUnresolvedSessions = false
            return .success(activeSessions)
        }

        let now = nowProvider()
        let unresolvedProcessesChanged = currentUnresolvedProcessKeys != unresolvedProcessKeys
        if unresolvedProcessesChanged {
            unresolvedProcessKeys = currentUnresolvedProcessKeys
            candidateRetryDeadline = now.addingTimeInterval(candidateRetryWindow)
        }
        let retryWindowIsOpen = candidateRetryDeadline.map { now <= $0 } ?? false
        let refreshIntervalElapsed = candidatesLoadedAt.map {
            now.timeIntervalSince($0) >= candidateRefreshInterval
        } ?? true
        let shouldRefreshCandidates = startupCandidates == nil
            || unresolvedProcessesChanged
            || (
                lastEnrichmentHadUnresolvedSessions
                    && retryWindowIsOpen
                    && refreshIntervalElapsed
            )

        if shouldRefreshCandidates {
            let localProvider = localSessionProvider
            startupCandidates = await Task.detached(priority: .utility) {
                localProvider()
            }.value
            candidatesLoadedAt = now
        }

        let enrichedSessions = Self.enrich(
            activeSessions,
            with: startupCandidates ?? []
        )
        lastEnrichmentHadUnresolvedSessions = enrichedSessions.contains {
            $0.nativeSessionID == nil
        }
        return .success(enrichedSessions)
    }

    private static func enrich(
        _ activeSessions: [ActiveAgentSession],
        with candidates: [StartupSessionCandidate]
    ) -> [ActiveAgentSession] {
        let candidatesByID = Dictionary(
            grouping: candidates,
            by: { "\($0.tool.rawValue):\($0.sessionID.lowercased())" }
        )
        let candidatesByPath = Dictionary(
            grouping: candidates,
            by: { "\($0.tool.rawValue):\($0.transcriptPath)" }
        )
        let candidatesByWorkspace = Dictionary(
            grouping: candidates,
            by: {
                workspaceKey(
                    tool: $0.tool,
                    workingDirectory: $0.workingDirectory
                )
            }
        )
        let unresolvedByWorkspace = Dictionary(
            grouping: activeSessions.filter {
                $0.nativeSessionID == nil && $0.transcriptPath == nil
            },
            by: {
                workspaceKey(
                    tool: $0.tool,
                    workingDirectory: $0.jumpTarget?.workingDirectory
                )
            }
        )

        var claimedCandidates: Set<String> = []
        return activeSessions.map { activeSession in
            let candidate: StartupSessionCandidate?
            if let nativeSessionID = activeSession.nativeSessionID {
                candidate = candidatesByID[
                    "\(activeSession.tool.rawValue):\(nativeSessionID.lowercased())"
                ]?.only
            } else if let transcriptPath = activeSession.transcriptPath {
                candidate = candidatesByPath[
                    "\(activeSession.tool.rawValue):\(transcriptPath)"
                ]?.only
            } else {
                let key = workspaceKey(
                    tool: activeSession.tool,
                    workingDirectory: activeSession.jumpTarget?.workingDirectory
                )
                if unresolvedByWorkspace[key]?.count == 1 {
                    candidate = candidatesByWorkspace[key]?.only
                } else {
                    candidate = nil
                }
            }

            guard let candidate else {
                return activeSession
            }
            let candidateKey = "\(candidate.tool.rawValue):\(candidate.sessionID.lowercased())"
            guard claimedCandidates.insert(candidateKey).inserted else {
                return activeSession
            }

            var enriched = activeSession
            enriched.nativeSessionID = enriched.nativeSessionID ?? candidate.sessionID
            enriched.transcriptPath = enriched.transcriptPath ?? candidate.transcriptPath
            enriched.id = "discovered-\(enriched.tool.rawValue)-\(candidate.sessionID)"
            if enriched.jumpTarget?.workingDirectory == nil {
                enriched.jumpTarget?.workingDirectory = candidate.workingDirectory
            }
            return enriched
        }
    }

    private static func workspaceKey(
        tool: ToolKind,
        workingDirectory: String?
    ) -> String {
        let path = workingDirectory.map(
            ActiveAgentProcessDiscovery.normalizedWorkingDirectory
        ) ?? "-"
        return "\(tool.rawValue):\(path)"
    }

    private static func processKey(_ session: ActiveAgentSession) -> String {
        [
            session.tool.rawValue,
            session.processID ?? session.id,
            session.parentProcessID ?? "-",
            session.jumpTarget?.terminalTTY ?? "-",
            session.jumpTarget?.workingDirectory.map(
                ActiveAgentProcessDiscovery.normalizedWorkingDirectory
            ) ?? "-",
        ].joined(separator: "|")
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? self[0] : nil
    }
}

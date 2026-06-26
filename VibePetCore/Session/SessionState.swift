import Foundation

public struct SessionState: Equatable, Sendable {
    public private(set) var sessionsByID: [String: AgentSession]
    private var greetedSessionIDs: Set<String>

    public init(sessions: [AgentSession] = []) {
        self.sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        self.greetedSessionIDs = []
    }

    public var visibleSessions: [AgentSession] {
        sessionsByID.values
            .filter(\.isVisible)
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.id < rhs.id
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    public var runningCount: Int {
        visibleSessions.filter { $0.phase == .running }.count
    }

    public var attentionCount: Int {
        sessionsByID.values.filter { $0.phase.requiresAttention }.count
    }

    public var activeActionableSession: AgentSession? {
        visibleSessions.first { $0.phase.requiresAttention }
    }

    public var derivedPetActivity: SessionPetActivity {
        if activeActionableSession != nil {
            return .deciding
        }
        if sessionsByID.values.contains(where: { $0.phase == .running && !greetedSessionIDs.contains($0.id) }) {
            return .greeting
        }
        return .idle
    }

    public var petVisualState: PetVisualState {
        if activeActionableSession != nil {
            return .waiting
        }
        if visibleSessions.contains(where: { $0.phase == .completed && $0.isError }) {
            return .failed
        }
        if runningCount > 0 {
            return .running
        }
        return .idle
    }

    public var nextUngreetedRunningSessionID: String? {
        sessionsByID.values
            .filter { $0.phase == .running && !greetedSessionIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.firstSeenAt == rhs.firstSeenAt {
                    return lhs.id < rhs.id
                }
                return lhs.firstSeenAt < rhs.firstSeenAt
            }
            .first?
            .id
    }

    public mutating func apply(_ event: AgentEvent) {
        switch event {
        case let .sessionStarted(sessionID, timestamp, title, tool, summary, jumpTarget):
            let existing = sessionsByID[sessionID]
            let session = AgentSession(
                id: sessionID,
                title: title,
                tool: tool,
                phase: .running,
                summary: summary,
                updatedAt: timestamp,
                firstSeenAt: existing?.firstSeenAt ?? timestamp,
                jumpTarget: jumpTarget ?? existing?.jumpTarget,
                isError: false,
                isSessionEnded: false,
                isProcessAlive: true,
                processNotSeenCount: 0,
                latestUserPrompt: existing?.latestUserPrompt ?? Self.userPrompt(from: summary)
            )
            sessionsByID[sessionID] = session

        case let .activityUpdated(sessionID, timestamp, summary):
            guard var session = sessionsByID[sessionID] else { return }
            if !session.phase.requiresAttention {
                session.phase = .running
            }
            session.summary = summary
            if let userPrompt = Self.userPrompt(from: summary) {
                session.latestUserPrompt = userPrompt
            }
            session.updatedAt = timestamp
            session.isProcessAlive = true
            session.processNotSeenCount = 0
            sessionsByID[sessionID] = session

        case let .permissionRequested(sessionID, timestamp, summary):
            guard var session = sessionsByID[sessionID] else { return }
            session.phase = .waitingForApproval
            session.summary = summary
            session.updatedAt = timestamp
            sessionsByID[sessionID] = session

        case let .questionAsked(sessionID, timestamp, summary):
            guard var session = sessionsByID[sessionID] else { return }
            session.phase = .waitingForAnswer
            session.summary = summary
            session.updatedAt = timestamp
            sessionsByID[sessionID] = session

        case let .sessionCompleted(sessionID, timestamp, summary, isError, isSessionEnd):
            guard var session = sessionsByID[sessionID] else { return }
            session.phase = .completed
            session.summary = summary
            session.isError = isError
            session.isSessionEnded = isSessionEnd
            session.updatedAt = timestamp
            sessionsByID[sessionID] = session

        case let .jumpTargetUpdated(sessionID, timestamp, jumpTarget):
            guard var session = sessionsByID[sessionID] else { return }
            session.jumpTarget = jumpTarget
            session.updatedAt = timestamp
            sessionsByID[sessionID] = session

        case let .actionableStateResolved(sessionID, timestamp, summary):
            guard var session = sessionsByID[sessionID], session.phase.requiresAttention else { return }
            session.phase = .running
            session.summary = summary
            session.updatedAt = timestamp
            sessionsByID[sessionID] = session
        }
    }

    public static func userPrompt(from summary: String) -> String? {
        let prefix = "User prompt:"
        guard summary.hasPrefix(prefix) else { return nil }
        let prompt = summary.dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return prompt.isEmpty ? nil : prompt
    }

    public static func isUserPromptSummary(_ summary: String) -> Bool {
        userPrompt(from: summary) != nil
    }

    public mutating func resolvePermission(sessionID: String, approved: Bool, at timestamp: Date = .now) {
        guard var session = sessionsByID[sessionID], session.phase == .waitingForApproval else { return }
        session.phase = approved ? .running : .completed
        session.summary = approved ? "Permission approved" : "Permission denied"
        session.updatedAt = timestamp
        sessionsByID[sessionID] = session
    }

    public mutating func answerQuestion(sessionID: String, summary: String, at timestamp: Date = .now) {
        guard var session = sessionsByID[sessionID], session.phase == .waitingForAnswer else { return }
        session.phase = .running
        session.summary = summary
        session.updatedAt = timestamp
        sessionsByID[sessionID] = session
    }

    @discardableResult
    public mutating func markProcessLiveness(aliveSessionIDs: Set<String>) -> Set<String> {
        var reaped: Set<String> = []

        for (id, var session) in sessionsByID {
            if session.isSessionEnded, !session.isProcessAlive, session.phase == .completed {
                sessionsByID[id] = session
                continue
            }

            if aliveSessionIDs.contains(id) {
                session.isProcessAlive = true
                session.processNotSeenCount = 0
            } else {
                session.processNotSeenCount += 1
                if session.processNotSeenCount >= 2, !session.phase.requiresAttention {
                    session.isProcessAlive = false
                    session.isSessionEnded = true
                    session.phase = .completed
                    reaped.insert(id)
                }
            }
            sessionsByID[id] = session
        }

        return reaped
    }

    @discardableResult
    public mutating func removeInvisibleSessions() -> Set<String> {
        let removableIDs = Set(sessionsByID.compactMap { id, session in
            session.isVisible ? nil : id
        })
        for id in removableIDs {
            sessionsByID.removeValue(forKey: id)
            greetedSessionIDs.remove(id)
        }
        return removableIDs
    }

    public mutating func markGreetingShown(for sessionID: String) {
        greetedSessionIDs.insert(sessionID)
    }

    @discardableResult
    public mutating func removeSession(sessionID: String) -> AgentSession? {
        greetedSessionIDs.remove(sessionID)
        return sessionsByID.removeValue(forKey: sessionID)
    }

    public mutating func upsertDiscoveredSession(_ session: AgentSession) {
        guard sessionsByID[session.id] == nil else {
            return
        }
        sessionsByID[session.id] = session
    }
}

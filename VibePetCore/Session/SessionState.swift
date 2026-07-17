import Foundation

public struct SessionState: Equatable, Sendable {
    public private(set) var sessionsByID: [String: AgentSession]
    private var greetedSessionIDs: Set<String>
    /// Highest actionable request timestamp that has already been resolved per session.
    /// Kept outside `AgentSession` so bridge/persistence Codable formats stay unchanged.
    private var resolvedActionableWatermarks: [String: Date]

    public init(sessions: [AgentSession] = []) {
        self.sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        self.greetedSessionIDs = []
        self.resolvedActionableWatermarks = [:]
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

    /// Applies one normalized event and returns whether canonical session state changed.
    /// Lifecycle timestamps never move backwards. Metadata-only jump updates may still
    /// fill missing fields when they arrive late, without changing lifecycle recency.
    @discardableResult
    public mutating func apply(_ event: AgentEvent) -> Bool {
        switch event {
        case let .sessionStarted(sessionID, timestamp, title, tool, summary, jumpTarget):
            return applySessionStarted(
                sessionID: sessionID,
                timestamp: timestamp,
                title: title,
                tool: tool,
                summary: summary,
                jumpTarget: jumpTarget
            )
        case let .activityUpdated(sessionID, timestamp, summary):
            return applyActivity(sessionID: sessionID, timestamp: timestamp, summary: summary)
        case let .permissionRequested(sessionID, timestamp, summary):
            return applyActionable(
                sessionID: sessionID,
                timestamp: timestamp,
                phase: .waitingForApproval,
                summary: summary
            )
        case let .questionAsked(sessionID, timestamp, summary):
            return applyActionable(
                sessionID: sessionID,
                timestamp: timestamp,
                phase: .waitingForAnswer,
                summary: summary
            )
        case let .sessionCompleted(sessionID, timestamp, summary, isError, isSessionEnd):
            return applyCompletion(
                sessionID: sessionID,
                timestamp: timestamp,
                summary: summary,
                isError: isError,
                isSessionEnd: isSessionEnd
            )
        case let .jumpTargetUpdated(sessionID, _, jumpTarget):
            return applyJumpTarget(sessionID: sessionID, jumpTarget: jumpTarget)
        case let .actionableStateResolved(sessionID, timestamp, summary):
            return applyActionableResolution(sessionID: sessionID, timestamp: timestamp, summary: summary)
        }
    }

    private mutating func applySessionStarted(
        sessionID: String,
        timestamp: Date,
        title: String,
        tool: ToolKind,
        summary: String,
        jumpTarget: JumpTarget?
    ) -> Bool {
        guard var existing = sessionsByID[sessionID] else {
            sessionsByID[sessionID] = AgentSession(
                id: sessionID,
                title: title,
                tool: tool,
                phase: .running,
                summary: summary,
                updatedAt: timestamp,
                jumpTarget: jumpTarget,
                latestUserPrompt: Self.userPrompt(from: summary)
            )
            return true
        }

        let mergedJumpTarget = Self.mergingJumpTarget(existing.jumpTarget, with: jumpTarget)
        // Session IDs are lifecycle identities. Duplicate starts may arrive late or
        // with a newer receive timestamp, but they must not reset waiting/completed
        // state. They can only fill terminal metadata captured after the first start.
        guard mergedJumpTarget != existing.jumpTarget else { return false }
        existing.jumpTarget = mergedJumpTarget
        sessionsByID[sessionID] = existing
        return true
    }

    private mutating func applyActivity(sessionID: String, timestamp: Date, summary: String) -> Bool {
        guard var session = sessionsByID[sessionID],
              !session.isSessionEnded,
              timestamp > session.updatedAt else { return false }
        if !session.phase.requiresAttention {
            // A newer activity opens the next turn after a turn-level completion.
            session.phase = .running
            session.isError = false
        }
        session.summary = summary
        if let userPrompt = Self.userPrompt(from: summary) {
            session.latestUserPrompt = userPrompt
        }
        session.updatedAt = timestamp
        session.isProcessAlive = true
        session.processNotSeenCount = 0
        sessionsByID[sessionID] = session
        return true
    }

    private mutating func applyActionable(
        sessionID: String,
        timestamp: Date,
        phase: SessionPhase,
        summary: String
    ) -> Bool {
        guard var session = sessionsByID[sessionID],
              !session.isSessionEnded,
              timestamp > (resolvedActionableWatermarks[sessionID] ?? .distantPast),
              Self.mayApplyActionableEvent(timestamp: timestamp, phase: phase, to: session) else { return false }
        session.phase = phase
        session.summary = summary
        session.updatedAt = max(session.updatedAt, timestamp)
        sessionsByID[sessionID] = session
        return true
    }

    private mutating func applyCompletion(
        sessionID: String,
        timestamp: Date,
        summary: String,
        isError: Bool,
        isSessionEnd: Bool
    ) -> Bool {
        guard var session = sessionsByID[sessionID] else { return false }
        if isSessionEnd {
            let previous = session
            session.phase = .completed
            session.isSessionEnded = true
            session.isProcessAlive = false
            session.processNotSeenCount = max(session.processNotSeenCount, 2)
            if timestamp >= session.updatedAt {
                session.summary = summary
                session.isError = isError
                session.updatedAt = timestamp
            }
            guard session != previous else { return false }
            sessionsByID[sessionID] = session
            return true
        }

        guard !session.isSessionEnded,
              !session.phase.requiresAttention,
              Self.mayApplyPhaseEvent(timestamp: timestamp, phase: .completed, to: session) else { return false }
        session.phase = .completed
        session.summary = summary
        session.isError = isError
        session.updatedAt = timestamp
        sessionsByID[sessionID] = session
        return true
    }

    private mutating func applyJumpTarget(sessionID: String, jumpTarget: JumpTarget) -> Bool {
        guard var session = sessionsByID[sessionID] else { return false }
        let merged = Self.mergingJumpTarget(session.jumpTarget, with: jumpTarget)
        guard merged != session.jumpTarget else { return false }
        session.jumpTarget = merged
        sessionsByID[sessionID] = session
        return true
    }

    private mutating func applyActionableResolution(
        sessionID: String,
        timestamp: Date,
        summary: String
    ) -> Bool {
        guard var session = sessionsByID[sessionID],
              !session.isSessionEnded,
              session.phase.requiresAttention else { return false }
        recordResolvedActionable(sessionID: sessionID, requestTimestamp: session.updatedAt)
        session.phase = .running
        session.summary = summary
        session.updatedAt = max(session.updatedAt, timestamp)
        sessionsByID[sessionID] = session
        return true
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

    @discardableResult
    public mutating func resolvePermission(sessionID: String, approved: Bool, at timestamp: Date = .now) -> Bool {
        guard var session = sessionsByID[sessionID],
              !session.isSessionEnded,
              session.phase == .waitingForApproval else { return false }
        recordResolvedActionable(sessionID: sessionID, requestTimestamp: session.updatedAt)
        session.phase = approved ? .running : .completed
        session.summary = approved ? "Permission approved" : "Permission denied"
        session.updatedAt = max(session.updatedAt, timestamp)
        sessionsByID[sessionID] = session
        return true
    }

    @discardableResult
    public mutating func answerQuestion(sessionID: String, summary: String, at timestamp: Date = .now) -> Bool {
        guard var session = sessionsByID[sessionID],
              !session.isSessionEnded,
              session.phase == .waitingForAnswer else { return false }
        recordResolvedActionable(sessionID: sessionID, requestTimestamp: session.updatedAt)
        session.phase = .running
        session.summary = summary
        session.updatedAt = max(session.updatedAt, timestamp)
        sessionsByID[sessionID] = session
        return true
    }

    @discardableResult
    public mutating func markProcessLiveness(aliveSessionIDs: Set<String>) -> Set<String> {
        var reaped: Set<String> = []

        for (id, current) in sessionsByID {
            var session = current
            if session.isSessionEnded {
                session.isProcessAlive = false
                session.processNotSeenCount = max(session.processNotSeenCount, 2)
            } else if aliveSessionIDs.contains(id) {
                session.isProcessAlive = true
                session.processNotSeenCount = 0
            } else {
                session.processNotSeenCount = min(2, session.processNotSeenCount + 1)
                if session.processNotSeenCount >= 2, !session.phase.requiresAttention {
                    session.isProcessAlive = false
                    session.isSessionEnded = true
                    session.phase = .completed
                    reaped.insert(id)
                }
            }
            if session != current {
                sessionsByID[id] = session
            }
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
            resolvedActionableWatermarks.removeValue(forKey: id)
        }
        return removableIDs
    }

    public mutating func markGreetingShown(for sessionID: String) {
        greetedSessionIDs.insert(sessionID)
    }

    @discardableResult
    public mutating func removeSession(sessionID: String) -> AgentSession? {
        greetedSessionIDs.remove(sessionID)
        resolvedActionableWatermarks.removeValue(forKey: sessionID)
        return sessionsByID.removeValue(forKey: sessionID)
    }

    @discardableResult
    public mutating func upsertDiscoveredSession(_ session: AgentSession) -> Bool {
        guard sessionsByID[session.id] == nil else { return false }
        sessionsByID[session.id] = session
        return true
    }

    /// Atomically replaces a process-discovered placeholder with its hook identity,
    /// preserving first-seen ordering and any precise terminal metadata captured early.
    @discardableResult
    public mutating func replaceDiscoveredSession(
        sessionID placeholderID: String,
        with event: AgentEvent
    ) -> Bool {
        guard case let .sessionStarted(sessionID, timestamp, title, tool, summary, jumpTarget) = event,
              sessionsByID[sessionID] == nil,
              let placeholder = sessionsByID[placeholderID] else { return false }
        let mergedJumpTarget = Self.mergingJumpTarget(placeholder.jumpTarget, with: jumpTarget)
        let replacement = AgentSession(
            id: sessionID,
            title: title,
            tool: tool,
            phase: .running,
            summary: summary,
            updatedAt: timestamp,
            firstSeenAt: min(placeholder.firstSeenAt, timestamp),
            jumpTarget: mergedJumpTarget,
            latestUserPrompt: placeholder.latestUserPrompt ?? Self.userPrompt(from: summary)
        )
        sessionsByID.removeValue(forKey: placeholderID)
        sessionsByID[sessionID] = replacement
        resolvedActionableWatermarks.removeValue(forKey: placeholderID)
        if greetedSessionIDs.remove(placeholderID) != nil {
            greetedSessionIDs.insert(sessionID)
        }
        return true
    }
}

private extension SessionState {
    mutating func recordResolvedActionable(sessionID: String, requestTimestamp: Date) {
        resolvedActionableWatermarks[sessionID] = max(
            resolvedActionableWatermarks[sessionID] ?? .distantPast,
            requestTimestamp
        )
    }

    private static func mayApplyActionableEvent(
        timestamp: Date,
        phase: SessionPhase,
        to session: AgentSession
    ) -> Bool {
        mayApplyPhaseEvent(timestamp: timestamp, phase: phase, to: session)
    }

    private static func mayApplyPhaseEvent(
        timestamp: Date,
        phase: SessionPhase,
        to session: AgentSession
    ) -> Bool {
        if timestamp > session.updatedAt { return true }
        guard timestamp == session.updatedAt else { return false }
        // Equal timestamps use a fixed phase priority rather than arrival order.
        return phasePriority(phase) > phasePriority(session.phase)
    }

    private static func phasePriority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .running: 0
        case .completed: 1
        case .waitingForApproval: 2
        case .waitingForAnswer: 3
        }
    }

    private static func mergingJumpTarget(_ existing: JumpTarget?, with incoming: JumpTarget?) -> JumpTarget? {
        guard let incoming else { return existing }
        guard let existing else { return incoming }
        return JumpTarget(
            terminalApp: knownTerminalApp(existing.terminalApp) ?? incoming.terminalApp,
            workspaceName: nonEmpty(existing.workspaceName) ?? nonEmpty(incoming.workspaceName),
            paneTitle: nonEmpty(existing.paneTitle) ?? nonEmpty(incoming.paneTitle),
            workingDirectory: nonEmpty(existing.workingDirectory) ?? nonEmpty(incoming.workingDirectory),
            terminalSessionID: nonEmpty(existing.terminalSessionID) ?? nonEmpty(incoming.terminalSessionID),
            terminalTTY: nonEmpty(existing.terminalTTY) ?? nonEmpty(incoming.terminalTTY)
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    private static func knownTerminalApp(_ value: String?) -> String? {
        guard let value = nonEmpty(value), value.caseInsensitiveCompare("Unknown") != .orderedSame else {
            return nil
        }
        return value
    }
}

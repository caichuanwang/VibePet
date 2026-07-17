import AppKit
import Dispatch
import VibePetCore

/// Runs the `BridgeServer` for the running App and routes received envelopes to
/// the `PetController` on the main actor. The server handler is `@Sendable` and
/// runs off the main actor, so traffic is funneled through `AsyncStream`s (their
/// continuations are `Sendable`) and consumed on main-actor tasks — keeping
/// `PetController` main-actor isolated.
///
/// Notifications are fire-and-forget (`.defer` reply). Response-bearing envelopes
/// (`approval` / `question`) run the blocking decision round trip: the handler
/// suspends on a per-request continuation while `PetController` presents the
/// approval and awaits the user's choice, then replies on the same connection with
/// the decision paired back by `requestId`. Each decision is awaited on its own
/// task so a 20s wait never blocks other connections.
@MainActor
final class BridgeServerHost {
    private let petController: PetController
    private let socketPath: SocketPath
    private let manifestStore: InstallManifestStore
    private let liveSessionProvider: @Sendable (SessionState) async -> Set<String>
    private let activeSessionProvider: @Sendable () async -> [ActiveAgentSession]
    private let livenessInterval: TimeInterval
    private let terminalJumpResolver: TerminalJumpTargetResolver
    private let localizerProvider: @MainActor () -> AppLocalizer
    private let onSessionStateChange: @MainActor (SessionState) -> Void
    private var sessionState = SessionState()
    private var server: BridgeServer?
    private var notifyTask: Task<Void, Never>?
    private var livenessTask: Task<Void, Never>?
    /// Covers EOF arriving before the decoded decision reaches the main actor.
    /// Entries are short-lived and pruned whenever the set is accessed.
    private var cancelledDecisionDeadlines: [UUID: Date] = [:]
    private var pendingDecisionEnvelopes: [UUID: BridgeEnvelope] = [:]
    private var pendingDecisionOrder: [UUID] = []
    private var endedSessionIDs: Set<String> = []
    private var isStopping = false
    /// Invalidates async decision work from a prior stop/start lifecycle.
    private var generation: UInt64 = 0
    /// Receiving a real Codex hook event is the runtime evidence that the user
    /// trusted VibePet in `/hooks`; flip the manifest to `trustedActive` once
    /// (M6-5a). Cached so we stop hitting disk after the first activation.
    private var codexTrustMarked = false

    init(
        petController: PetController,
        socketPath: SocketPath = SocketPath(),
        manifestStore: InstallManifestStore? = nil,
        liveSessionProvider: @escaping @Sendable (SessionState) async -> Set<String> = {
            await AgentProcessLiveness.liveSessionIDs(in: $0)
        },
        activeSessionProvider: @escaping @Sendable () async -> [ActiveAgentSession] = {
            await Task.detached(priority: .utility) {
                ActiveAgentProcessDiscovery().discover()
            }.value
        },
        livenessInterval: TimeInterval = 5,
        terminalJumpResolver: TerminalJumpTargetResolver = TerminalJumpTargetResolver(),
        localizerProvider: @escaping @MainActor () -> AppLocalizer = { AppLocalizer(language: .simplifiedChinese) },
        onSessionStateChange: @escaping @MainActor (SessionState) -> Void = { _ in }
    ) {
        self.petController = petController
        self.socketPath = socketPath
        self.manifestStore = manifestStore
            ?? InstallManifestStore(applicationSupportRoot: socketPath.applicationSupportRoot)
        self.liveSessionProvider = liveSessionProvider
        self.activeSessionProvider = activeSessionProvider
        self.livenessInterval = livenessInterval
        self.terminalJumpResolver = terminalJumpResolver
        self.localizerProvider = localizerProvider
        self.onSessionStateChange = onSessionStateChange
    }

    /// On the first real Codex event, promote its hook install to `trustedActive`.
    private func markCodexTrustedIfNeeded(_ envelope: BridgeEnvelope) {
        guard !codexTrustMarked, envelope.source.tool == .codex else { return }
        if manifestStore.markTrustedActive(tool: .codex) {
            codexTrustMarked = true
        }
    }

    func start() {
        generation &+= 1
        let startGeneration = generation
        isStopping = false
        cancelledDecisionDeadlines.removeAll()
        let (notifyStream, notifyContinuation) = AsyncStream<BridgeEnvelope>.makeStream()

        notifyTask = Task { @MainActor [petController] in
            for await envelope in notifyStream {
                self.markCodexTrustedIfNeeded(envelope)
                self.applyNotification(envelope)
                if self.shouldPresent(envelope) {
                    petController.handle(envelope)
                }
            }
        }

        let server = BridgeServer(
            socketPath: socketPath,
            cancellationHandler: { [weak self] requestID in
                Task { @MainActor [weak self] in
                    self?.cancelDecision(requestID: requestID, generation: startGeneration)
                }
            }
        ) { [weak self] envelope in
            guard let self else {
                return BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
            }
            if envelope.content.needsResponse {
                let response = await self.processDecision(envelope, generation: startGeneration)
                return BridgeResponseEnvelope(requestId: envelope.requestId, response: response)
            }
            notifyContinuation.yield(envelope)
            return BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
        }
        self.server = server

        startLivenessSweep(generation: startGeneration)

        Task {
            do {
                try await server.start()
            } catch {
                NSLog("VibePet bridge server failed to start: \(error)")
            }
        }
    }

    func stop() {
        guard !isStopping else { return }
        isStopping = true
        generation &+= 1
        let resolved = resolvePendingActionableStateForStop()
        petController.cancelAllDecisions()
        if resolved {
            publishSessionState(allowGreeting: false)
        }
        server?.stop()
        server = nil
        notifyTask?.cancel()
        notifyTask = nil
        livenessTask?.cancel()
        livenessTask = nil
        cancelledDecisionDeadlines.removeAll()
        pendingDecisionEnvelopes.removeAll()
        pendingDecisionOrder.removeAll()
    }

    private func processDecision(_ envelope: BridgeEnvelope, generation requestGeneration: UInt64) async -> BridgeResponse {
        pruneCancelledDecisionTombstones()
        guard !isStopping,
              requestGeneration == generation,
              !Task.isCancelled,
              cancelledDecisionDeadlines.removeValue(forKey: envelope.requestId) == nil,
              pendingDecisionEnvelopes[envelope.requestId] == nil,
              !endedSessionIDs.contains(envelope.source.sessionID),
              sessionState.sessionsByID[envelope.source.sessionID]?.isSessionEnded != true else {
            return .defer
        }

        markCodexTrustedIfNeeded(envelope)
        let sessionAlreadyPending = pendingDecisionEnvelopes.values.contains {
            $0.source.sessionID == envelope.source.sessionID
        }
        pendingDecisionEnvelopes[envelope.requestId] = envelope
        pendingDecisionOrder.append(envelope.requestId)
        if !sessionAlreadyPending {
            applyDecisionEntry(envelope)
        }
        let response = await petController.requestDecision(for: envelope)
        guard !isStopping, requestGeneration == generation, !Task.isCancelled else {
            return .defer
        }
        cancelledDecisionDeadlines.removeValue(forKey: envelope.requestId)
        removePendingDecision(requestID: envelope.requestId)
        if !reconcileNextPendingDecision(sessionID: envelope.source.sessionID) {
            applyDecisionResolution(response, for: envelope)
        }
        return response
    }

    private func cancelDecision(requestID: UUID, generation requestGeneration: UInt64) {
        guard !isStopping, requestGeneration == generation else { return }
        pruneCancelledDecisionTombstones()
        cancelledDecisionDeadlines[requestID] = Date().addingTimeInterval(5)
        let cancelled = removePendingDecision(requestID: requestID)
        petController.cancelDecision(requestId: requestID)
        guard let sessionID = cancelled?.source.sessionID else { return }
        if reconcileNextPendingDecision(sessionID: sessionID) {
            return
        }
        guard
              sessionState.apply(.actionableStateResolved(
                  sessionID: sessionID,
                  timestamp: .now,
                  summary: localizerProvider().text(.handledInTerminal)
              )) else {
            return
        }
        publishSessionState()
    }

    @discardableResult
    private func removePendingDecision(requestID: UUID) -> BridgeEnvelope? {
        pendingDecisionOrder.removeAll { $0 == requestID }
        return pendingDecisionEnvelopes.removeValue(forKey: requestID)
    }

    private func cancelPendingDecisions(sessionID: String) {
        let requestIDs = pendingDecisionOrder.filter {
            pendingDecisionEnvelopes[$0]?.source.sessionID == sessionID
        }
        for requestID in requestIDs {
            removePendingDecision(requestID: requestID)
            petController.cancelDecision(requestId: requestID)
        }
    }

    private func reconcileNextPendingDecision(sessionID: String) -> Bool {
        guard let envelope = pendingDecisionOrder.lazy
            .compactMap({ self.pendingDecisionEnvelopes[$0] })
            .first(where: { $0.source.sessionID == sessionID }) else {
            return false
        }
        let changed: Bool
        switch envelope.content {
        case let .approval(content):
            changed = sessionState.apply(.permissionRequested(
                sessionID: sessionID,
                timestamp: .now,
                summary: content.title
            ))
        case let .question(content):
            changed = sessionState.apply(.questionAsked(
                sessionID: sessionID,
                timestamp: .now,
                summary: content.title
            ))
        case .completion, .status:
            return false
        }
        let merged = mergeSourceJumpTarget(envelope.source, sessionID: sessionID)
        if changed || merged {
            publishSessionState()
        }
        return true
    }

    private func resolvePendingActionableStateForStop() -> Bool {
        var changed = false
        let actionableIDs = sessionState.sessionsByID.values
            .filter { $0.phase.requiresAttention }
            .map(\.id)
        for sessionID in actionableIDs {
            changed = sessionState.apply(.actionableStateResolved(
                sessionID: sessionID,
                timestamp: .now,
                summary: localizerProvider().text(.handledInTerminal)
            )) || changed
        }
        return changed
    }

    private func pruneCancelledDecisionTombstones(now: Date = .now) {
        cancelledDecisionDeadlines = cancelledDecisionDeadlines.filter { $0.value > now }
    }

}

extension BridgeServerHost {
    var sessionStateSnapshot: SessionState {
        sessionState
    }

    func runLivenessSweepOnce() async {
        await runLivenessSweepOnce(generation: nil)
    }

    private func runLivenessSweepOnce(generation sweepGeneration: UInt64?) async {
        guard isCurrentLivenessSweep(generation: sweepGeneration) else { return }
        let activeSessions = await activeSessionProvider()
        guard isCurrentLivenessSweep(generation: sweepGeneration) else { return }

        let livenessInput = sessionState
        let observedSessionIDs = Set(livenessInput.sessionsByID.keys)
        let liveSessionIDs = await liveSessionProvider(livenessInput)
        guard isCurrentLivenessSweep(generation: sweepGeneration) else { return }

        var previewState = sessionState
        let previewDiscoveredIDs = importActiveSessions(activeSessions, into: &previewState)
        let previewNewIDs = Set(previewState.sessionsByID.keys).subtracting(observedSessionIDs)
        let previewChangedIDs = changedSessionIDs(from: livenessInput, to: previewState)
        previewState.markProcessLiveness(
            aliveSessionIDs: liveSessionIDs
                .union(previewDiscoveredIDs)
                .union(previewNewIDs)
                .union(previewChangedIDs)
        )
        let visibleSessions = previewState.visibleSessions
        let resolver = terminalJumpResolver
        let jumpTargetUpdates = await Task.detached(priority: .utility) {
            resolver.resolveJumpTargets(for: visibleSessions)
        }.value
        guard isCurrentLivenessSweep(generation: sweepGeneration) else { return }

        let previousState = sessionState
        let newSessionIDs = Set(sessionState.sessionsByID.keys).subtracting(observedSessionIDs)
        let changedSessionIDs = changedSessionIDs(from: livenessInput, to: sessionState)
        let discoveredSessionIDs = importActiveSessions(activeSessions, into: &sessionState)
        sessionState.markProcessLiveness(
            aliveSessionIDs: liveSessionIDs
                .union(discoveredSessionIDs)
                .union(newSessionIDs)
                .union(changedSessionIDs)
        )
        for (sessionID, jumpTarget) in jumpTargetUpdates {
            sessionState.apply(.jumpTargetUpdated(
                sessionID: sessionID,
                timestamp: .now,
                jumpTarget: jumpTarget
            ))
        }
        sessionState.removeInvisibleSessions()
        if sessionState != previousState {
            publishSessionState()
        }
    }

    private func importActiveSessions(
        _ activeSessions: [ActiveAgentSession],
        into state: inout SessionState
    ) -> Set<String> {
        var discoveredAliveIDs: Set<String> = []
        for activeSession in activeSessions {
            if state.sessionsByID[activeSession.id] != nil {
                discoveredAliveIDs.insert(activeSession.id)
                continue
            }
            if let matchingHookSession = matchingHookSession(for: activeSession, in: state) {
                discoveredAliveIDs.insert(matchingHookSession.id)
                continue
            }
            let now = Date.now
            state.upsertDiscoveredSession(AgentSession(
                id: activeSession.id,
                title: activeSession.title,
                tool: activeSession.tool,
                phase: .completed,
                summary: activeSession.summary,
                updatedAt: now,
                firstSeenAt: now,
                jumpTarget: activeSession.jumpTarget,
                isError: false,
                isSessionEnded: false,
                isProcessAlive: true,
                processNotSeenCount: 0
            ))
            discoveredAliveIDs.insert(activeSession.id)
        }
        return discoveredAliveIDs
    }

    private func startLivenessSweep(generation sweepGeneration: UInt64) {
        livenessTask?.cancel()
        let nanos = UInt64(livenessInterval * 1_000_000_000)
        livenessTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runLivenessSweepOnce(generation: sweepGeneration)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanos)
                guard self.isCurrentLivenessSweep(generation: sweepGeneration) else { return }
                await self.runLivenessSweepOnce(generation: sweepGeneration)
            }
        }
    }

    private func isCurrentLivenessSweep(generation sweepGeneration: UInt64?) -> Bool {
        guard !isStopping, !Task.isCancelled else { return false }
        guard let sweepGeneration else { return true }
        return sweepGeneration == generation
    }

    private func changedSessionIDs(from previous: SessionState, to current: SessionState) -> Set<String> {
        Set(current.sessionsByID.compactMap { sessionID, session in
            guard let previousSession = previous.sessionsByID[sessionID],
                  previousSession != session else {
                return nil
            }
            return sessionID
        })
    }

    private func applyNotification(_ envelope: BridgeEnvelope) {
        let event = envelope.agentEvent.map {
            rekeyEventIfNeeded($0, source: envelope.source)
        } ?? eventFromEnvelope(envelope)
        let isNativeSessionEnd: Bool
        if case let .sessionCompleted(sessionID, _, _, _, isSessionEnd) = event,
           isSessionEnd {
            isNativeSessionEnd = true
            endedSessionIDs.insert(sessionID)
            endedSessionIDs.insert(envelope.source.sessionID)
            cancelPendingDecisions(sessionID: sessionID)
            if envelope.source.sessionID != sessionID {
                cancelPendingDecisions(sessionID: envelope.source.sessionID)
            }
        } else {
            isNativeSessionEnd = false
        }

        if !isNativeSessionEnd,
           endedSessionIDs.contains(event.sessionID) || endedSessionIDs.contains(envelope.source.sessionID) {
            var changed = false
            if sessionState.sessionsByID[event.sessionID]?.isSessionEnded == true,
               case .jumpTargetUpdated = event {
                changed = apply(event, source: envelope.source)
            }
            changed = mergeSourceJumpTarget(envelope.source, sessionID: event.sessionID) || changed
            if changed {
                publishSessionState()
            }
            return
        }

        var changed = false
        if sessionState.sessionsByID[event.sessionID] == nil,
           !event.isSessionStart,
           !hasAmbiguousSessionMatch(tool: envelope.source.tool, workingDirectory: envelope.source.cwd) {
            changed = ensureSessionExists(
                for: envelope,
                at: event.timestamp.addingTimeInterval(-0.001)
            )
        }
        changed = apply(event, source: envelope.source) || changed
        changed = mergeSourceJumpTarget(envelope.source, sessionID: event.sessionID) || changed
        if changed {
            publishSessionState()
        }
    }

    private func rekeyEventIfNeeded(_ event: AgentEvent, source: SourceInfo) -> AgentEvent {
        if case .sessionStarted = event {
            return event
        }
        guard sessionState.sessionsByID[event.sessionID] == nil else {
            return event
        }
        if let cwd = source.cwd,
           let matchingSession = uniquelyMatchedSession(tool: source.tool, workingDirectory: cwd) {
            return event.rekeyed(to: matchingSession.id)
        }
        return event
    }

    private func uniquelyMatchedSession(tool: ToolKind, workingDirectory: String) -> AgentSession? {
        let matches = sessionsMatching(tool: tool, workingDirectory: workingDirectory)
        return matches.count == 1 ? matches[0] : nil
    }

    private func hasAmbiguousSessionMatch(tool: ToolKind, workingDirectory: String?) -> Bool {
        guard let workingDirectory else { return false }
        return sessionsMatching(tool: tool, workingDirectory: workingDirectory).count > 1
    }

    private func sessionsMatching(tool: ToolKind, workingDirectory: String) -> [AgentSession] {
        sessionState.sessionsByID.values.filter {
            $0.tool == tool && $0.jumpTarget?.workingDirectory == workingDirectory
        }
    }

    private func applyDecisionEntry(_ envelope: BridgeEnvelope) {
        let timestamp = envelope.agentEvent?.timestamp ?? .now
        var changed = ensureSessionExists(for: envelope, at: timestamp)
        if let event = envelope.agentEvent {
            changed = apply(event, source: envelope.source) || changed
        } else {
            switch envelope.content {
            case let .approval(content):
                changed = sessionState.apply(.permissionRequested(
                    sessionID: envelope.source.sessionID,
                    timestamp: timestamp,
                    summary: content.title
                )) || changed
            case let .question(content):
                changed = sessionState.apply(.questionAsked(
                    sessionID: envelope.source.sessionID,
                    timestamp: timestamp,
                    summary: content.title
                )) || changed
            case .completion, .status:
                break
            }
        }
        changed = mergeSourceJumpTarget(envelope.source, sessionID: envelope.source.sessionID) || changed
        if changed {
            publishSessionState()
        }
    }

    private func applyDecisionResolution(_ response: BridgeResponse, for envelope: BridgeEnvelope) {
        let changed: Bool
        switch response {
        case let .approval(decision):
            switch decision {
            case .allowOnce, .allowAlways:
                changed = sessionState.resolvePermission(
                    sessionID: envelope.source.sessionID,
                    approved: true,
                    at: .now
                )
            case .deny:
                changed = sessionState.resolvePermission(
                    sessionID: envelope.source.sessionID,
                    approved: false,
                    at: .now
                )
            }
        case let .question(answer):
            changed = sessionState.answerQuestion(
                sessionID: envelope.source.sessionID,
                summary: answer.answers.values.sorted().joined(separator: " · "),
                at: .now
            )
        case .defer:
            changed = sessionState.apply(.actionableStateResolved(
                sessionID: envelope.source.sessionID,
                timestamp: .now,
                summary: localizerProvider().text(.handledInTerminal)
            ))
        }
        if changed {
            publishSessionState()
        }
    }

    private func eventFromEnvelope(_ envelope: BridgeEnvelope) -> AgentEvent {
        switch envelope.content {
        case let .completion(content):
            return .sessionCompleted(
                sessionID: envelope.source.sessionID,
                timestamp: .now,
                summary: content.markdownSummary,
                isError: content.isError,
                isSessionEnd: false
            )
        case let .status(content):
            return .activityUpdated(sessionID: envelope.source.sessionID, timestamp: .now, summary: content.text)
        case let .approval(content):
            return .permissionRequested(sessionID: envelope.source.sessionID, timestamp: .now, summary: content.title)
        case let .question(content):
            return .questionAsked(sessionID: envelope.source.sessionID, timestamp: .now, summary: content.title)
        }
    }

    private func shouldPresent(_ envelope: BridgeEnvelope) -> Bool {
        guard let event = envelope.agentEvent else {
            return true
        }
        switch event {
        case .permissionRequested, .questionAsked:
            return true
        case .sessionStarted, .activityUpdated, .sessionCompleted, .jumpTargetUpdated, .actionableStateResolved:
            return false
        }
    }

    private func publishSessionState(allowGreeting: Bool = true) {
        if allowGreeting,
           sessionState.activeActionableSession == nil,
           let sessionID = sessionState.nextUngreetedRunningSessionID {
            var greetedState = sessionState
            greetedState.markGreetingShown(for: sessionID)
            if petController.sync(with: greetedState, activityOverride: .greeting) {
                sessionState = greetedState
                onSessionStateChange(sessionState)
                return
            }
        }

        // A rejected greeting (for example while notify/decide owns the surface)
        // keeps the session ungreeted so a later transition can try again.
        let activityOverride: SessionPetActivity? = allowGreeting ? nil : .idle
        petController.sync(with: sessionState, activityOverride: activityOverride)
        onSessionStateChange(sessionState)
    }

    @discardableResult
    private func ensureSessionExists(for envelope: BridgeEnvelope, at timestamp: Date) -> Bool {
        guard sessionState.sessionsByID[envelope.source.sessionID] == nil else {
            return false
        }
        return sessionState.apply(.sessionStarted(
            sessionID: envelope.source.sessionID,
            timestamp: timestamp,
            title: envelope.source.projectName ?? toolTitle(envelope.source.tool),
            tool: envelope.source.tool,
            summary: localizerProvider().text(.sessionStarted),
            jumpTarget: envelope.source.jumpTarget
        ))
    }

    private func toolTitle(_ tool: ToolKind) -> String {
        switch tool {
        case .claudeCode:
            "Claude Code"
        case .codex:
            "Codex"
        }
    }

    func applyForTesting(_ event: AgentEvent) {
        if apply(event, source: nil) {
            publishSessionState()
        }
    }

    @discardableResult
    private func apply(_ event: AgentEvent, source: SourceInfo?) -> Bool {
        if case .sessionStarted = event,
           sessionState.sessionsByID[event.sessionID] == nil,
           let match = matchingDiscoveredSession(for: event, source: source) {
            return sessionState.replaceDiscoveredSession(sessionID: match.id, with: event)
        }
        return sessionState.apply(event)
    }

    @discardableResult
    private func mergeSourceJumpTarget(_ source: SourceInfo, sessionID: String) -> Bool {
        guard let incoming = source.jumpTarget,
              sessionState.sessionsByID[sessionID] != nil else {
            return false
        }
        return sessionState.apply(.jumpTargetUpdated(
            sessionID: sessionID,
            timestamp: .now,
            jumpTarget: incoming
        ))
    }

    private func matchingHookSession(
        for activeSession: ActiveAgentSession,
        in state: SessionState
    ) -> AgentSession? {
        let matches = state.sessionsByID.values.filter { session in
            !Self.isDiscoveredSessionID(session.id)
                && session.tool == activeSession.tool
                && Self.jumpTargetsMatch(session.jumpTarget, activeSession.jumpTarget)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private func matchingDiscoveredSession(for event: AgentEvent, source: SourceInfo?) -> AgentSession? {
        let eventJumpTarget = source?.jumpTarget ?? eventJumpTarget(event)
        let matches = sessionState.sessionsByID.values.filter { session in
            Self.isDiscoveredSessionID(session.id)
                && session.tool == eventTool(event, source: source)
                && Self.jumpTargetsMatch(session.jumpTarget, eventJumpTarget)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private func eventTool(_ event: AgentEvent, source: SourceInfo?) -> ToolKind {
        if let source {
            return source.tool
        }
        if case let .sessionStarted(_, _, _, tool, _, _) = event {
            return tool
        }
        return .codex
    }

    private func eventJumpTarget(_ event: AgentEvent) -> JumpTarget? {
        guard case let .sessionStarted(_, _, _, _, _, jumpTarget) = event else {
            return nil
        }
        return jumpTarget
    }

    private static func isDiscoveredSessionID(_ id: String) -> Bool {
        id.hasPrefix("discovered-")
    }

    private static func jumpTargetsMatch(_ lhs: JumpTarget?, _ rhs: JumpTarget?) -> Bool {
        guard let lhs, let rhs else {
            return false
        }
        if let lhsTTY = lhs.terminalTTY.flatMap(normalizedTerminalTTY),
           let rhsTTY = rhs.terminalTTY.flatMap(normalizedTerminalTTY) {
            return lhsTTY == rhsTTY
        }
        if let lhsDirectory = lhs.workingDirectory,
           let rhsDirectory = rhs.workingDirectory {
            return lhsDirectory == rhsDirectory
        }
        return false
    }

    private static func normalizedTerminalTTY(_ tty: String) -> String? {
        let trimmed = tty.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.replacingOccurrences(of: "/dev/", with: "")
    }
}

enum AgentProcessLiveness {
    struct ProcessRow: Equatable, Sendable {
        var tty: String
        var command: String
    }

    static func liveSessionIDs(in state: SessionState) async -> Set<String> {
        let rows = await Task.detached(priority: .utility) {
            runningProcessRows()
        }.value
        return liveSessionIDs(in: state, rows: rows)
    }

    static func liveSessionIDs(in state: SessionState, rows: [ProcessRow]) -> Set<String> {
        var alive: Set<String> = []

        for session in state.sessionsByID.values {
            if session.phase.requiresAttention {
                alive.insert(session.id)
                continue
            }
            if session.isSessionEnded {
                continue
            }
            guard let tty = session.jumpTarget?.terminalTTY, !tty.isEmpty else {
                alive.insert(session.id)
                continue
            }

            let targetTTY = normalizedTTY(tty)
            if rows.contains(where: { row in
                normalizedTTY(row.tty) == targetTTY && isAgentCommand(row.command, for: session.tool)
            }) {
                alive.insert(session.id)
            }
        }

        return alive
    }

    private static func runningProcessRows() -> [ProcessRow] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "tty=,command="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            let exitGroup = DispatchGroup()
            exitGroup.enter()
            process.terminationHandler = { _ in
                exitGroup.leave()
            }
            try process.run()
            guard exitGroup.wait(timeout: .now() + 1) == .success else {
                process.terminate()
                return []
            }
            guard process.terminationStatus == 0 else {
                return []
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }
            return output.split(separator: "\n").compactMap { line in
                let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
                guard parts.count == 2 else { return nil }
                return ProcessRow(tty: String(parts[0]), command: String(parts[1]))
            }
        } catch {
            return []
        }
    }

    private static func normalizedTTY(_ tty: String) -> String {
        tty.replacingOccurrences(of: "/dev/", with: "")
    }

    private static func isAgentCommand(_ command: String, for tool: ToolKind) -> Bool {
        let lowercased = command.lowercased()
        guard !lowercased.contains("vibepethooks") else {
            return false
        }
        switch tool {
        case .claudeCode:
            return lowercased.contains("claude")
        case .codex:
            return lowercased.contains("codex")
        }
    }
}

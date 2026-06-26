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
    private let onSessionStateChange: @MainActor (SessionState) -> Void
    private var sessionState = SessionState()
    private var server: BridgeServer?
    private var notifyTask: Task<Void, Never>?
    private var decideTask: Task<Void, Never>?
    private var livenessTask: Task<Void, Never>?
    /// Receiving a real Codex hook event is the runtime evidence that the user
    /// trusted VibePet in `/hooks`; flip the manifest to `trustedActive` once
    /// (M6-5a). Cached so we stop hitting disk after the first activation.
    private var codexTrustMarked = false

    /// A response-bearing request plus the `Sendable` reply that resumes the
    /// suspended handler with the user's decision.
    private struct DecisionRequest: Sendable {
        let envelope: BridgeEnvelope
        let reply: @Sendable (BridgeResponse) -> Void
    }

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
        let (notifyStream, notifyContinuation) = AsyncStream<BridgeEnvelope>.makeStream()
        let (decideStream, decideContinuation) = AsyncStream<DecisionRequest>.makeStream()

        notifyTask = Task { @MainActor [petController] in
            for await envelope in notifyStream {
                self.markCodexTrustedIfNeeded(envelope)
                self.applyNotification(envelope)
                if self.shouldPresent(envelope) {
                    petController.handle(envelope)
                }
            }
        }

        decideTask = Task { @MainActor [petController] in
            for await request in decideStream {
                self.markCodexTrustedIfNeeded(request.envelope)
                self.applyDecisionEntry(request.envelope)
                // Await each decision on its own task so a long wait (default 20s)
                // does not block subsequent requests or notifications.
                Task { @MainActor in
                    let response = await petController.requestDecision(for: request.envelope)
                    self.applyDecisionResolution(response, for: request.envelope)
                    request.reply(response)
                }
            }
        }

        let server = BridgeServer(socketPath: socketPath) { envelope in
            if envelope.content.needsResponse {
                let response: BridgeResponse = await withCheckedContinuation { continuation in
                    decideContinuation.yield(
                        DecisionRequest(envelope: envelope) { continuation.resume(returning: $0) }
                    )
                }
                return BridgeResponseEnvelope(requestId: envelope.requestId, response: response)
            } else {
                notifyContinuation.yield(envelope)
                // Notifications don't need a real response; the CLI sends one-way
                // and closes. Reply with `defer` to satisfy the handler contract.
                return BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
            }
        }
        self.server = server

        startLivenessSweep()
        Task { @MainActor in
            await runLivenessSweepOnce()
        }

        Task {
            do {
                try await server.start()
            } catch {
                NSLog("VibePet bridge server failed to start: \(error)")
            }
        }
    }

    func stop() {
        server?.stop()
        server = nil
        notifyTask?.cancel()
        notifyTask = nil
        decideTask?.cancel()
        decideTask = nil
        livenessTask?.cancel()
        livenessTask = nil
    }

    var sessionStateSnapshot: SessionState {
        sessionState
    }

    func runLivenessSweepOnce() async {
        let activeSessions = await activeSessionProvider()
        let discoveredSessionIDs = importActiveSessions(activeSessions)
        let aliveSessionIDs = await liveSessionProvider(sessionState).union(discoveredSessionIDs)
        sessionState.markProcessLiveness(aliveSessionIDs: aliveSessionIDs)
        let visibleSessions = sessionState.visibleSessions
        let resolver = terminalJumpResolver
        let jumpTargetUpdates = await Task.detached(priority: .utility) {
            resolver.resolveJumpTargets(for: visibleSessions)
        }.value
        for (sessionID, jumpTarget) in jumpTargetUpdates {
            sessionState.apply(.jumpTargetUpdated(
                sessionID: sessionID,
                timestamp: .now,
                jumpTarget: jumpTarget
            ))
        }
        sessionState.removeInvisibleSessions()
        publishSessionState()
    }

    private func importActiveSessions(_ activeSessions: [ActiveAgentSession]) -> Set<String> {
        var discoveredAliveIDs: Set<String> = []
        for activeSession in activeSessions {
            if sessionState.sessionsByID[activeSession.id] != nil {
                discoveredAliveIDs.insert(activeSession.id)
                continue
            }
            if let matchingHookSession = matchingHookSession(for: activeSession) {
                discoveredAliveIDs.insert(matchingHookSession.id)
                continue
            }
            let now = Date.now
            sessionState.upsertDiscoveredSession(AgentSession(
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

    private func startLivenessSweep() {
        livenessTask?.cancel()
        let nanos = UInt64(livenessInterval * 1_000_000_000)
        livenessTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled else { return }
                await self?.runLivenessSweepOnce()
            }
        }
    }

    private func applyNotification(_ envelope: BridgeEnvelope) {
        if let event = envelope.agentEvent {
            apply(rekeyEventIfNeeded(event, source: envelope.source), source: envelope.source)
            publishSessionState()
            return
        }
        sessionState.apply(eventFromEnvelope(envelope))
        publishSessionState()
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
        let matches = sessionState.sessionsByID.values.filter {
            $0.tool == tool && $0.jumpTarget?.workingDirectory == workingDirectory
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private func applyDecisionEntry(_ envelope: BridgeEnvelope) {
        ensureSessionExists(for: envelope)
        if let event = envelope.agentEvent {
            apply(event, source: envelope.source)
            publishSessionState()
            return
        }
        switch envelope.content {
        case let .approval(content):
            sessionState.apply(.permissionRequested(
                sessionID: envelope.source.sessionID,
                timestamp: .now,
                summary: content.title
            ))
        case let .question(content):
            sessionState.apply(.questionAsked(
                sessionID: envelope.source.sessionID,
                timestamp: .now,
                summary: content.title
            ))
        case .completion, .status:
            break
        }
        publishSessionState()
    }

    private func applyDecisionResolution(_ response: BridgeResponse, for envelope: BridgeEnvelope) {
        switch response {
        case let .approval(decision):
            switch decision {
            case .allowOnce, .allowAlways:
                sessionState.resolvePermission(sessionID: envelope.source.sessionID, approved: true, at: .now)
            case .deny:
                sessionState.resolvePermission(sessionID: envelope.source.sessionID, approved: false, at: .now)
            }
        case let .question(answer):
            sessionState.answerQuestion(
                sessionID: envelope.source.sessionID,
                summary: answer.answers.values.sorted().joined(separator: " · "),
                at: .now
            )
        case .defer:
            sessionState.apply(.actionableStateResolved(
                sessionID: envelope.source.sessionID,
                timestamp: .now,
                summary: "Handled in terminal"
            ))
        }
        publishSessionState()
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
        case .sessionStarted:
            return false
        case let .activityUpdated(_, _, summary):
            return !SessionState.isUserPromptSummary(summary)
        case .permissionRequested, .questionAsked, .sessionCompleted, .jumpTargetUpdated, .actionableStateResolved:
            return true
        }
    }

    private func publishSessionState() {
        if sessionState.activeActionableSession != nil {
            petController.sync(with: sessionState)
        } else if let sessionID = sessionState.nextUngreetedRunningSessionID, petController.greet() {
            sessionState.markGreetingShown(for: sessionID)
        } else {
            petController.sync(with: sessionState)
        }
        onSessionStateChange(sessionState)
    }

    private func ensureSessionExists(for envelope: BridgeEnvelope) {
        guard sessionState.sessionsByID[envelope.source.sessionID] == nil else {
            return
        }
        sessionState.apply(.sessionStarted(
            sessionID: envelope.source.sessionID,
            timestamp: .now,
            title: envelope.source.projectName ?? toolTitle(envelope.source.tool),
            tool: envelope.source.tool,
            summary: "Session started",
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
        apply(event, source: nil)
        publishSessionState()
    }

    private func apply(_ event: AgentEvent, source: SourceInfo?) {
        if case .sessionStarted = event {
            removeMatchingDiscoveredPlaceholder(for: event, source: source)
        }
        sessionState.apply(event)
    }

    private func removeMatchingDiscoveredPlaceholder(for event: AgentEvent, source: SourceInfo?) {
        guard sessionState.sessionsByID[event.sessionID] == nil else {
            return
        }
        guard let match = matchingDiscoveredSession(for: event, source: source) else {
            return
        }
        sessionState.removeSession(sessionID: match.id)
    }

    private func matchingHookSession(for activeSession: ActiveAgentSession) -> AgentSession? {
        let matches = sessionState.sessionsByID.values.filter { session in
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

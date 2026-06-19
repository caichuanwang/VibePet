import Foundation

/// Drives the `VibePetHooks` CLI: read a tool event from stdin, normalize it via
/// a `ToolAdapter`, and either forward notification traffic (fire-and-forget) or
/// run the blocking decision round trip (approval / question) and encode the
/// tool-native response. Every failure path (unparseable input, an ignored event,
/// an unreachable App, a connection/read timeout) resolves to `.deferred` so the
/// calling tool falls back to its native flow — fail-open is the contract (§7).
///
/// Lives in `VibePetCore` (not the executable target) so the orchestration is unit
/// testable; `VibePetHooks/main.swift` is a thin shell over `run`.
public struct HookRuntime: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// A notification envelope was delivered to the App (no stdout).
        case sent
        /// A decision round trip completed; `Data` is the tool-native bytes to
        /// write to stdout (empty when the decision was a defer).
        case responded(Data)
        /// Nothing was delivered; the tool should use its native flow (no stdout).
        case deferred
    }

    enum HookRuntimeError: Error { case noDecisionSender }

    private let adapter: any ToolAdapter
    private let sendNotification: @Sendable (BridgeEnvelope) async throws -> Void
    private let sendDecision: @Sendable (BridgeEnvelope) async throws -> BridgeResponseEnvelope

    public init(adapter: any ToolAdapter = ClaudeCodeAdapter(), client: BridgeClient = BridgeClient()) {
        self.adapter = adapter
        self.sendNotification = { try await client.sendOneWay($0) }
        self.sendDecision = { try await client.send($0) }
    }

    init(
        adapter: any ToolAdapter,
        sendNotification: @escaping @Sendable (BridgeEnvelope) async throws -> Void,
        sendDecision: @escaping @Sendable (BridgeEnvelope) async throws -> BridgeResponseEnvelope = { _ in
            throw HookRuntimeError.noDecisionSender
        }
    ) {
        self.adapter = adapter
        self.sendNotification = sendNotification
        self.sendDecision = sendDecision
    }

    public func run(stdin: Data, env: [String: String]) async -> Outcome {
        let parsed: BridgeEnvelope?
        do {
            parsed = try adapter.parseEvent(stdin: stdin, env: env)
        } catch {
            return .deferred
        }

        guard let envelope = parsed else {
            // The adapter ignores this event; nothing to deliver.
            return .deferred
        }

        if envelope.content.needsResponse {
            return await runDecision(envelope)
        } else {
            return await runNotification(envelope)
        }
    }

    /// Notification (`completion` / `status`): write one line and return — no
    /// response is awaited.
    private func runNotification(_ envelope: BridgeEnvelope) async -> Outcome {
        do {
            try await sendNotification(envelope)
            return .sent
        } catch {
            // App not running / connection failed / timed out → fail open.
            return .deferred
        }
    }

    /// Decision (`approval` / `question`): keep the connection open and block for
    /// the user's response (bounded by the client read deadline). On a response,
    /// encode the tool-native output. Any failure — connection refused, broken
    /// socket, or the read deadline elapsing with no reply — fails open.
    private func runDecision(_ envelope: BridgeEnvelope) async -> Outcome {
        do {
            let responseEnvelope = try await sendDecision(envelope)
            let data = adapter.encodeResponse(responseEnvelope.response, for: envelope)
            return .responded(data)
        } catch {
            return .deferred
        }
    }
}

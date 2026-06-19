import Foundation

/// Drives the `VibePetHooks` CLI: read a tool event from stdin, normalize it via
/// a `ToolAdapter`, and forward notification traffic to the App over the bridge.
/// Every failure path (unparseable input, an event the adapter ignores, an
/// unreachable App, a connection timeout) resolves to `.deferred` so the calling
/// tool falls back to its native flow — fail-open is the contract (§7).
///
/// Lives in `VibePetCore` (not the executable target) so the orchestration is unit
/// testable; `VibePetHooks/main.swift` is a thin shell over `run`.
public struct HookRuntime: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// A notification envelope was delivered to the App.
        case sent
        /// Nothing was delivered; the tool should use its native flow.
        case deferred
    }

    private let adapter: any ToolAdapter
    private let sendNotification: @Sendable (BridgeEnvelope) async throws -> Void

    public init(adapter: any ToolAdapter = ClaudeCodeAdapter(), client: BridgeClient = BridgeClient()) {
        self.adapter = adapter
        self.sendNotification = { try await client.sendOneWay($0) }
    }

    init(
        adapter: any ToolAdapter,
        sendNotification: @escaping @Sendable (BridgeEnvelope) async throws -> Void
    ) {
        self.adapter = adapter
        self.sendNotification = sendNotification
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

        guard !envelope.content.needsResponse else {
            // Approval / question are blocking, response-bearing paths handled in
            // M4 / M5. In M3 they are deferred to the native flow.
            return .deferred
        }

        do {
            try await sendNotification(envelope)
            return .sent
        } catch {
            // App not running / connection failed / timed out → fail open.
            return .deferred
        }
    }
}

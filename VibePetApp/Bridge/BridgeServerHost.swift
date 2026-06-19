import AppKit
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
    private var server: BridgeServer?
    private var notifyTask: Task<Void, Never>?
    private var decideTask: Task<Void, Never>?

    /// A response-bearing request plus the `Sendable` reply that resumes the
    /// suspended handler with the user's decision.
    private struct DecisionRequest: Sendable {
        let envelope: BridgeEnvelope
        let reply: @Sendable (BridgeResponse) -> Void
    }

    init(petController: PetController, socketPath: SocketPath = SocketPath()) {
        self.petController = petController
        self.socketPath = socketPath
    }

    func start() {
        let (notifyStream, notifyContinuation) = AsyncStream<BridgeEnvelope>.makeStream()
        let (decideStream, decideContinuation) = AsyncStream<DecisionRequest>.makeStream()

        notifyTask = Task { @MainActor [petController] in
            for await envelope in notifyStream {
                petController.handle(envelope)
            }
        }

        decideTask = Task { @MainActor [petController] in
            for await request in decideStream {
                // Await each decision on its own task so a long wait (default 20s)
                // does not block subsequent requests or notifications.
                Task { @MainActor in
                    let response = await petController.requestDecision(for: request.envelope)
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
    }
}

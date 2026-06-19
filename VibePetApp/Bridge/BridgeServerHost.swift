import AppKit
import VibePetCore

/// Runs the `BridgeServer` for the running App and routes received envelopes to
/// the `PetController` on the main actor. The server handler is `@Sendable` and
/// runs off the main actor, so envelopes are funneled through an `AsyncStream`
/// (its continuation is `Sendable`, `BridgeEnvelope` is `Sendable`) and consumed
/// on a main-actor task — keeping `PetController` main-actor isolated.
@MainActor
final class BridgeServerHost {
    private let petController: PetController
    private let socketPath: SocketPath
    private var server: BridgeServer?
    private var consumerTask: Task<Void, Never>?

    init(petController: PetController, socketPath: SocketPath = SocketPath()) {
        self.petController = petController
        self.socketPath = socketPath
    }

    func start() {
        let (stream, continuation) = AsyncStream<BridgeEnvelope>.makeStream()

        consumerTask = Task { @MainActor [petController] in
            for await envelope in stream {
                petController.handle(envelope)
            }
        }

        let server = BridgeServer(socketPath: socketPath) { envelope in
            continuation.yield(envelope)
            // Notifications don't need a real response; the CLI sends one-way and
            // closes. Reply with `defer` to satisfy the handler contract.
            return BridgeResponseEnvelope(requestId: envelope.requestId, response: .defer)
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
        consumerTask?.cancel()
        consumerTask = nil
    }
}

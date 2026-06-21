import Foundation
import VibePetCore

// Thin shell over `HookRuntime`. Reads the tool's native event from stdin, runs
// either the notification (fire-and-forget) or the blocking decision round trip,
// writes the tool-native response (if any) to stdout, and always exits 0.
//
// `main.swift` top-level code runs on the MainActor (Swift 5.5+). We must NOT
// block the main thread with a semaphore and run the work in a `Task`: that Task
// inherits MainActor isolation, so it would deadlock waiting for the very thread
// the semaphore is blocking — hanging every hook invocation (a fail-open
// violation). Top-level `await` suspends the main actor correctly while the
// cooperative pool drives the bridge I/O.
//
// Fail-open is the contract: defer == no stdout, exit 0 → the tool falls back to
// its native permission flow. For decisions, the CLI read deadline is the final
// fail-open backstop if the App crashes mid-decision; we give it a small margin
// over the App-side countdown so the App replies first in the normal "no user
// response" case (technical design §3.4 / §7).
let arguments = CommandLine.arguments
let environment = ProcessInfo.processInfo.environment

// Per-process opt-out: a wrapper that owns this child agent's permission flow sets
// `VIBEPET_SKIP_HOOKS=1` so we no-op without reading stdin or touching the bridge.
// Global install state is unchanged; other agents still get the VibePet flow.
if HookSkipConfiguration.shouldSkip(environment: environment) {
    exit(0)
}

// Optional diagnostics: when `VIBEPET_HOOKS_DEBUG` is truthy, surface fail-open
// reasons (bridge unreachable / timed out) on stderr. Silent by default so normal
// runs add no terminal noise.
let hooksDebugEnabled = HookSkipConfiguration.isTruthy(environment["VIBEPET_HOOKS_DEBUG"])
let debugLog: @Sendable (String) -> Void = { message in
    guard hooksDebugEnabled else { return }
    FileHandle.standardError.write(Data("[VibePetHooks] \(message)\n".utf8))
}

// Adapter selection by tool (technical design §4.2): `--tool codex` → CodexAdapter,
// otherwise ClaudeCodeAdapter. Codex's `notify` program passes its JSON payload as
// the last argv (`--notify`); everything else reads the event from stdin.
let adapter = HookInvocation.adapter(forTool: HookInvocation.toolArgument(in: arguments))
let stdinData = HookInvocation.isNotify(arguments: arguments)
    ? Data()
    : FileHandle.standardInput.readDataToEndOfFile()
let eventData = HookInvocation.eventData(arguments: arguments, stdin: stdinData)

// Optional test/sandbox isolation: point the bridge + config at a custom support
// directory instead of the user's real one. Unset in normal use → default path.
let supportRoot = environment["VIBEPET_SUPPORT_DIR"].map { URL(fileURLWithPath: $0) }

let decisionTimeout = ((try? ConfigStore(applicationSupportRoot: supportRoot).read()) ?? .default)
    .decisionTimeoutSeconds
let client = BridgeClient(socketPath: SocketPath(applicationSupportRoot: supportRoot), readTimeout: decisionTimeout + 5)
let runtime = HookRuntime(adapter: adapter, client: client, log: debugLog)

let outcome = await runtime.run(stdin: eventData, env: environment)
if case let .responded(data) = outcome, !data.isEmpty {
    FileHandle.standardOutput.write(data)
}

exit(0)

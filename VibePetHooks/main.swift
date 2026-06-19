import Foundation
import VibePetCore

// Thin shell over `HookRuntime`. Reads the tool's native event from stdin,
// forwards notification traffic to the App, and always exits 0 — emitting no
// stdout for the M3 notification subset (defer == no JSON for Claude Code).
// Approval / question stdout encoding lands in M4 / M5.
// `main.swift` top-level code runs on the MainActor (Swift 5.5+). We must NOT
// block the main thread with a semaphore and run the work in a `Task`: that Task
// inherits MainActor isolation, so it would deadlock waiting for the very thread
// the semaphore is blocking — hanging every hook invocation (a fail-open
// violation). Top-level `await` suspends the main actor correctly while the
// cooperative pool drives the bridge I/O.
let stdinData = FileHandle.standardInput.readDataToEndOfFile()
let environment = ProcessInfo.processInfo.environment

let runtime = HookRuntime()
_ = await runtime.run(stdin: stdinData, env: environment)

exit(0)

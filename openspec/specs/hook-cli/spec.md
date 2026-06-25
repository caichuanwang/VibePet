## Purpose

Define the `VibePetHooks` command-line bridge that reads a tool's native event from stdin, normalizes it, and forwards notification envelopes to the App while preserving fail-open behavior.
## Requirements
### Requirement: Hook CLI selects the tool adapter by invocation

`VibePetHooks` SHALL select its `ToolAdapter` from an explicit tool identifier passed at invocation (e.g. `--tool codex` selects `CodexAdapter`; absent/default selects `ClaudeCodeAdapter`). The installer SHALL write each tool's hook `command` with the matching identifier. The CLI SHALL NOT infer the tool by sniffing event shape.

#### Scenario: Codex invocation selects CodexAdapter

- **WHEN** `VibePetHooks` is invoked with the Codex tool identifier
- **THEN** it uses `CodexAdapter` to parse and encode

#### Scenario: Default invocation selects ClaudeCodeAdapter

- **WHEN** `VibePetHooks` is invoked with no tool identifier
- **THEN** it uses `ClaudeCodeAdapter`

### Requirement: Hook CLI reads stdin and normalizes via adapter

`VibePetHooks` SHALL read a tool's native event JSON from stdin, select the appropriate `ToolAdapter`, and call `parseEvent(stdin:env:)` to normalize it into a `BridgeEnvelope`. The selected adapter SHALL use the supplied environment to attach a best-effort terminal jump target when terminal app, cwd, tty, or locator data is available. When the adapter returns `nil` (an event it does not care about) the CLI SHALL exit `0` without contacting the App.

#### Scenario: Notification event is normalized

- **WHEN** `VibePetHooks` receives a recognized notification event on stdin
- **THEN** it produces a `BridgeEnvelope` whose `content` is a non-response form (`.completion` or `.status`)

#### Scenario: Recognized event includes terminal jump target when available

- **WHEN** `VibePetHooks` receives a recognized event and the adapter can infer terminal jump-back data from `env`, cwd, tty, or an injected locator
- **THEN** the resulting `BridgeEnvelope.source.jumpTarget` contains that best-effort terminal target

#### Scenario: Ignored event exits cleanly

- **WHEN** the selected adapter's `parseEvent` returns `nil` for the stdin event
- **THEN** the CLI exits `0` without opening a socket connection

### Requirement: Hook CLI sends notification envelopes without waiting

For notification-class content (`needsResponse == false`), `VibePetHooks` SHALL connect to the bridge socket via `BridgeClient`, send the `BridgeEnvelope` as one newline-delimited JSON message, and exit `0` immediately without waiting for any response.

#### Scenario: Notification is sent and CLI exits

- **WHEN** a `.completion` or `.status` envelope is sent to a running App
- **THEN** the App receives the envelope and the CLI exits `0` without blocking on a reply

### Requirement: Hook CLI fails open when the App is unreachable

If the App is not running, the socket connection fails, the socket is broken, stdin input is malformed, or terminal jump-target capture fails, `VibePetHooks` SHALL fall back to the tool's native flow within ≤2s by emitting no output and exiting `0`, rather than hanging. Empty stdout is the tool-native `defer`/decline for both tools: Claude Code treats no JSON as a non-decision, and Codex treats no output (and any non-JSON) as "no decision → native approval flow".

#### Scenario: App not running yields prompt defer

- **WHEN** `VibePetHooks` runs with no App listening on the bridge socket
- **THEN** it emits no output, exits `0`, and returns within ≤2s

#### Scenario: Malformed stdin does not hang

- **WHEN** stdin contains input that cannot be parsed into a known event
- **THEN** the CLI defers to the native flow and exits without error to the tool

#### Scenario: Jump target capture failure does not hang

- **WHEN** terminal app inference, tty capture, or the focused-terminal locator fails while parsing an otherwise recognized hook event
- **THEN** the CLI still follows the normal envelope send or defer behavior and does not emit an error to the tool because jump-back precision failed

### Requirement: Hook CLI blocks for decision response with bounded wait

For decision-class content (`needsResponse == true`), `VibePetHooks` SHALL send the `BridgeEnvelope` and keep the connection open to await a `BridgeResponseEnvelope`, bounded by a configurable user-response deadline (default 20s) that MUST be less than the tool's hook timeout. On receiving the response it SHALL encode the tool-native output via the selected `ToolAdapter`, write it to stdout, and `exit 0`.

#### Scenario: Approval response is written and CLI exits

- **WHEN** the App replies with a `BridgeResponseEnvelope` for a decision-class envelope before the deadline
- **THEN** the CLI encodes the adapter's tool-native output to stdout and exits `0`

#### Scenario: Decision wait is bounded by a deadline

- **WHEN** a decision-class envelope is sent and the App is connected
- **THEN** the CLI waits for the response no longer than the configured deadline (default 20s, < hook timeout)

### Requirement: Decision path fails open on unreachable app or no response

For decision-class content, `VibePetHooks` SHALL fail open in two cases: if the App is not running, the connection fails, or the socket is broken, it SHALL `defer` within ≤2s; if the App is connected but the user does not respond by the deadline, it SHALL `defer` at the deadline. A `defer` is empty stdout + `exit 0` for both tools (Claude Code: no JSON; Codex: no output → native approval flow). When the App returns an explicit `defer` response, the selected adapter's `encodeResponse` likewise yields empty output.

#### Scenario: App not running defers within 2s

- **WHEN** a decision-class event is processed with no App listening on the bridge socket
- **THEN** the CLI emits no output, exits `0`, and returns within ≤2s

#### Scenario: No user response defers at the deadline

- **WHEN** the App is connected but the user does not respond before the configured deadline
- **THEN** the CLI emits no output and exits `0` at the deadline rather than hanging

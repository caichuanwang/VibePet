## Purpose

Define the `VibePetHooks` command-line bridge that reads a tool's native event from stdin, normalizes it, and forwards notification envelopes to the App while preserving fail-open behavior.
## Requirements
### Requirement: Hook CLI reads stdin and normalizes via adapter

`VibePetHooks` SHALL read a tool's native event JSON from stdin, select the appropriate `ToolAdapter`, and call `parseEvent(stdin:env:)` to normalize it into a `BridgeEnvelope`. When the adapter returns `nil` (an event it does not care about) the CLI SHALL exit `0` without contacting the App.

#### Scenario: Notification event is normalized

- **WHEN** `VibePetHooks` receives a recognized notification event on stdin
- **THEN** it produces a `BridgeEnvelope` whose `content` is a non-response form (`.completion` or `.status`)

#### Scenario: Ignored event exits cleanly

- **WHEN** the selected adapter's `parseEvent` returns `nil` for the stdin event
- **THEN** the CLI exits `0` without opening a socket connection

### Requirement: Hook CLI sends notification envelopes without waiting

For notification-class content (`needsResponse == false`), `VibePetHooks` SHALL connect to the bridge socket via `BridgeClient`, send the `BridgeEnvelope` as one newline-delimited JSON message, and exit `0` immediately without waiting for any response.

#### Scenario: Notification is sent and CLI exits

- **WHEN** a `.completion` or `.status` envelope is sent to a running App
- **THEN** the App receives the envelope and the CLI exits `0` without blocking on a reply

### Requirement: Hook CLI fails open when the App is unreachable

If the App is not running, the socket connection fails, the socket is broken, or the stdin input is malformed, `VibePetHooks` SHALL fall back to the tool's native flow within ≤2s by emitting a `defer` outcome (for Claude Code: exit `0` with no JSON) rather than hanging.

#### Scenario: App not running yields prompt defer

- **WHEN** `VibePetHooks` runs with no App listening on the bridge socket
- **THEN** it returns the `defer` outcome and exits within ≤2s

#### Scenario: Malformed stdin does not hang

- **WHEN** stdin contains input that cannot be parsed into a known event
- **THEN** the CLI defers to the native flow and exits without error to the tool

### Requirement: Hook CLI blocks for decision response with bounded wait

For decision-class content (`needsResponse == true`), `VibePetHooks` SHALL send the `BridgeEnvelope` and keep the connection open to await a `BridgeResponseEnvelope`, bounded by a configurable user-response deadline (default 20s) that MUST be less than the tool's hook timeout. On receiving the response it SHALL encode the tool-native output via the selected `ToolAdapter`, write it to stdout, and `exit 0`.

#### Scenario: Approval response is written and CLI exits

- **WHEN** the App replies with a `BridgeResponseEnvelope` for a decision-class envelope before the deadline
- **THEN** the CLI encodes the adapter's tool-native output to stdout and exits `0`

#### Scenario: Decision wait is bounded by a deadline

- **WHEN** a decision-class envelope is sent and the App is connected
- **THEN** the CLI waits for the response no longer than the configured deadline (default 20s, < hook timeout)

### Requirement: Decision path fails open on unreachable app or no response

For decision-class content, `VibePetHooks` SHALL fail open in two cases: if the App is not running, the connection fails, or the socket is broken, it SHALL `defer` within ≤2s; if the App is connected but the user does not respond by the deadline, it SHALL `defer` at the deadline. A `defer` for Claude Code means no JSON output and `exit 0`.

#### Scenario: App not running defers within 2s

- **WHEN** a decision-class event is processed with no App listening on the bridge socket
- **THEN** the CLI defers (no JSON, exit `0`) within ≤2s

#### Scenario: No user response defers at the deadline

- **WHEN** the App is connected but the user does not respond before the configured deadline
- **THEN** the CLI defers (no JSON, exit `0`) at the deadline rather than hanging


## ADDED Requirements

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

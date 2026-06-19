## ADDED Requirements

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

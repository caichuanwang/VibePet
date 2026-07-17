## MODIFIED Requirements

### Requirement: Hook CLI blocks for decision response with bounded wait

For decision-class content (`needsResponse == true`), `VibePetHooks` SHALL send the `BridgeEnvelope` and keep the connection open for one matching `BridgeResponseEnvelope`. The entire response frame SHALL use a tool-specific monotonic deadline below the native hook timeout: 86,390 seconds for Claude Code and 3,590 seconds for Codex. On receiving the response it SHALL encode the selected adapter's native output, write it once to stdout, and exit `0`.

#### Scenario: Approval response is written and CLI exits

- **WHEN** the App replies with the matching response before the tool-specific deadline
- **THEN** the CLI writes exactly one native response to stdout and exits `0`

#### Scenario: Decision wait uses the tool-specific absolute deadline

- **WHEN** a connected peer stalls or drip-feeds an incomplete response
- **THEN** Claude Code and Codex stop waiting at their respective CLI deadlines rather than resetting the deadline per byte

### Requirement: Decision path fails open on unreachable app or no response

For decision-class content, `VibePetHooks` SHALL fail open on connect failure, malformed response, mismatched request ID, disconnect, or timeout. Connect failure SHALL return within two seconds; a connected decision SHALL return at its tool-specific deadline. Fail-open output is empty stdout and exit `0`, allowing both tools to use their native flow.

#### Scenario: App not running defers within two seconds

- **WHEN** a decision-class event is processed with no App listening
- **THEN** the CLI emits no output, exits `0`, and returns within two seconds

#### Scenario: No response defers at the deadline

- **WHEN** the App is connected but no complete matching response arrives before the configured deadline
- **THEN** the CLI emits no output and exits `0` at the absolute deadline

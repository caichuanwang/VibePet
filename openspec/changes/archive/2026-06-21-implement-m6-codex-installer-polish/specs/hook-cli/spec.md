## ADDED Requirements

### Requirement: Hook CLI selects the tool adapter by invocation

`VibePetHooks` SHALL select its `ToolAdapter` from an explicit tool identifier passed at invocation (e.g. `--tool codex` selects `CodexAdapter`; absent/default selects `ClaudeCodeAdapter`). The installer SHALL write each tool's hook `command` with the matching identifier. The CLI SHALL NOT infer the tool by sniffing event shape.

#### Scenario: Codex invocation selects CodexAdapter

- **WHEN** `VibePetHooks` is invoked with the Codex tool identifier
- **THEN** it uses `CodexAdapter` to parse and encode

#### Scenario: Default invocation selects ClaudeCodeAdapter

- **WHEN** `VibePetHooks` is invoked with no tool identifier
- **THEN** it uses `ClaudeCodeAdapter`

## MODIFIED Requirements

### Requirement: Hook CLI fails open when the App is unreachable

If the App is not running, the socket connection fails, the socket is broken, or the stdin input is malformed, `VibePetHooks` SHALL fall back to the tool's native flow within ≤2s by emitting no output and exiting `0`, rather than hanging. Empty stdout is the tool-native `defer`/decline for both tools: Claude Code treats no JSON as a non-decision, and Codex treats no output (and any non-JSON) as "no decision → native approval flow".

#### Scenario: App not running yields prompt defer

- **WHEN** `VibePetHooks` runs with no App listening on the bridge socket
- **THEN** it emits no output, exits `0`, and returns within ≤2s

#### Scenario: Malformed stdin does not hang

- **WHEN** stdin contains input that cannot be parsed into a known event
- **THEN** the CLI defers to the native flow and exits without error to the tool

### Requirement: Decision path fails open on unreachable app or no response

For decision-class content, `VibePetHooks` SHALL fail open in two cases: if the App is not running, the connection fails, or the socket is broken, it SHALL `defer` within ≤2s; if the App is connected but the user does not respond by the deadline, it SHALL `defer` at the deadline. A `defer` is empty stdout + `exit 0` for both tools (Claude Code: no JSON; Codex: no output → native approval flow). When the App returns an explicit `defer` response, the selected adapter's `encodeResponse` likewise yields empty output.

#### Scenario: App not running defers within 2s

- **WHEN** a decision-class event is processed with no App listening on the bridge socket
- **THEN** the CLI emits no output, exits `0`, and returns within ≤2s

#### Scenario: No user response defers at the deadline

- **WHEN** the App is connected but the user does not respond before the configured deadline
- **THEN** the CLI emits no output and exits `0` at the deadline rather than hanging

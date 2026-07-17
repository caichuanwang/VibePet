## MODIFIED Requirements

### Requirement: CodexAdapter downgrades input-requiring events to terminal approval

`CodexAdapter` SHALL map an input-requiring Codex event to terminal-only approval only when that event and its inability to accept hook output are demonstrated by a checked-in fixture or pinned upstream test. It SHALL NOT infer Codex capability from Claude-only tool names such as `AskUserQuestion`. An unverified tool name in an otherwise valid binary `PermissionRequest` SHALL remain a generic binary approval with no free-form or persistent-allow behavior.

#### Scenario: Unverified Claude tool name does not invent Codex capability

- **WHEN** a Codex-shaped `PermissionRequest` uses `tool_name: "AskUserQuestion"` without verified Codex schema evidence
- **THEN** the adapter does not emit `.question` or set `requiresTerminalApproval`

## ADDED Requirements

### Requirement: Codex compatibility aliases remain evidence-backed and fail-open

`CodexAdapter` SHALL accept only session/thread identifier aliases demonstrated by checked-in fixtures or the pinned upstream tests. Malformed, unknown, answer-requiring, or terminal-required payloads that cannot be encoded safely SHALL return no output and allow Codex's native flow. It MUST NOT invent free-form answer or persistent-allow capability.

#### Scenario: Verified session fields correlate one session

- **WHEN** a hook fixture uses `session_id` or an `agent-turn-complete` fixture uses `thread-id`
- **THEN** the resulting source carries that surface-specific value as its stable session ID

#### Scenario: Turn identity is not reused as session identity

- **WHEN** a notify payload has `turn-id` but no verified `thread-id`
- **THEN** the adapter does not create a session event from the turn identifier

#### Scenario: Unknown payload emits no decision

- **WHEN** an unknown or malformed Codex payload is received
- **THEN** parsing returns nil or defer and the CLI emits no stdout

#### Scenario: Unverified persistent allow is not emitted

- **WHEN** the App response requests an always-allow behavior without a verified Codex persistent rule schema
- **THEN** the adapter emits at most the verified single-request decision behavior

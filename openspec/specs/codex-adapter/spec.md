# codex-adapter Specification

## Purpose

Define the `CodexAdapter` that normalizes Codex CLI hook events into VibePet `BridgeEnvelope`s and encodes VibePet decisions back into Codex-native hook output, preserving fail-open behavior.

## Requirements

### Requirement: CodexAdapter normalizes PermissionRequest to approval

`CodexAdapter` SHALL conform to `ToolAdapter` with `tool == .codex` and parse a Codex `PermissionRequest` hook event from stdin into a `BridgeEnvelope` whose content is `.approval`. Shell-escalation requests SHALL produce an `ActionPreview.command`; apply-patch requests SHALL produce an `ActionPreview.fileChange`. The approval SHALL be risk-classified via `RiskClassifier` and SHALL set `requiresTerminalApproval == false`.

#### Scenario: Shell escalation becomes a command approval

- **WHEN** a Codex `PermissionRequest` for a shell escalation is read from stdin
- **THEN** the adapter returns an `.approval` envelope with an `ActionPreview.command` and a classified `RiskLevel`

#### Scenario: apply-patch becomes a file-change approval

- **WHEN** a Codex `PermissionRequest` for an apply-patch is read from stdin
- **THEN** the adapter returns an `.approval` envelope with an `ActionPreview.fileChange`

### Requirement: CodexAdapter normalizes turn completion to completion

`CodexAdapter` SHALL parse a Codex `Stop` hook event into a `BridgeEnvelope` whose content is `.completion` (a non-response notification), using `last_assistant_message` as the summary. VibePet registers the `Stop` hook for turn-completion (open-vibe-island pattern) rather than the `notify` program; for robustness the adapter SHALL ALSO accept a `notify` payload of type `agent-turn-complete` (using `last-assistant-message`). Other lifecycle hooks and unknown notify types SHALL be ignored (return `nil`).

#### Scenario: Stop hook becomes a completion notification

- **WHEN** a Codex `Stop` hook event is read from stdin
- **THEN** the adapter returns a `.completion` envelope (from `last_assistant_message`) whose `needsResponse == false`

#### Scenario: agent-turn-complete notify also becomes a completion

- **WHEN** a Codex `notify` payload of type `agent-turn-complete` is provided
- **THEN** the adapter returns a `.completion` envelope whose `needsResponse == false`

#### Scenario: Unrelated event is ignored

- **WHEN** a Codex lifecycle hook outside the supported subset, or an unsupported notify type, is read
- **THEN** the adapter returns `nil` so the CLI exits without contacting the App

### Requirement: CodexAdapter normalizes SessionStart and UserPromptSubmit to AgentEvents

`CodexAdapter` SHALL normalize a Codex `SessionStart` hook event into an `AgentEvent.sessionStarted` and a `UserPromptSubmit` hook event into an `AgentEvent.activityUpdated`, both keyed by a stable `SourceInfo.sessionID` taken from the Codex session/thread identifier in the payload. These are fire-and-forget notifications and SHALL NOT use the blocking decision channel. Parsing SHALL be fail-open: missing fields or unknown event types SHALL be dropped (return `nil`) without throwing.

#### Scenario: Codex SessionStart becomes sessionStarted

- **WHEN** a Codex `SessionStart` hook event with a session/thread id is read from stdin
- **THEN** the adapter yields an `AgentEvent.sessionStarted` whose `sessionID` is that identifier

#### Scenario: Codex UserPromptSubmit becomes activityUpdated

- **WHEN** a Codex `UserPromptSubmit` hook event is read from stdin
- **THEN** the adapter yields an `AgentEvent.activityUpdated` for the session

#### Scenario: Unknown Codex lifecycle event fails open

- **WHEN** a Codex lifecycle event outside the supported subset, or one missing its session identifier, is read
- **THEN** the adapter returns `nil` so the CLI exits without contacting the App

### Requirement: CodexAdapter populates a stable sessionID

`CodexAdapter` SHALL populate `SourceInfo.sessionID` from the Codex session/thread identifier on every envelope it produces (including the existing `PermissionRequest` and `Stop` paths), so reducer state correlates Codex events across a session. `sessionShortId` is retained for display.

#### Scenario: Permission request carries a stable sessionID

- **WHEN** a Codex `PermissionRequest` carrying a session/thread id is normalized
- **THEN** the resulting envelope's `SourceInfo.sessionID` equals that identifier

### Requirement: CodexAdapter ignores PostToolUse status-only hooks

`CodexAdapter` SHALL ignore Codex `PostToolUse` hook events. Tool-completion status is not decision-worthy and SHALL NOT create a status bubble or activity update. Parsing SHALL be fail-open: the adapter returns `nil` without throwing.

#### Scenario: Codex PostToolUse is ignored

- **WHEN** a Codex `PostToolUse` hook event with a session identifier is read from stdin
- **THEN** the adapter returns `nil` so the CLI exits without contacting the App

#### Scenario: PostToolUse missing its session identifier fails open

- **WHEN** a Codex `PostToolUse` event without a resolvable session identifier is read
- **THEN** the adapter returns `nil` so the CLI exits without contacting the App

### Requirement: CodexAdapter downgrades input-requiring events to terminal approval

`CodexAdapter` SHALL map Codex events that require free-form user input (questions, plan-mode, or other answer-requiring prompts) to an `.approval` envelope with `requiresTerminalApproval == true`, because Codex hooks cannot fill answers back. It SHALL NOT emit a `.question` envelope for Codex.

#### Scenario: Codex question downgrades to terminal approval

- **WHEN** a Codex event requiring user input is read from stdin
- **THEN** the adapter returns an `.approval` envelope with `requiresTerminalApproval == true` (not a `.question`)

### Requirement: CodexAdapter encodes decisions as allow/deny/decline idempotently

`CodexAdapter.encodeResponse(_:for:)` SHALL map `BridgeResponse.approval(.allowOnce)` and `.allowAlways` to a Codex allow decision (`allowAlways` equals a single allow unless a verified Codex persistent rule exists), `.approval(.deny)` to a deny decision, and both `BridgeResponse.question` and `BridgeResponse.defer` to a decline (no-decision) output that lets Codex fall back to its native approval. Encoding SHALL be idempotent and MUST NOT assume VibePet is the only matching hook; `requestId` is used only for VibePet's own pairing, never as a global lock. `ask` / `continue:false` fields MAY be parsed but SHALL NOT be emitted in the MVP.

#### Scenario: Allow once and always map to allow

- **WHEN** `encodeResponse` receives `.approval(.allowOnce)` or `.approval(.allowAlways)` for a Codex envelope
- **THEN** it produces a Codex allow decision

#### Scenario: Deny maps to deny

- **WHEN** `encodeResponse` receives `.approval(.deny)` for a Codex envelope
- **THEN** it produces a Codex deny decision

#### Scenario: Question and defer map to decline

- **WHEN** `encodeResponse` receives `.question(...)` or `.defer` for a Codex envelope
- **THEN** it produces a decline (no-decision) output that lets Codex use its native approval flow

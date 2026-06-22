## ADDED Requirements

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

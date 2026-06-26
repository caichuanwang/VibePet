## ADDED Requirements

### Requirement: CodexAdapter normalizes PostToolUse to an activity heartbeat

`CodexAdapter` SHALL normalize a Codex `PostToolUse` hook event into an `AgentEvent.activityUpdated`, keyed by the stable `SourceInfo.sessionID`, so a running Codex session refreshes its summary and `updatedAt` after each tool execution instead of going stale between `UserPromptSubmit` and `Stop`. The event is a fire-and-forget notification and SHALL NOT use the blocking decision channel. The summary SHALL be derived from the payload's tool name when available, falling back to a readable default. Parsing SHALL be fail-open: a missing session identifier or unreadable payload SHALL be dropped (return `nil`) without throwing, and SHALL NOT clear an in-flight attention state.

#### Scenario: Codex PostToolUse becomes activityUpdated

- **WHEN** a Codex `PostToolUse` hook event with a session identifier is read from stdin
- **THEN** the adapter yields an `AgentEvent.activityUpdated` for that session whose summary reflects the executed tool

#### Scenario: PostToolUse refreshes a running session's recency

- **WHEN** a running Codex session receives a `PostToolUse` event after a period with no other events
- **THEN** the session's `updatedAt` advances so the dashboard reflects current activity rather than a stale timestamp

#### Scenario: PostToolUse missing its session identifier fails open

- **WHEN** a Codex `PostToolUse` event without a resolvable session identifier is read
- **THEN** the adapter returns `nil` so the CLI exits without contacting the App

#### Scenario: PostToolUse does not override an active approval

- **WHEN** a session is `waitingForApproval` or `waitingForAnswer` and a `PostToolUse` activity update is applied
- **THEN** the session's attention phase is preserved (the heartbeat does not silently clear a pending decision)

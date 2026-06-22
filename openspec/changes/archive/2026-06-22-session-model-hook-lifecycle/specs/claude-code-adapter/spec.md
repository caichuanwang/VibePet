## MODIFIED Requirements

### Requirement: SourceInfo populated from event context

`ClaudeCodeAdapter` SHALL populate `SourceInfo` with `tool == .claudeCode`, the project name from the working directory basename when available, a session short id derived from the event/session identifier when available, and a stable `sessionID` taken from the hook payload's `session_id` when available. When terminal context is present in the payload/env it MAY populate `jumpTarget`.

#### Scenario: Source carries tool and project context

- **WHEN** `parseEvent` normalizes an event whose context provides a working directory and session id
- **THEN** the resulting envelope's `SourceInfo` has `tool == .claudeCode`, `projectName` set to the cwd basename, and `sessionShortId` derived from the session identifier

#### Scenario: Source carries a stable sessionID from session_id

- **WHEN** `parseEvent` normalizes an event whose payload contains `session_id`
- **THEN** the resulting envelope's `SourceInfo.sessionID` equals that `session_id` value

## ADDED Requirements

### Requirement: Claude Code lifecycle hooks normalize to AgentEvents

`ClaudeCodeAdapter` SHALL normalize the full set of Claude Code lifecycle hooks into `AgentEvent`s keyed by `SourceInfo.sessionID`, in addition to producing `BridgeEnvelope` content where applicable:
- `SessionStart` → `sessionStarted`
- `UserPromptSubmit`, `PostToolUse`, `SubagentStart`, `SubagentStop`, `PreCompact`, `Notification` → `activityUpdated`
- `PreToolUse` (tool_name ≠ `AskUserQuestion`) → `permissionRequested` (alongside the existing `.approval` content)
- `PreToolUse` with `AskUserQuestion` → `questionAsked`
- `Stop` → `sessionCompleted`; `StopFailure` → `sessionCompleted` with the error flag; `SessionEnd` → `sessionCompleted` with the session-end flag
- `PermissionDenied` → `actionableStateResolved`

Only `PreToolUse`(decision) stays on the blocking decision channel; every other lifecycle hook SHALL be a fire-and-forget notification. Parsing SHALL be fail-open: a missing field or unknown event SHALL be logged and dropped, never thrown, so the tool is never blocked. When the payload lacks a displayable summary the adapter SHALL substitute a readable fallback rather than depending on Markdown.

#### Scenario: SessionStart becomes sessionStarted

- **WHEN** `parseEvent` is given a Claude Code `SessionStart` event with a `session_id`
- **THEN** it yields an `AgentEvent.sessionStarted` carrying that `sessionID`

#### Scenario: PostToolUse becomes activityUpdated

- **WHEN** `parseEvent` is given a `PostToolUse` event
- **THEN** it yields an `AgentEvent.activityUpdated` for the session, not a decision-channel event

#### Scenario: StopFailure marks an errored completion

- **WHEN** `parseEvent` is given a `StopFailure` event
- **THEN** it yields an `AgentEvent.sessionCompleted` whose error flag is set

#### Scenario: SessionEnd marks a session-end completion

- **WHEN** `parseEvent` is given a `SessionEnd` event
- **THEN** it yields an `AgentEvent.sessionCompleted` whose session-end flag is set

#### Scenario: Malformed lifecycle payload fails open

- **WHEN** `parseEvent` is given a lifecycle event with missing or malformed fields
- **THEN** it drops the event (logs a readable fallback) and returns without throwing, so the CLI exits cleanly

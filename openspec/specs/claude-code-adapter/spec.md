## Purpose

Define how `ClaudeCodeAdapter` normalizes Claude Code native hook events into `BridgeEnvelope` content for the VibePet bridge.

## Requirements

### Requirement: Claude Code Stop event normalizes to completion

`ClaudeCodeAdapter` SHALL conform to `ToolAdapter` with `tool == .claudeCode` and SHALL normalize a Claude Code `Stop` event into `.completion` content. It SHALL prefer a summary / transcript excerpt from the event payload for `markdownSummary`; when the sample carries no displayable summary it SHALL generate a readable fallback rather than assuming the event always carries Markdown.

#### Scenario: Stop with summary becomes completion

- **WHEN** `parseEvent` is given a `Stop` event whose payload contains a summary or transcript excerpt
- **THEN** it returns a `BridgeEnvelope` with `.completion` whose `markdownSummary` is taken from that summary

#### Scenario: Stop without summary uses a readable fallback

- **WHEN** `parseEvent` is given a `Stop` event with no displayable summary
- **THEN** it returns `.completion` with a readable fallback `markdownSummary` rather than empty or raw content

### Requirement: Claude Code Notification event normalizes to status

`ClaudeCodeAdapter` SHALL normalize a Claude Code `Notification` event into `.status` content carrying a single line of `text`.

#### Scenario: Notification becomes single-line status

- **WHEN** `parseEvent` is given a `Notification` event
- **THEN** it returns a `BridgeEnvelope` with `.status` whose `text` is a single line derived from the notification message

### Requirement: SourceInfo populated from event context

`ClaudeCodeAdapter` SHALL populate `SourceInfo` with `tool == .claudeCode`, the project name from the working directory basename when available, and a session short id derived from the event/session identifier when available.

#### Scenario: Source carries tool and project context

- **WHEN** `parseEvent` normalizes an event whose context provides a working directory and session id
- **THEN** the resulting envelope's `SourceInfo` has `tool == .claudeCode`, `projectName` set to the cwd basename, and `sessionShortId` derived from the session identifier

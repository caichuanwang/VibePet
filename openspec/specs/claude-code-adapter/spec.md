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

### Requirement: Claude Code PreToolUse normalizes to approval

`ClaudeCodeAdapter` SHALL normalize a Claude Code `PreToolUse` event whose `tool_name` is not `AskUserQuestion` into `.approval` content, assembling an `ActionPreview` from `tool_input` by tool: `Bash` → `.command`, `Edit` / `Write` → `.fileChange`, `Read` → `.fileRead`, `WebFetch` → `.network`, and any other tool → `.generic`. It SHALL populate the approval's `alwaysAllow` from `tool_name` only when the allowAlways mechanism is verified supported (see "allowAlways support gated by schema verification"); otherwise `alwaysAllow` SHALL be `nil`.

#### Scenario: Bash PreToolUse becomes command approval

- **WHEN** `parseEvent` is given a `PreToolUse` event with `tool_name == "Bash"`
- **THEN** it returns `.approval` whose `ActionPreview` is a `.command` built from the `tool_input` command

#### Scenario: Edit and Write PreToolUse become file-change approval

- **WHEN** `parseEvent` is given a `PreToolUse` event with `tool_name` of `Edit` or `Write`
- **THEN** it returns `.approval` whose `ActionPreview` is a `.fileChange` built from the `tool_input` path/diff

#### Scenario: Read PreToolUse becomes file-read approval

- **WHEN** `parseEvent` is given a `PreToolUse` event with `tool_name == "Read"`
- **THEN** it returns `.approval` whose `ActionPreview` is a `.fileRead` built from the `tool_input` path

#### Scenario: WebFetch PreToolUse becomes network approval

- **WHEN** `parseEvent` is given a `PreToolUse` event with `tool_name == "WebFetch"`
- **THEN** it returns `.approval` whose `ActionPreview` is a `.network` built from the `tool_input` URL

#### Scenario: Unknown tool becomes generic approval

- **WHEN** `parseEvent` is given a `PreToolUse` event whose `tool_name` is not a recognized preview kind
- **THEN** it returns `.approval` whose `ActionPreview` is `.generic`

### Requirement: Approval decision encodes to Claude Code permission output

`ClaudeCodeAdapter.encodeResponse` SHALL encode approval decisions per Claude Code's hook output contract: `deny(reason:)` SHALL emit `{"hookSpecificOutput":{…,"permissionDecision":"deny","permissionDecisionReason":…}}`; `allowOnce` SHALL emit `permissionDecision:"allow"`; `defer` SHALL emit no JSON and `exit 0` (fail-open). The encoded bytes and exit semantics SHALL be unit-testable.

#### Scenario: Deny emits a deny decision with reason

- **WHEN** `encodeResponse` is given a `deny(reason:)` decision for a `PreToolUse` approval
- **THEN** it produces hook output with `permissionDecision:"deny"` carrying the reason

#### Scenario: Allow once emits an allow decision

- **WHEN** `encodeResponse` is given an `allowOnce` decision
- **THEN** it produces hook output with `permissionDecision:"allow"`

#### Scenario: Defer emits no JSON and exits zero

- **WHEN** `encodeResponse` is given a `defer` outcome
- **THEN** it produces no JSON output and the CLI exits `0`

### Requirement: allowAlways support gated by schema verification

The adapter's `allowAlways` handling SHALL be gated by a verified Claude Code persistent/session permission mechanism, validated against the current Claude Code version's documentation or a local hook fixture. When verification succeeds the adapter SHALL emit the persistent-allow output for `allowAlways(scopeHint:)` and populate `alwaysAllow`. When it cannot be verified the adapter SHALL omit `alwaysAllow` and SHALL NOT produce an allowAlways branch, and no other requirement may treat `allowAlways` as a hard dependency.

#### Scenario: Verified mechanism emits persistent allow

- **WHEN** the allowAlways mechanism is verified supported and `encodeResponse` is given `allowAlways(scopeHint:)`
- **THEN** it emits the persistent/session allow output consistent with the verified mechanism

#### Scenario: Unverified mechanism omits always-allow

- **WHEN** the allowAlways mechanism cannot be verified
- **THEN** `parseEvent` leaves `alwaysAllow` `nil` and `encodeResponse` produces no allowAlways branch

### Requirement: Claude Code AskUserQuestion normalizes to question

`ClaudeCodeAdapter` SHALL normalize a Claude Code `PreToolUse` event whose `tool_name` is `AskUserQuestion` into `.question` content, mapping each entry of `tool_input.questions` to a `QuestionItem` (`prompt` from `question`, `header` from `header` with a fallback derived from the question text, `multiSelect` defaulting to `false`) and each option to a `QuestionOption` (`label`, `detail` from `description`, `allowsFreeform == false`). It SHALL append one synthetic free-text option (`label "其他"`, `allowsFreeform == true`) to every question, mirroring the "Other" choice the CLIs add client-side. It SHALL populate `SourceInfo` the same way as other events. This mechanism is verified supported (M5-0 spike, Claude Code ≥ 2.1.85). When `tool_input.questions` is missing or yields no usable item, parsing SHALL return `nil` (fail-open).

#### Scenario: AskUserQuestion becomes question content

- **WHEN** `parseEvent` is given a `PreToolUse` event with `tool_name == "AskUserQuestion"`
- **THEN** it returns a `BridgeEnvelope` with `.question` whose `questions` map from `tool_input.questions` with `header`, `prompt`, `multiSelect`, and per-option `label` / `detail`

#### Scenario: Multi-select question preserves multiSelect

- **WHEN** `parseEvent` normalizes an `AskUserQuestion` whose question has `multiSelect: true`
- **THEN** the resulting `QuestionItem.multiSelect` is `true`

#### Scenario: Question content needs a response

- **WHEN** an `AskUserQuestion` event is normalized to `.question`
- **THEN** the content's `needsResponse` is `true`, so the CLI blocks for the answer and the App enters `decide`

### Requirement: Question answer encodes to updatedInput prefill

`ClaudeCodeAdapter.encodeResponse` SHALL encode a `.question(QuestionAnswer)` response as Claude Code hook output with `permissionDecision:"allow"` and an `updatedInput` carrying the questions plus the user's `answers` keyed by question text (translated from `QuestionAnswer`, which is keyed by `header`), so the tool proceeds without prompting natively. The rebuilt `updatedInput.questions` SHALL exclude the synthetic "其他" option so the tool's question schema is unchanged. When the answer carries no usable selection, or the response is `.defer`, it SHALL emit no JSON and `exit 0` (fail-open). The encoded bytes and exit semantics SHALL be unit-testable.

#### Scenario: Question answer emits allow with updatedInput

- **WHEN** `encodeResponse` is given a `.question(QuestionAnswer)` with at least one selection
- **THEN** it produces hook output with `permissionDecision:"allow"` and an `updatedInput` whose `answers` are keyed by question text and whose `questions` are preserved without the synthetic "其他" option

#### Scenario: Empty answer defers with no JSON

- **WHEN** `encodeResponse` is given a `.question` response with no usable selection, or a `.defer`
- **THEN** it produces no JSON output and the CLI exits `0`


## ADDED Requirements

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

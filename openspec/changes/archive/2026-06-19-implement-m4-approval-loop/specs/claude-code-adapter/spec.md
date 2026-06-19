## ADDED Requirements

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

## MODIFIED Requirements

### Requirement: Manifest-driven idempotent install

`VibePetSetup install` SHALL be idempotent and driven by the VibePet install manifest. It SHALL reconcile drift in VibePet-managed entries while preserving the first pristine backup and all unrelated user hooks/settings. Claude Code SHALL receive the existing managed lifecycle hook set. Codex SHALL receive managed `PermissionRequest`, `Stop`, `SessionStart`, and `UserPromptSubmit` entries with `--tool codex`; its shared feature key SHALL be enabled without migrating or deleting an already valid modern, legacy, or mixed user configuration. The manifest SHALL record the Codex feature state observed before first install, with missing legacy ownership decoded as unknown.

The native hook timeout, CLI read timeout, and App decision timeout MUST be ordered so the App fails open first, the CLI retains response margin, and the native tool remains the final backstop. The configured production budgets SHALL be 86,400/86,390/86,385 seconds for Claude Code and 3,600/3,590/3,585 seconds for Codex.

Managed command ownership SHALL require the stable helper path to be the exact first shell argument after shell-quote parsing. Paths containing apostrophes SHALL round-trip safely. Wrapper commands that merely mention the helper path and unrelated top-level JSON fields or matcher metadata SHALL remain user-owned and be preserved. Setup install/uninstall SHALL reject an unknown tool selector instead of interpreting it as `all`.

#### Scenario: Re-running install repairs managed drift

- **WHEN** a managed hook entry is missing from an otherwise installed current-version tool
- **THEN** install restores that entry, preserves user entries, and retains the first backup path

#### Scenario: Re-running a healthy install preserves bytes

- **WHEN** install runs for a tool whose binary, managed entries, feature state, and manifest already match the desired version
- **THEN** config and manifest bytes remain unchanged

#### Scenario: Original config is backed up before writing

- **WHEN** install first writes hook entries to an existing tool config
- **THEN** it writes a pristine backup before replacing config and records its path in the successful install manifest

#### Scenario: User's existing hooks are preserved

- **WHEN** a target hook key already contains user-authored entries
- **THEN** install retains those entries while reconciling only VibePet-managed entries

#### Scenario: Managed and user hooks share one matcher group

- **WHEN** a matcher group contains both a VibePet-managed command and a user-authored command
- **THEN** install and uninstall remove only the managed command and preserve the user command and matcher metadata

#### Scenario: Codex PostToolUse hook entry is not registered

- **WHEN** install runs for Codex
- **THEN** no managed `PostToolUse` entry is written or recorded in `writtenHooks`

#### Scenario: Legacy managed PostToolUse entries are removed

- **GIVEN** a previous VibePet install wrote a managed `PostToolUse` entry
- **WHEN** install or repair reconciles Codex config
- **THEN** the managed entry is removed while user-authored `PostToolUse` hooks remain

#### Scenario: New Claude lifecycle hook entries are registered and recorded

- **WHEN** install runs for Claude Code
- **THEN** `SessionStart`, `UserPromptSubmit`, `SubagentStart`, `SubagentStop`, `SessionEnd`, `StopFailure`, `PermissionDenied`, and `PreCompact` are written and recorded

#### Scenario: Existing valid Codex feature key is preserved

- **WHEN** modern, legacy, or mixed supported feature keys already enable hooks
- **THEN** install leaves those user-owned key/value lines unchanged

#### Scenario: Equivalent features table headers are preserved

- **WHEN** Codex config declares the features table with a trailing comment, quoted key, key whitespace, or CRLF line endings
- **THEN** install updates that semantic table and equivalent quoted feature keys without appending a duplicate, and preserves the original header

#### Scenario: Old manifest ownership is conservative

- **WHEN** a legacy manifest omits Codex feature ownership
- **THEN** it decodes as unknown and uninstall preserves the shared feature flag

#### Scenario: Explicit repair refreshes unknown ownership conservatively

- **WHEN** an installed legacy record has unknown ownership and the user explicitly repairs Codex hooks
- **THEN** repair records the currently observed valid feature state while ordinary install continues preserving unknown

#### Scenario: Hook command paths remain single-quoted

- **WHEN** either tool's managed command is written
- **THEN** the stable helper path is single-quoted for `/bin/sh -c`

#### Scenario: Wrapper command is not removed as managed

- **WHEN** a user wrapper command mentions the stable helper path but invokes another executable first
- **THEN** install, uninstall, and health checks preserve and classify that wrapper as user-owned

#### Scenario: Codex uninstall preserves unrelated root fields

- **WHEN** removing the final managed Codex hook leaves unrelated top-level fields in `hooks.json`
- **THEN** uninstall preserves those fields and removes the file only when the full root object is empty

#### Scenario: Unknown Setup tool selector is rejected

- **WHEN** Setup receives `install` or `uninstall` with an unrecognized tool selector
- **THEN** it prints usage, performs no configuration mutation, and does not fall back to installing or uninstalling both tools

## ADDED Requirements

### Requirement: Configuration mutation rejects malformed input

Install, repair, and uninstall MUST NOT replace unreadable or malformed Claude/Codex JSON or TOML with an empty template. Without adding a TOML dependency, Codex mutation SHALL perform a conservative full-file structural preflight for balanced strings/containers, duplicate ordinary tables, and supported feature values before writing either `hooks.json` or `config.toml`; uncertain input SHALL return a diagnostic error and preserve original bytes.

#### Scenario: Malformed TOML preserves both files

- **WHEN** Codex config contains an unclosed or misordered container, invalid string escape or Unicode scalar, duplicate/conflicting ordinary and array table identity, duplicate supported key, invalid supported feature value, a conflicting root/dotted `features` namespace, duplicate features table, or a conflicting `[[features]]` array-of-tables
- **THEN** install, repair, and uninstall fail before writing either file and preserve both config and hooks bytes

#### Scenario: Structurally uncertain hooks JSON is preserved

- **WHEN** `hooks` is not an object, an event value is not an array of groups, or a group's `hooks` value is not an array
- **THEN** install, repair, and uninstall reject the file as malformed and preserve its original bytes

### Requirement: Health diagnosis is read-only and complete

Health checks SHALL report missing/stale/non-executable/version-mismatched helper binaries, malformed config/manifest, manifest-to-config drift, missing managed hook keys, stale command paths, disabled Codex feature state, and coexistence with other hooks. Health checks MUST NOT create directories, repair, or rewrite files.

Health SHALL use the same JSON structural preflight as mutation. Structurally uncertain JSON SHALL be reported as non-repairable malformed configuration without deriving repairable missing-hook issues. A missing Codex `config.toml` for an installed integration SHALL be reported as disabled feature state.

#### Scenario: Health check leaves the filesystem unchanged

- **WHEN** health is requested for a missing or malformed installation
- **THEN** it returns issues without creating or modifying any managed path

### Requirement: Hook binary source resolution is authoritative

Source candidates SHALL be evaluated as explicit override, app/executable sibling or `Helpers`, then SwiftPM product. Candidates MUST be executable regular files. An invalid explicit override SHALL fail without fallback, the managed stable destination MUST NOT be selected as a source, and installation MUST reject source and destination resolving to the same path before deletion.

#### Scenario: Invalid override does not fall back

- **WHEN** `VIBEPET_HOOKS_BINARY` points to an invalid file while another candidate exists
- **THEN** both App and Setup report the override error and do not install the other candidate

#### Scenario: Stable destination cannot delete itself

- **WHEN** the only discovered helper is the managed destination or an injected source resolves to that destination
- **THEN** installation fails before removing or modifying the existing helper

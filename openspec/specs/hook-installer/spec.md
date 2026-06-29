# hook-installer Specification

## Purpose

Define `VibePetSetup` install/uninstall/status behavior: copying the hook binary to a stable path, manifest-driven idempotent installation, precise uninstall, per-tool status reporting, and Codex trust activation tracking.

## Requirements

### Requirement: Hook binary copied to a stable path decoupled from the app bundle

`VibePetSetup` SHALL copy `VibePetHooks` to `~/Library/Application Support/VibePet/bin/VibePetHooks` and write all tool-configuration `command` entries pointing at that stable copy, never at a path inside the `.app` bundle. On install/status it SHALL compare the installed binary version against the current one and re-copy only when the installed copy is behind.

#### Scenario: Tool config points at the stable copy

- **WHEN** `install` writes a hook entry for any tool
- **THEN** the entry's `command` references `~/Library/Application Support/VibePet/bin/VibePetHooks`, not a bundle-internal path

#### Scenario: Outdated binary is re-copied without rewriting config

- **WHEN** the installed `bin/VibePetHooks` version is behind the current one
- **THEN** install re-copies the binary and leaves the existing tool config untouched

### Requirement: Manifest-driven idempotent install

`VibePetSetup install` SHALL be idempotent and driven by `~/Library/Application Support/VibePet/install-manifest.json`. It SHALL detect existing tool config, present the files/binary/backup it will change for confirmation, back up the original config, copy/upgrade the binary, write the VibePet hook entries, and update the manifest recording per-tool `installed`, `settingsPath`, `writtenHooks`, `backupPath`, and `hookBinaryVersion`. If a target hook key already holds a user's non-VibePet entry, install SHALL append rather than overwrite. Tool-specific writes:
- **Claude Code**: `~/.claude/settings.json` (JSON) hook keys `PreToolUse` / `Stop` / `Notification` plus the lifecycle keys `SessionStart` / `UserPromptSubmit` / `SubagentStart` / `SubagentStop` / `SessionEnd` / `StopFailure` / `PermissionDenied` / `PreCompact`.
- **Codex** (open-vibe-island pattern): hook entries in `~/.codex/hooks.json` (JSON) for `PermissionRequest` + `Stop` + `SessionStart` + `UserPromptSubmit`, each marked `statusMessage: "Managed by VibePet"`; and `~/.codex/config.toml` gets only a `[features]` `hooks = true` flag toggled via line-based editing (never adding a root key after a table). The Codex hook command carries `--tool codex`.

Because 0.3 removes the App-side decision deadline, each tool's per-hook tool-side `timeout` is the sole fail-open backstop for an unanswered decision; it MUST stay large enough to give the user time to respond yet finite so an unanswered request eventually falls back to the tool's native flow.

#### Scenario: Re-running install is a no-op

- **WHEN** `install` runs for a tool already installed at the current binary version with all lifecycle hook entries present
- **THEN** it skips re-writing config and the manifest/config are unchanged

#### Scenario: Original config is backed up before writing

- **WHEN** `install` writes hook entries to an existing tool config
- **THEN** it first writes a backup and records its `backupPath` in the manifest

#### Scenario: User's existing hooks are preserved

- **WHEN** the target hook key already contains a user's non-VibePet entry
- **THEN** install appends the VibePet entry without overwriting the user's entry

#### Scenario: Codex PostToolUse hook entry is not registered

- **WHEN** `install` runs for Codex
- **THEN** no managed `PostToolUse` hook entry is written to `~/.codex/hooks.json` or recorded in the manifest's `writtenHooks`

#### Scenario: Legacy managed PostToolUse entries are removed

- **GIVEN** a previous VibePet install wrote a managed `PostToolUse` hook entry
- **WHEN** `install` or repair rewrites the tool config
- **THEN** the VibePet-managed `PostToolUse` entry is removed while user-authored `PostToolUse` hooks are preserved

#### Scenario: New Claude lifecycle hook entries are registered and recorded

- **WHEN** `install` runs for Claude Code
- **THEN** the lifecycle hook keys (`SessionStart`, `UserPromptSubmit`, `SubagentStart`, `SubagentStop`, `SessionEnd`, `StopFailure`, `PermissionDenied`, `PreCompact`) are written and recorded in the manifest's `writtenHooks`

#### Scenario: Hook command paths are single-quoted

- **WHEN** any hook `command` is written for either tool
- **THEN** the stable binary path is single-quoted so the embedded space survives `/bin/sh -c`

### Requirement: Precise manifest-driven uninstall

`VibePetSetup uninstall` SHALL read the manifest and remove only the entries it recorded in `writtenHooks`, preserving the user's other hooks, then remove `bin/VibePetHooks` and the manifest's per-tool record. It MUST NOT remove user-authored or non-VibePet entries.

#### Scenario: Uninstall removes only VibePet entries

- **WHEN** `uninstall` runs for a tool whose config also holds user hooks
- **THEN** only the manifest-recorded VibePet entries are removed and the user's hooks remain

### Requirement: Status reports per-tool installation and activation state

`VibePetSetup status` SHALL read the manifest, verify the binary version, and return for each tool one of: `notInstalled`, `installedNeedsTrust`, `enabled` (trusted/active), or `outdated` (binary behind). The result SHALL be consumable by both the CLI and the App settings page.

#### Scenario: Status distinguishes written-but-untrusted from enabled

- **WHEN** Codex config is written but not yet trusted
- **THEN** `status` reports `installedNeedsTrust` for Codex, not `enabled`

#### Scenario: Status flags an outdated binary

- **WHEN** the installed binary version is behind the current one
- **THEN** `status` reports `outdated` for the affected tool

### Requirement: Codex hook trust activation state

The manifest SHALL track Codex activation as one of `notInstalled` / `installedNeedsTrust` / `trustedActive`. After writing Codex config, install SHALL default to `installedNeedsTrust` and surface readable `/hooks` trust guidance. When VibePet first receives a real Codex hook event, the manifest (or runtime cache) SHALL be marked `trustedActive`. When trust cannot be determined automatically, the system SHALL NOT display "enabled". Claude Code, having no trust gate, SHALL be treated as active once written.

#### Scenario: Codex starts as needs-trust with guidance

- **WHEN** Codex config is freshly written by install
- **THEN** its activation state is `installedNeedsTrust` and `/hooks` trust guidance is provided

#### Scenario: Real Codex event activates trust

- **WHEN** VibePet receives its first real Codex hook event after install
- **THEN** the activation state transitions `installedNeedsTrust → trustedActive`

### Requirement: Missing tool is reported, not blocking

When a tool's configuration is not detected (no `~/.claude/` for Claude Code, no Codex config), install/status SHALL report a readable "not detected" result and allow the flow to continue; hook installation is not a prerequisite for pet companionship.

#### Scenario: Undetected tool yields a skippable hint

- **WHEN** no configuration is detected for a tool
- **THEN** the result is a readable "not detected" state that does not block the rest of the flow

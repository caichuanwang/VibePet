## MODIFIED Requirements

### Requirement: Manifest-driven idempotent install

`VibePetSetup install` SHALL be idempotent and driven by `~/Library/Application Support/VibePet/install-manifest.json`. It SHALL detect existing tool config, present the files/binary/backup it will change for confirmation, back up the original config, copy/upgrade the binary, write the VibePet hook entries, and update the manifest recording per-tool `installed`, `settingsPath`, `writtenHooks`, `backupPath`, and `hookBinaryVersion`. If a target hook key already holds a user's non-VibePet entry, install SHALL append rather than overwrite. Every written hook `command` SHALL single-quote the stable binary path (which contains a space and runs via `/bin/sh -c`). Tool-specific writes:
- **Claude Code**: `~/.claude/settings.json` (JSON) hook keys `PreToolUse` / `Stop` / `Notification` plus the lifecycle keys `SessionStart` / `UserPromptSubmit` / `PostToolUse` / `SubagentStart` / `SubagentStop` / `SessionEnd` / `StopFailure` / `PermissionDenied` / `PreCompact`. Each hook's tool-side `timeout` MUST exceed the VibePet decision deadline.
- **Codex** (open-vibe-island pattern): hook entries in `~/.codex/hooks.json` (JSON) for `PermissionRequest` + `Stop` plus the new `SessionStart` + `UserPromptSubmit`, each marked `statusMessage: "Managed by VibePet"`; and `~/.codex/config.toml` gets only a `[features]` `hooks = true` flag toggled via line-based editing (never adding a root key after a table). The Codex hook command carries `--tool codex`.

#### Scenario: Re-running install is a no-op

- **WHEN** `install` runs for a tool already installed at the current binary version with all lifecycle hook entries present
- **THEN** it skips re-writing config and the manifest/config are unchanged

#### Scenario: Original config is backed up before writing

- **WHEN** `install` writes hook entries to an existing tool config
- **THEN** it first writes a backup and records its `backupPath` in the manifest

#### Scenario: User's existing hooks are preserved

- **WHEN** the target hook key already contains a user's non-VibePet entry
- **THEN** install appends the VibePet entry without overwriting the user's entry

#### Scenario: New lifecycle hook entries are registered and recorded

- **WHEN** `install` runs for Claude Code
- **THEN** the new lifecycle hook keys (`SessionStart`, `UserPromptSubmit`, `PostToolUse`, `SubagentStart`, `SubagentStop`, `SessionEnd`, `StopFailure`, `PermissionDenied`, `PreCompact`) are written and recorded in the manifest's `writtenHooks`

#### Scenario: Hook command paths are single-quoted

- **WHEN** any hook `command` is written for either tool
- **THEN** the stable binary path is single-quoted so the embedded space survives `/bin/sh -c`

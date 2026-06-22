## Why

VibePet 0.1 is stateless: each hook event produces a one-shot bubble, so the pet cannot reflect a session's *continuing* state (running a tool / waiting for approval / waiting for an answer / completed / failed / idle) or aggregate multiple concurrent sessions. This is the "foundation block" of 0.2 — the shared dependency that the sprite-animation host (sub-project 2) and terminal jump-back (sub-project 3) both build on. It introduces a persistent multi-session source of truth and widens hook coverage to the full agent lifecycle, without regressing the existing blocking approval/question loop or fail-open behavior.

## What Changes

- Add a persistent, pure-function multi-session `SessionState` reducer in `VibePetCore` (`AgentSession`, `SessionPhase`, `AgentEvent` event vocabulary, `JumpTarget` data structure). Both bridge channels feed it: notification envelopes translate to `AgentEvent` → `apply`; decision envelopes drive `permissionRequested`/`questionAsked` on entry and `resolvePermission`/`answerQuestion` on user resolution.
- Make the App's pet activity and menu-bar counts **derived** from `SessionState` rather than from a single envelope. `BridgeServerHost`/`PetController` route through the reducer; the existing `requestId`-paired blocking round-trip and 20s fail-open are unchanged.
- Add stable cross-event session identity: extend `SourceInfo` with `sessionID` (adapters populate it) and an optional `jumpTarget`; keep `sessionShortId` for display.
- Widen hook lifecycle coverage:
  - **Claude Code** adapter: existing `PreToolUse`/`Stop`/`Notification` plus `SessionStart`, `UserPromptSubmit`, `PostToolUse`, `SubagentStart`, `SubagentStop`, `SessionEnd`, `StopFailure`, `PermissionDenied`, `PreCompact` → `AgentEvent`.
  - **Codex** adapter: add `SessionStart` and `UserPromptSubmit` (atop existing `PermissionRequest`/`Stop`) → `AgentEvent`.
  - Only `PreToolUse`(decision) / `PermissionRequest` stay on the blocking decision channel; all new events are fire-and-forget notifications.
- Register the new hook entries in the installer (Claude `settings.json`, Codex hooks), preserving idempotence, manifest recording, automatic backup, precise uninstall, and single-quoted hook command paths.
- Add a process-liveness fail-open sweep so "stuck-visible" sessions (when `SessionEnd` never arrives) are reaped.
- Surface multi-session aggregation in the menu bar: visible/active session count and "needs attention" (waiting for approval/answer) count.

## Capabilities

### New Capabilities
- `session-model`: pure `SessionState` reducer over `AgentEvent`, producing a deterministic `[sessionID: AgentSession]`; defines `AgentSession`, `SessionPhase`, the `AgentEvent` vocabulary, `JumpTarget`, decision-resolution transitions, process-liveness reaping, and the derived aggregates (active/attention counts, current pet activity).

### Modified Capabilities
- `bridge-protocol`: `SourceInfo` gains a stable `sessionID` and an optional `jumpTarget`; `sessionShortId` retained for display.
- `claude-code-adapter`: normalize the full set of Claude Code lifecycle hooks into `AgentEvent`s (in addition to existing envelope content) and populate `SourceInfo.sessionID`.
- `codex-adapter`: normalize Codex `SessionStart`/`UserPromptSubmit` into `AgentEvent`s and populate `SourceInfo.sessionID`.
- `hook-installer`: register the new Claude Code and Codex lifecycle hook entries idempotently, recorded in the manifest with precise uninstall and single-quoted command paths.
- `pet-controller`: drive pet activity and bubble presentation from the derived `SessionState` (decision entry/resolution updates session phase) instead of directly from each envelope, preserving the blocking round-trip and fail-open.
- `menu-bar`: display multi-session aggregate counts (visible/active sessions and needs-attention).

## Impact

- **Core (`VibePetCore`)**: new `Session/` module (`SessionState`, `AgentSession`, `AgentEvent`, `SessionPhase`, `JumpTarget`); `SourceInfo` field additions in `Bridge/`; `Adapters/` mapping expansion.
- **App (`VibePetApp`)**: `BridgeServerHost` feeds and resolves against `SessionState`; `PetController` derives activity; `StatusItemController` shows aggregate counts; periodic process-liveness sweep.
- **Installer (`VibePetSetup`)**: `ClaudeCodeConfigWriter` / `CodexConfigWriter` / `HookInstaller` / `InstallManifest` register new hook keys.
- **Tests**: reducer unit tests (event sequences → expected state), adapter parse tests per new hook (incl. malformed/fail-open), installer idempotence/manifest/uninstall/quoting tests. No real install smoke tests.
- **Constraints**: `VibePetCore` stays UI-independent (no AppKit/SwiftUI); local-first (no network/telemetry); fail-open red line preserved; open-vibe-island source may be consulted freely for architecture and implementation guidance. In-memory state only — no cross-restart persistence in this change.

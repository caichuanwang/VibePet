## Context

VibePet already has the sub-project 1 session model: `SourceInfo.jumpTarget`, `AgentSession.jumpTarget`, `AgentEvent.jumpTargetUpdated`, and a pure `SessionState` reducer exist as the storage path for jump targets. Today that data is only a placeholder; the app has no production path that reliably captures the originating terminal, refreshes stale terminal metadata, or uses the value to focus the user's terminal from a bubble.

The key signal is temporal: while a tool hook is executing, the hook process is still inside the agent's terminal session. For iTerm and Terminal.app, asking the front/focused terminal at that moment can capture the exact session/tab before the user changes focus. App-side polling later is useful as a safety net, but it cannot reconstruct that exact "I am here now" signal without ambiguity.

Constraints:
- `VibePetCore` must stay UI-independent and must not import AppKit or SwiftUI.
- Hook and bridge behavior must remain fail-open. App unreachability, malformed input, osascript failure, denied Automation permission, and timeouts must never block Claude Code or Codex native flows.
- The implementation remains local-first: no network generation, telemetry, remote pet gallery, or new dependency.
- open-vibe-island is the architecture reference, but this change deliberately cuts its broader terminal/IDE surface down to iTerm, Terminal.app, Ghostty, cmux, and VS Code.

## Goals / Non-Goals

**Goals:**
- Capture a `JumpTarget` during hook parsing for Claude Code and Codex events whenever terminal environment or focused-terminal lookup provides enough information.
- Precisely jump back to iTerm, Terminal.app, Ghostty, cmux, and VS Code when possible.
- Provide a best-effort fallback chain for unknown or partially identified terminals: activate the recognized app, open the cwd, or silently no-op in UI paths.
- Refresh Ghostty and Terminal.app jump targets from App-side polling without affecting session visibility or liveness.
- Make every bubble/card body support double-click jump-back while preserving existing buttons, countdowns, auto-dismiss, hover pause, and fail-open defer behavior.
- Keep all external side effects testable through injected closures.

**Non-Goals:**
- Support tmux, zellij, Warp, WezTerm, Kaku, JetBrains IDEs, Codex.app URL threads, or broad VS Code-family forks beyond the `code -r <cwd>` path.
- Use keyboard or Accessibility injection.
- Add network, telemetry, remote lookup, or terminal installation flows.
- Rework the session model beyond the `JumpTarget` fields and update path required for terminal jump-back.

## Decisions

### Capture precision at hook time

Hook adapters will build `JumpTarget` as part of `parseEvent(stdin:env:)`. They will infer the terminal app from environment first (`CMUX_*`, `TERM_PROGRAM`, `ITERM_SESSION_ID`, `LC_TERMINAL`, `GHOSTTY_RESOURCES_DIR`), populate cwd-derived workspace fields, capture tty through an injectable command runner, and call an injectable focused-terminal locator only for terminal/event combinations where the result is reliable.

Alternatives considered:
- **Only poll from the App every 2s**: rejected because iTerm's AppleScript session id is not available from environment and the focused session may have changed after the hook.
- **Never run osascript from hooks**: rejected because fail-open, bounded locators give precision without compromising native tool flow. Denied Automation permission simply degrades the target.

### Gate focused-terminal locators by terminal

iTerm and Terminal.app locators run for every recognized hook event. Ghostty runs only during safe interaction events (`sessionStart` / `userPromptSubmit` in the normalized hook vocabulary); other Ghostty hooks intentionally omit stale session id/title and allow the App resolver to fill them later. cmux and VS Code never run osascript: cmux uses `CMUX_SURFACE_ID`, and VS Code uses cwd.

Alternatives considered:
- **Run Ghostty lookup for every hook**: rejected because tool hooks can fire after the user changes the focused tab, making the front terminal unreliable.
- **Do no Ghostty hook lookup**: rejected because safe interaction hooks can capture an exact id with better precision than later polling.

### Keep App-side resolver narrow

`TerminalJumpTargetResolver` will run as a lightweight safety net over live sessions, returning session-id keyed `JumpTarget` updates for Ghostty and Terminal.app only. It fetches AppleScript snapshots with a 3s cap and matches Ghostty by `terminalSessionID -> cwd -> title`, Terminal.app by `terminalTTY -> title`. It does not touch iTerm, cmux, or VS Code because their precision comes from hook-time id/env/cwd.

Alternatives considered:
- **Port open-vibe-island resolver wholesale**: rejected because tmux, WezTerm/Kaku, Warp, and IDE probing are out of scope for VibePet 0.2 and would add risk and system surface.
- **Make resolver part of liveness monitoring**: rejected because jump-target precision must not affect whether sessions are visible or alive.

### Centralize jumping in TerminalJumpService

`TerminalJumpService.jump(to:)` will dispatch by normalized `terminalApp`:
- iTerm: AppleScript selects matching window/tab/session by session id first, then tty.
- Terminal.app: AppleScript selects matching tab by tty first, then title.
- Ghostty: AppleScript focuses matching terminal by session id first, then cwd/title.
- cmux: Unix socket JSON-RPC `surface.focus` using `terminalSessionID` as `CMUX_SURFACE_ID`.
- VS Code: run `code -r <cwd>`.

If the precise branch fails, the service tries app activation and cwd opening before throwing an unsupported-terminal error. UI callers catch and silence failures so double-click never interrupts the user.

Alternatives considered:
- **Embed jump logic in each card/view**: rejected because it would duplicate side effects and make tests harder.
- **Expose only a fire-and-forget UI closure**: rejected because the service needs unit-testable dispatch behavior and fallback ordering.

### Treat double-click as a card-body gesture

Bubble/card body views receive an optional jump action derived from `SourceInfo.jumpTarget`. The gesture applies to the background/body region, not action buttons or input controls. The terminal-approval downgrade form's "Handle in terminal" button attempts jump-back and then still resolves `.defer` so Codex/Claude can continue in the native terminal flow.

Alternatives considered:
- **Single-click jump-back**: rejected because single-click is already used for buttons, dismissal, and control interaction.
- **Jump only from terminal-approval cards**: rejected because status and completion bubbles are equally useful entry points back to the originating session.

## Risks / Trade-offs

- Automation permission prompts may appear when locators or jump actions first run -> locators and jump actions must treat denial as failure and degrade without surfacing modal app errors.
- Hook-time osascript could delay tool flow -> locators must be bounded, injectable, and fail-open; any failure returns a degraded target or nil.
- Terminal metadata can be stale after users move tabs or panes -> Ghostty and Terminal.app resolver refreshes live sessions every 2s without changing liveness.
- Matching by cwd/title can be ambiguous with multiple panes in one project -> prefer exact session id/tty before cwd/title and keep fallback best-effort.
- cmux socket paths vary -> resolve the known active socket locations and fall back to app/cwd activation when socket focus fails.
- Removing broader open-vibe-island terminal support could disappoint power users -> document unsupported terminals as fallback-only for this version rather than silently attempting fragile automation.
- VS Code CLI may not be installed as `code` -> failed CLI execution falls through to app activation/cwd fallback.

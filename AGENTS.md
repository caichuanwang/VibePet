# Repository Guidelines

## Project Structure & Module Organization

VibePet is a Swift Package targeting macOS 14 with Swift tools 6.0. Core reusable, UI-independent code lives in `VibePetCore/`, organized by concern: `Bridge/`, `Adapters/`, `Install/`, `Persistence/`, `Geometry/`, and `Pet/`. Executable targets are split into `VibePetApp/`, `VibePetHooks/`, and `VibePetSetup/`. Tests live under `Tests/` (`VibePetCoreTests/`, `VibePetAppTests/`, `VibePetSetupTests/`, `E2E/`); shared core helpers are under `Tests/VibePetCoreTests/Support/`. Long-lived product docs are in `docs/` (`VibePet-PRD.md`), current-version design in `docs/superpowers/specs/`, archived docs in `docs/archive/`; OpenSpec requirements and archived changes are in `openspec/`.

## where to 

## Build, Test, and Development Commands

- `swift build` builds all library and executable targets.
- `swift test` runs the `VibePetCoreTests` XCTest suite.
- `swift run VibePetApp` launches the app executable.
- `swift run VibePetSetup` runs local setup behavior.
- `swift run VibePetHooks` runs the hook bridge helper.

Use `swift package describe --type json` when you need to confirm target membership or products.

## Coding Style & Naming Conventions

Use idiomatic Swift with 4-space indentation, `UpperCamelCase` for types, and `lowerCamelCase` for properties, functions, and enum cases. Keep source files focused around one primary type or feature area. Public model types should remain explicit about protocol conformances such as `Codable`, `Equatable`, and `Sendable` when they cross package or bridge boundaries. No repository SwiftLint or SwiftFormat configuration is currently present, so rely on SwiftPM compilation and local consistency.

## Testing Guidelines

Tests use XCTest and should be added under the matching `Tests/` target (`VibePetCoreTests/`, `VibePetAppTests/`, `VibePetSetupTests/`, or `E2E/`) with filenames ending in `Tests.swift`. Follow the existing `test...` method naming pattern, for example `testApprovalContentRoundTrips`. Prefer deterministic fixtures (e.g. `Tests/Fixtures/claude/`) over ad hoc local files. Run `swift test` before submitting changes that affect core logic, bridge serialization, adapters, the installer, persistence, or fail-open paths. Verify installer/config-writer logic by unit tests only — never real install smoke tests, since writes hit the real `~/.codex` / `~/.claude` even with `$HOME` overridden. An intermittent SIGPIPE (signal 13) during a full `swift test` run is not a regression; re-run or use `--filter`.

## Commit & Pull Request Guidelines

Recent history uses short, imperative summaries, sometimes with conventional prefixes such as `feat:`. Keep the first line focused on intent. Include context in the body when behavior, architecture, or requirements change, and use project decision trailers where useful, especially `Constraint:`, `Rejected:`, `Tested:`, and `Not-tested:`. Pull requests should summarize the change, link related OpenSpec items or issues, list verification performed, and include screenshots or recordings for visible app changes.

## Security & Configuration Tips

Do not commit generated build output, private local paths, credentials, or personal fixture data. Keep `.build/` and local tool caches out of reviews. When changing bridge or hook behavior, document any new socket, file-system, or command-execution assumptions in code and tests.

## Reset / Initial State Cleanup

To return the app to a first-run state, remove only VibePet-owned state and hook entries:

- Stop the running app first so `bridge.sock` is not live.
- Run `swift run VibePetSetup uninstall all` when possible. It removes VibePet-managed Claude Code and Codex hook entries while preserving user hooks and config.
- Delete `~/Library/Application Support/VibePet/`. This removes `config.json`, `bridge.sock`, `install-manifest.json`, `backups/`, `bin/VibePetHooks`, and imported pets under `pets/`.
- Delete only shared pet assets that VibePet should forget from `${CODEX_HOME:-~/.codex}/pets/`; do not remove the whole `~/.codex` directory.
- If uninstall cannot run, manually remove only hook entries that reference `~/Library/Application Support/VibePet/bin/VibePetHooks` from `~/.claude/settings.json`, and only Codex hook groups marked `statusMessage: "Managed by VibePet"` or referencing that same binary from `~/.codex/hooks.json`.
- In `~/.codex/config.toml`, remove VibePet-managed `[features]` `hooks = true` / `codex_hooks = true` only when no other Codex hooks remain. Do not delete unrelated Codex settings.
- Do not delete `~/.claude/`, `~/.codex/`, terminal app state, or user-created pet packages unless the user explicitly asks for a destructive full wipe.

## Project-Specific Guardrails

- Keep `VibePetCore/` UI-independent. Do not import `AppKit` or `SwiftUI` there; UI belongs in `VibePetApp/`. System side effects needed by Core logic (osascript, etc.) must be exposed through injectable closures so unit tests don't touch the real system.
- Preserve fail-open behavior for hooks and bridge code. If the app is not running, the socket fails, input is malformed, or a timeout occurs, Claude Code and Codex must fall back to their native flow instead of hanging. This is a red line that must not regress in any version.
- Keep the project local-first. Do not add network generation, telemetry, or upload paths without an explicit product change and user authorization design.
- When changing `PetAssetStore`, bridge serialization, adapters, or the installer, run `swift test`.
- Hook installation must point tool configuration at a stable copy such as `~/Library/Application Support/VibePet/bin/VibePetHooks`, not a path inside the `.app` bundle. That stable path contains a space and runs via `/bin/sh -c`, so config writers must single-quote the hook command path.
- VibePet plans to ship on the **Mac App Store** with **one-time (buyout) pricing** — no subscription, no account/server (consistent with the local-first guardrail). Be aware this conflicts with App Store **sandboxing**: writing `~/.codex`/`~/.claude`, the Unix socket, and osascript terminal jump-back all live outside the sandbox. Distribution may require sandbox-exception entitlements / App Group container paths, or fall back to Developer ID notarized direct distribution. Do not silently break the stable-path / fail-open / local-first constraints to accommodate this; flag the tradeoff instead.

## Reference Project: open-vibe-island

A full clone of **open-vibe-island** (Octane0411/open-vibe-island) lives at `open-vibe-island/` in the repo root. VibePet is essentially "open-vibe-island's architecture + a desktop pet", so it is the primary architecture reference. **You may read its source freely** to align bridge/session/installer/terminal-jump design; reimplement in VibePet's own models and naming rather than copying verbatim. Do not build or test it as part of VibePet — it is a self-contained nested package (its own `Package.swift` + `.git`) that the root `swift build`/`swift test` does not include.

**Its shape mirrors VibePet 1:1** — single Swift package, four targets:

| open-vibe-island target | VibePet equivalent | Role |
|---|---|---|
| `OpenIslandCore` | `VibePetCore` | Models, Unix-socket bridge transport (NDJSON), hook installers, session reducer |
| `OpenIslandApp` | `VibePetApp` | SwiftUI/AppKit shell; `AppModel` is the central `@Observable` state owner |
| `OpenIslandHooks` | `VibePetHooks` | Lightweight hook CLI: stdin payload → socket → app; blocking stdout only on a `PreToolUse` deny |
| `OpenIslandSetup` | `VibePetSetup` | Installer CLI for tool config (`~/.codex`, `~/.claude`) |

**Core abstractions VibePet's 0.2 session model is drawn from** (`open-vibe-island/Sources/OpenIslandCore/`):
- `AgentSession.swift` — `SessionPhase` (exactly `running` / `waitingForApproval` / `waitingForAnswer` / `completed`, with `requiresAttention`), `AgentSession`, and `JumpTarget`.
- `AgentEvent.swift` — the `AgentEvent` enum (`sessionStarted` / `activityUpdated` / `permissionRequested` / `questionAsked` / `sessionCompleted` / `jumpTargetUpdated` / `actionableStateResolved`, plus per-agent metadata cases VibePet does not need).
- `SessionState.swift` — `SessionState.apply(_:)` pure reducer over `sessionsByID`, with derived counts (`runningCount`, `attentionCount`, `liveSessionCount`, …).
- `BridgeServer.swift` / `BridgeTransport.swift` — socket server + newline-delimited JSON envelope codec.

**Where to look, by VibePet sub-project:**
- Sub-project 1 (session model + hooks): the four Core files above, plus `ClaudeHooks.swift` / `CodexHooks.swift` (payload → event) and `*HookInstaller.swift` / `*HookInstallationManager.swift` (config writing). Design notes: `open-vibe-island/docs/architecture.md`, `docs/hooks.md`, `docs/session-state-refactor.md`.
- Sub-project 3 (terminal jump-back): `Sources/OpenIslandApp/TerminalJumpService.swift`, `TerminalJumpTargetResolver.swift`, `ForegroundTerminalSessionProbe.swift`.

**Scope caveats — do not copy breadth:** open-vibe-island supports ~10 agents and 15+ terminals/IDEs, a notch overlay UI, Sparkle auto-update, Apple Watch relay, and keystroke/AX injection. VibePet stays at the MVP surface (Claude Code + Codex), has no notch UI, and adds the Codex-spritesheet pet instead. Take the architecture and the precise-jump-at-hook-time insight; leave the extra agents, terminals, and UI surface out unless a VibePet spec asks for them.

# AGENTS.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

# 工作语言
你的第一工作语言是**简体中文**

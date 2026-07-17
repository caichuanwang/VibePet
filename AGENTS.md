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

## Reset / First Launch State Cleanup

To make VibePet behave like a fresh first launch, clear the app's persisted state and managed integration footprint:

- Quit VibePet first so `bridge.sock` and in-memory session state are gone.
- Run `swift run VibePetSetup uninstall all` when possible before deleting state. This removes VibePet-managed Claude Code and Codex hook entries while preserving user hooks and config.
- Delete the entire `~/Library/Application Support/VibePet/` directory. This resets onboarding (`hasCompletedOnboarding`), selected pet, pet position, decision timeout, imported pets, session socket, install manifest/backups, and the stable `bin/VibePetHooks` copy.
- On next launch, VibePet should recreate `~/Library/Application Support/VibePet/` from defaults and show onboarding as if no prior app state existed.
- If uninstall cannot run before the directory is deleted, manually remove only hook entries that reference `~/Library/Application Support/VibePet/bin/VibePetHooks` from `~/.claude/settings.json`, and only Codex hook groups marked `statusMessage: "Managed by VibePet"` or referencing that same binary from `~/.codex/hooks.json`.
- In `~/.codex/config.toml`, remove VibePet-managed `[features]` `hooks = true` / `codex_hooks = true` only when no other Codex hooks remain. Do not delete unrelated Codex settings.
- `${CODEX_HOME:-~/.codex}/pets/` is an external shared Codex pet library, not VibePet app state. Leave it alone for a normal app reset; move or delete specific pet folders there only when the goal is for VibePet to discover no shared pets on first launch.
- Do not delete `~/.claude/`, `~/.codex/`, terminal app state, or user-created pet packages unless the user explicitly asks for a destructive full wipe beyond resetting VibePet.

## Project-Specific Guardrails

- Keep `VibePetCore/` UI-independent. Do not import `AppKit` or `SwiftUI` there; UI belongs in `VibePetApp/`. System side effects needed by Core logic (osascript, etc.) must be exposed through injectable closures so unit tests don't touch the real system.
- Preserve fail-open behavior for hooks and bridge code. If the app is not running, the socket fails, input is malformed, or a timeout occurs, Claude Code and Codex must fall back to their native flow instead of hanging. This is a red line that must not regress in any version.
- Keep the project local-first. VibePet is a Codex pet host: do not add network generation, telemetry, upload paths, or in-app pet gallery installs without an explicit product change and user authorization design.
- When changing `SpriteSheetAnimator`, `PetAssetStore`, bridge serialization, adapters, or the installer, run `swift test`.
- Hook installation must point tool configuration at a stable copy such as `~/Library/Application Support/VibePet/bin/VibePetHooks`, not a path inside the `.app` bundle. That stable path contains a space and runs via `/bin/sh -c`, so config writers must single-quote the hook command path.
- VibePet is a **GPL-3.0 open-source project** and currently does not use buyout, subscription, or in-app-purchase pricing. Source builds and project releases are the primary distribution paths; the Mac App Store is not a committed channel. If App Store distribution is considered later, flag the sandbox conflict with writes to `~/.codex`/`~/.claude`, the Unix socket, and osascript terminal jump-back rather than silently breaking the stable-path, fail-open, or local-first constraints.

## Reference Project: open-vibe-island

The primary upstream architecture reference is **[Octane0411/open-vibe-island](https://github.com/Octane0411/open-vibe-island)**. A full clone lives at `open-vibe-island/` in the repository root, so use the local clone for source-level investigation and the GitHub URL for upstream history or newer changes. VibePet is broadly "open-vibe-island's agent-session architecture + a desktop pet," and agents may freely study its source, tests, documentation, data flow, naming, and edge-case handling.

Adapt ideas into VibePet's own models, supported agents, product scope, and naming. Do not paste large unchanged blocks, import entire subsystems, or build/test the nested package as part of VibePet; `open-vibe-island/` is a self-contained Swift package with its own `Package.swift` and `.git`.

**Target correspondence:**

| open-vibe-island target | VibePet equivalent | Role |
|---|---|---|
| `OpenIslandCore` | `VibePetCore` | Models, event reduction, Unix-socket bridge transport, hook adapters, and installers |
| `OpenIslandApp` | `VibePetApp` | SwiftUI/AppKit shell with a central observable application-state owner |
| `OpenIslandHooks` | `VibePetHooks` | Lightweight hook CLI: stdin payload → socket → app, with blocking stdout only when the native tool requires a decision |
| `OpenIslandSetup` | `VibePetSetup` | Installer CLI for managed Claude Code and Codex configuration |

**Portable ideas worth adapting:**

- **Strict target boundaries:** keep models, codecs, reducers, persistence contracts, and installer logic UI-independent in Core; keep AppKit/SwiftUI and terminal automation in the app target; keep the hook executable small and fail-open.
- **Normalized event model and pure reducer:** translate Claude Code and Codex payloads into a small shared `AgentEvent` vocabulary, then update `sessionsByID` through a deterministic `SessionState.apply(_:)`. Derive running/attention/live counts from state instead of maintaining duplicate counters.
- **Explicit session phases and actionable payloads:** model running, approval, question, and completed states directly, with permission/question data attached to the session and cleared by an explicit resolution event. Preserve per-agent metadata only where VibePet actually needs it.
- **NDJSON Unix-socket bridge:** reuse the envelope/command/response separation, newline-delimited framing, stale-socket handling, restricted socket permissions, bounded reads, SIGPIPE protection, and request-specific timeouts. Every decode, connect, timeout, and malformed-input failure must remain fail-open.
- **Thin hook adapters:** keep each adapter responsible only for decoding its native payload, enriching runtime context, mapping it to shared events, and serializing the one response shape the tool expects. Unknown hook events should be ignored safely rather than becoming fatal.
- **Non-destructive, idempotent installation:** merge only VibePet-managed hook entries, preserve unrelated user configuration, maintain enough manifest/backup information for uninstall, quote the stable helper path correctly, and verify install/uninstall behavior with temporary-file unit tests rather than touching real user config.
- **Capture precise jump context early:** record terminal app, session/tab identifier, TTY, pane title, working directory, and process context at hook time when available. Separate target resolution from the actual jump service, prefer precise identifiers before heuristics, and retain a safe app/cwd fallback.
- **Central app state with isolated effects:** use the app model as the single observable owner of session and UI-facing state, while keeping bridge callbacks, persistence, terminal probing, and other side effects behind focused services or injectable closures.
- **Lifecycle reconciliation without flicker:** distinguish hook-managed lifecycle from process-discovered liveness, tolerate short observation gaps, clean up pending/actionable state on completion, and make late or duplicate events idempotent.
- **Deterministic test strategy:** adapt fixture-based payload tests, reducer transition tables, bridge codec/round-trip tests, timeout and app-not-running fail-open tests, installer merge/uninstall tests, and terminal-jump tests with injected system runners. Prefer regression tests for malformed input, stale sockets, duplicate events, and user-config preservation.


**Useful source entry points:**

- Session model: `open-vibe-island/Sources/OpenIslandCore/AgentSession.swift`, `AgentEvent.swift`, and `SessionState.swift`.
- Bridge transport: `open-vibe-island/Sources/OpenIslandCore/BridgeServer.swift` and `BridgeTransport.swift`.
- Hook translation and installation: `ClaudeHooks.swift`, `CodexHooks.swift`, `*HookInstaller.swift`, and `*HookInstallationManager.swift`.
- Hook CLI behavior: `open-vibe-island/Sources/OpenIslandHooks/OpenIslandHooksCLI.swift`.
- Terminal jump-back: `open-vibe-island/Sources/OpenIslandApp/TerminalJumpService.swift`, `TerminalJumpTargetResolver.swift`, and `ForegroundTerminalSessionProbe.swift`.
- Design notes and tests: `open-vibe-island/docs/architecture.md`, `docs/hooks.md`, `docs/session-state-refactor.md`, and the matching suites under `open-vibe-island/Tests/`.

**Scope caveats — adapt, do not clone wholesale:** open-vibe-island supports many agents and terminals/IDEs plus a notch overlay, Sparkle updates, Apple Watch relay, process-discovery machinery, keystroke/Accessibility injection, and other surfaces outside VibePet's current scope. VibePet stays focused on Claude Code + Codex, a desktop pet, local-only operation, and the integrations explicitly required by current specs. Do not add extra agents, network services, notch UI, updater/watch features, broad process scanning, or AX/keystroke automation merely because the reference implements them. Preserve VibePet's stable helper path, fail-open behavior, local-first privacy boundary, and spritesheet-pet architecture.

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

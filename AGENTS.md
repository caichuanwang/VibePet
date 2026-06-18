# Repository Guidelines

## Project Structure & Module Organization

VibePet is a Swift Package targeting macOS 14 with Swift tools 6.0. Core reusable code lives in `VibePetCore/`, organized by concern: `Bridge/`, `Generation/`, `Persistence/`, and `Adapters/`. Executable targets are split into `VibePetApp/`, `VibePetHooks/`, `VibePetSetup/`, and `Tools/CutoutBenchmark/Sources/CutoutBenchmark/`. Tests live in `Tests/VibePetCoreTests/`; shared test helpers are under `Tests/VibePetCoreTests/Support/`, and image fixtures are under `Tests/Fixtures/photos/`. Product and design notes are in `docs/`; OpenSpec requirements and archived changes are in `openspec/`.

## Build, Test, and Development Commands

- `swift build` builds all library and executable targets.
- `swift test` runs the `VibePetCoreTests` XCTest suite.
- `swift run VibePetApp` launches the app executable.
- `swift run VibePetSetup` runs local setup behavior.
- `swift run VibePetHooks` runs the hook bridge helper.
- `swift run CutoutBenchmark` runs the cutout benchmark tool.

Use `swift package describe --type json` when you need to confirm target membership or products.

## Coding Style & Naming Conventions

Use idiomatic Swift with 4-space indentation, `UpperCamelCase` for types, and `lowerCamelCase` for properties, functions, and enum cases. Keep source files focused around one primary type or feature area. Public model types should remain explicit about protocol conformances such as `Codable`, `Equatable`, and `Sendable` when they cross package or bridge boundaries. No repository SwiftLint or SwiftFormat configuration is currently present, so rely on SwiftPM compilation and local consistency.

## Testing Guidelines

Tests use XCTest and should be added under `Tests/VibePetCoreTests/` with filenames ending in `Tests.swift`. Follow the existing `test...` method naming pattern, for example `testApprovalContentRoundTrips`. Prefer deterministic fixtures from `Tests/Fixtures/photos/` over ad hoc local files. Run `swift test` before submitting changes that affect core logic, bridge serialization, generation, persistence, or adapters.

## Commit & Pull Request Guidelines

Recent history uses short, imperative summaries, sometimes with conventional prefixes such as `feat:`. Keep the first line focused on intent. Include context in the body when behavior, architecture, or requirements change, and use project decision trailers where useful, especially `Constraint:`, `Rejected:`, `Tested:`, and `Not-tested:`. Pull requests should summarize the change, link related OpenSpec items or issues, list verification performed, and include screenshots or recordings for visible app changes.

## Security & Configuration Tips

Do not commit generated build output, private local paths, credentials, or personal fixture data. Keep `.build/` and local tool caches out of reviews. When changing bridge or hook behavior, document any new socket, file-system, or command-execution assumptions in code and tests.

## Project-Specific Guardrails

- Keep `VibePetCore/` UI-independent. Do not import `AppKit` or `SwiftUI` there; UI belongs in `VibePetApp/`.
- Preserve fail-open behavior for hooks and bridge code. If the app is not running, the socket fails, input is malformed, or a timeout occurs, Claude Code and Codex must fall back to their native flow instead of hanging.
- Keep photo generation local-first. Do not add network generation, telemetry, or photo upload paths without an explicit product change and user authorization design.
- When changing `LocalCutoutGenerator`, image post-processing, or `PetAssetStore`, run `swift test` and `swift run CutoutBenchmark`.
- Hook installation must point tool configuration at a stable copy such as `~/Library/Application Support/VibePet/bin/VibePetHooks`, not a path inside the `.app` bundle.

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

## Why

VibePet's local Claude Code and Codex integration already works end to end, but several transport, lifecycle, installer, adapter, and terminal-target edge cases can still leave tools blocked, orphan actionable UI, mutate user-owned configuration, or jump to an ambiguous terminal. The local `open-vibe-island` baseline contains proven behavior and tests that can close these gaps without importing its broader product scope.

## What Changes

- Bound every NDJSON frame and transport phase with monotonic deadlines, preserve the one-connection/one-request protocol, validate response request IDs, and cancel request-scoped decisions when the peer disconnects.
- Reintroduce a tool-specific App decision deadline below the CLI and native hook timeouts so unanswered decisions fail open and clear all pending UI/state.
- Make session reduction idempotent for duplicate, stale, late, turn-completion, native-session-end, liveness, discovery, and metadata-enrichment events while keeping one App-side canonical writer.
- Harden Claude Code and Codex parsing/encoding only for schema facts supported by fixtures or the pinned upstream tests, including bounded transcript reads and UI-only question choices.
- Preserve user-owned Codex feature keys and hook entries, record conservative feature ownership in the manifest, reject malformed configuration, improve read-only drift diagnostics, and make explicit binary overrides authoritative.
- Prefer exact terminal identifiers and TTYs; allow cwd/title fallbacks only when unique, and preserve the existing target on ambiguity or runner failure.
- Keep the change local-only and limited to Claude Code, Codex, and the already supported terminal surfaces. No network, telemetry, Accessibility, keystroke injection, updater, Watch, or additional Agent support is added.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `bridge-transport`: Add bounded frames, absolute read deadlines, safe socket identity cleanup, peer cancellation, and response identity validation.
- `hook-cli`: Use tool-specific absolute decision budgets and preserve empty-stdout, exit-zero fail-open behavior for every transport failure.
- `pet-controller`: Expire or cancel request-scoped decisions exactly once and clear their actionable state without blocking other requests.
- `session-model`: Define duplicate, stale, late, session-end, liveness, discovery merge, and metadata enrichment semantics.
- `claude-code-adapter`: Bound transcript fallback and keep parsing/response behavior aligned with verified native schemas.
- `codex-adapter`: Limit identity and response behavior to fixture-backed fields, fail open on unknown payloads, and avoid inventing input or persistent-allow capability.
- `hook-installer`: Preserve shared feature ownership and mixed valid keys, reject malformed configuration, report drift read-only, and honor explicit binary overrides.
- `terminal-jumpback`: Enforce exact identifier/TTY priority and unique-only weak matching without expanding the supported terminal set.

## Impact

Affected code is confined to `VibePetCore` bridge/session/adapter/install modules, the thin hook and setup executables, `BridgeServerHost`, `PetController`, the terminal resolver/capture path, and their existing SwiftPM test targets. Public bridge framing remains NDJSON and public persisted models remain backward compatible. No dependency, network, entitlement, or real-user-config test changes are introduced.

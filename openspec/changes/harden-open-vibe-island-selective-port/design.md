## Context

VibePet is a local macOS Swift package whose Claude Code and Codex hooks exchange one NDJSON request per Unix-socket connection. `BridgeServerHost` owns the App's canonical `SessionState`, while `PetController` owns request continuations and the FIFO interaction surface. Hook installation uses a shared stable helper plus one manifest; terminal capture is best-effort and must never become a blocking prerequisite.

The pinned comparison points are VibePet `722989d3dc24ae5b490e5273651e66d46258db59` and local `open-vibe-island` `1e26dfc8d42bec0da7627986d49c2320b2593610`. The upstream project is an implementation reference, not the product source of truth.

## Goals / Non-Goals

**Goals:**

- Make every bridge and decision failure bounded and fail-open.
- Make session transitions deterministic and safe to publish once to every App consumer.
- Preserve user configuration and diagnose drift without writing during health checks.
- Improve terminal targeting only when captured or observed evidence is precise and unambiguous.
- Keep all changes fixture-backed, local-only, and compatible with existing public/persisted models.

**Non-Goals:**

- Persistent/multiplex socket connections, a new wire format, or a generic event bus.
- A second session store, process coordinator, or decision continuation inside `SessionState`.
- New Agents, terminals, network services, telemetry, Accessibility, keystroke injection, updater, or Watch/mobile features.
- Real install/uninstall smoke tests against the user's home directory.

## Decisions

### 1. Port behavior and tests, not upstream subsystems

Each gap is proven against VibePet first. Existing equivalent behavior remains in place; only the missing boundary rule or algorithm is adapted. This avoids importing upstream's broader agent registry, process monitoring, network relays, and UI architecture.

Rejected: copying the upstream bridge, app model, or installation managers wholesale. Those types encode product scope VibePet explicitly does not support.

### 2. Preserve one request per connection and add absolute deadlines

Frames remain newline-delimited JSON with a 4 MiB maximum. Server request framing uses chunked reads and a monotonic two-second deadline measured from accept, including for the maximum valid socket frame. Clients reject oversized requests before connecting and use a monotonic absolute deadline for the complete write. Client decision reads use one monotonic absolute deadline for the entire response, in addition to the existing idle socket timeout. The response request ID must match the request.

Tool budgets are ordered as follows:

| Tool | Native hook timeout | CLI read | App decision |
| --- | ---: | ---: | ---: |
| Claude Code | 86,400s | 86,390s | 86,385s |
| Codex | 3,600s | 3,590s | 3,585s |

The App deadline is long enough for deliberate user action but remains below the CLI and native deadlines. Tests inject short proportional values; they never wait for production durations.

Rejected: a persistent multiplex client. VibePet's short-lived hook process already has an unambiguous one-request connection, so multiplex pairing adds state without solving a product need.

### 3. Propagate request-scoped cancellation to the App owner

`BridgeServer` monitors EOF/HUP or extra input after decoding a decision request. `BridgeServerHost` keeps the minimal request-to-session association needed to cancel the matching `PetController` continuation and resolve canonical actionable state. Native SessionEnd cancels every already-pending request for its session and records an App-lifetime identity tombstone, so a decision or lifecycle event that arrives after canonical invisible-session cleanup cannot recreate or present that session; precise jump metadata may still enrich an ended session before cleanup. Stop invalidates the generation, cancels initial and periodic liveness work, fails open every continuation, and clears request tracking. Async liveness samples are generation-checked before the first provider and after every suspension; sessions added or canonically changed since the sampled snapshot are protected from that sample's stale miss. A response or timeout can resume a request only once.

Rejected: storing continuations in `SessionState`. It would mix pure reduction with UI/transport effects and allow one long decision to block unrelated session events.

### 4. Keep `SessionState` pure and retain one canonical writer

`SessionState.apply` returns whether state truly changed. Duplicate session starts enrich only missing metadata; they never reset waiting, completed, or ended lifecycle state. Event timestamps and deterministic equal-time phase priority prevent stale downgrades, with explicit exceptions for terminal SessionEnd bits and metadata enrichment. Process discovery merges only on a unique exact claim and process absence is debounced.

The ownership audit keeps `BridgeServerHost` as the sole canonical writer. Pet, dashboard, and menu consumers receive immutable snapshots from one publish path, so no `AppSessionStore` is introduced.

### 5. Treat shared Codex feature keys as user-owned unless proven otherwise

Install records the pre-install feature state. Existing enabled modern, legacy, or mixed keys are preserved byte-for-byte; install only enables a key when neither supported key is already active. Uninstall disables feature keys only when the first-install receipt proves VibePet enabled them and no other hooks remain. Old manifests decode ownership as unknown and therefore preserve the shared feature.

Malformed or unreadable JSON/TOML is never replaced with an empty template. Hook JSON mutation and health checks share a full hooks-tree structure preflight, so uncertain shapes are non-repairable rather than entering a repair loop. Managed command ownership is the exact parsed first executable, preserving wrappers and shell-quoted apostrophe paths. Codex uninstall preserves unrelated root fields. Without adding a dependency or launching Codex, the TOML mutator performs a conservative full-file structural preflight (quoted strings, comments, arrays, inline tables, duplicate ordinary tables, and supported feature values) before touching either config file. Uncertain input is rejected.

Rejected: automatic key migration. The key may reflect the installed Codex generation and is not owned by VibePet.

### 6. Binary source resolution is authoritative and non-destructive

Source priority is explicit override, executable/app-bundle sibling or `Helpers`, then SwiftPM products. The managed stable destination is not a source candidate. An invalid explicit override is an error in both Setup and App; it never falls back. `BinaryInstaller` rejects a source equal to its destination before any removal.

### 7. Terminal capture records only attributable facts

iTerm and Terminal locators may enrich a target only when their result matches the process-derived TTY. Ghostty's frontmost terminal is not attributable to a background hook, so hook-time capture records terminal app, process TTY, cwd, and workspace only. The App resolver later fills a Ghostty identifier from exact existing ID or a unique cwd/title match. Terminal title fallback likewise requires bidirectional uniqueness. Snapshot or runner failure produces no update.

## Risks / Trade-offs

- [Very long production decision tasks can outlive App UI changes] -> Generation invalidation, request IDs, peer cancellation, and single-resume guards make stale completions harmless.
- [A conservative TOML preflight can reject an unusual valid construct] -> Fail without writing and surface a diagnostic; do not guess or normalize the user's file.
- [Four MiB byte-at-a-time reads amplify syscalls] -> The hard size/deadline bounds prevent unbounded work; chunked framing can be a separate performance change after behavior is stable.
- [Weak terminal metadata can collide] -> Require unique matches and preserve the original target on ambiguity.
- [Old manifests cannot prove feature ownership] -> Treat ownership as unknown and preserve feature flags until an explicit repair records a new receipt.

## Migration Plan

No public wire or persisted session migration is required. The manifest ownership field decodes missing values as `unknown`. Installation repair rewrites only VibePet-managed entries and records current ownership; uninstall remains conservative for legacy records. Rollback is the reverse of the milestone changes; existing optional/default decoding keeps older app data readable.

## Open Questions

- Foreground terminal probing remains deferred because no current product behavior requires it.
- Chunked frame reads are a follow-up performance option, not part of this correctness change.

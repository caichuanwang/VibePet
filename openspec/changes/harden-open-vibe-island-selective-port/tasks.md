## 1. Bridge And Decision Fail-Open

- [x] 1.1 Verify 4 MiB frame limits, partial/EOF compatibility, one-frame connections, and two-second server absolute framing deadlines with deterministic Core tests
- [x] 1.2 Protect stale socket cleanup with type, owner, device, and inode checks across startup, stop, error, and replacement-node paths
- [x] 1.3 Apply an absolute BridgeClient response deadline, validate response request IDs, and add a drip-response regression test
- [x] 1.4 Propagate peer disconnect and stop cancellation by request ID so PetController continuations and canonical actionable state clear exactly once
- [x] 1.5 Verify tool-specific native/CLI/App decision budgets and process-level empty-stdout exit-zero fail-open behavior

## 2. Session Lifecycle And Ownership

- [x] 2.1 Make duplicate and stale events idempotent, including later duplicate session starts that must preserve waiting/completed state
- [x] 2.2 Verify turn completion reopening, native SessionEnd terminal merging, jump metadata enrichment, liveness debounce, and ambiguous discovery behavior
- [x] 2.3 Audit SessionState instances and mutation sites; keep BridgeServerHost as the only canonical writer and verify unchanged sweeps do not publish
- [x] 2.4 Verify Pet, dashboard, and menu projections consume the same published state while decisions remain independently awaitable

## 3. Adapter Compatibility

- [x] 3.1 Bound Claude transcript fallback to local regular files, 4 MiB, and the final 2,000 lines
- [x] 3.2 Verify Claude approval/question native response JSON and strip UI-only free-form choices from updatedInput
- [x] 3.3 Limit Codex session fields and decisions to fixture-backed behavior, keep malformed/unknown payloads empty-output fail-open, and avoid unverified input capability

## 4. Installer, Health, And Binary Sources

- [x] 4.1 Preserve existing modern, legacy, and mixed Codex feature keys and record conservative backward-compatible ownership receipts
- [x] 4.2 Reject malformed Claude/Codex JSON and full-file TOML structure before writing either config file
- [x] 4.3 Verify read-only health drift coverage without touching default user paths
- [x] 4.4 Make explicit binary overrides authoritative in Setup and App, remove the managed destination from source candidates, and reject source-equals-destination before deletion

## 5. Terminal Jump Precision

- [x] 5.1 Record only attributable hook-time identifiers; do not combine Ghostty frontmost ID with another process TTY
- [x] 5.2 Require exact ID/TTY priority and bidirectional uniqueness for cwd/title fallback while preserving precise fields on ambiguity or runner failure
- [x] 5.3 Verify existing cmux and VS Code behavior remains unchanged and keep foreground probing deferred

## 6. Integration And Documentation

- [x] 6.1 Update the selective-port execution matrix with pinned commits, Done/No-op/Deferred decisions, and concrete test evidence
- [x] 6.2 Run scope audits for Core UI imports, networking/telemetry, extra Agents, AX/keystroke code, and dependency changes
- [x] 6.3 Run targeted suites, `swift build`, and full `swift test` with zero failures and no unexpected skips
- [x] 6.4 Perform final specification-compliance and code-quality reviews and resolve every blocking finding

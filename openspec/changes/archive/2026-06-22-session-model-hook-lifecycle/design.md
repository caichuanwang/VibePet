## Context

VibePet 0.1's bridge is stateless: each hook event yields one bubble, mechanism in `BridgeServerHost.decideStream`/`notifyStream` over a Unix socket with `requestId`-paired blocking and 20s fail-open. That cannot express continuing state (running / waiting / completed / failed / idle) or aggregate concurrent sessions — the prerequisite for the sprite host (sub-project 2) and terminal jump-back (sub-project 3).

This change adds an App-side persistent `SessionState` reducer as the single source of truth, fed by **both** existing channels, and widens hook coverage to the full agent lifecycle. The existing socket, `HookRuntime.runDecision/runNotification`, stream wiring, request pairing, and fail-open countdown are **not** changed in mechanism — only layered on top of.

Reference implementation is open-vibe-island; its source may be consulted freely for architecture and implementation guidance.

## Goals / Non-Goals

**Goals:**
- Deterministic, pure `SessionState.apply(_:)` reducer over a small `AgentEvent` vocabulary (unit-testable in Core, no UI).
- Both channels feed one source of truth; pet activity and menu-bar counts become *derived*, not per-envelope.
- Full Claude lifecycle hooks + Codex `SessionStart`/`UserPromptSubmit` parsed fail-open into `AgentEvent`s.
- Stable cross-event `sessionID` on `SourceInfo`; `JumpTarget` defined and passed through.
- Existing blocking approval/question loop + fail-open behavior unchanged; decision entry/resolution also moves session phase.
- Installer registers new hooks idempotently with manifest recording, backup, precise uninstall, single-quoted paths.

**Non-Goals:**
- Sprite rendering / Codex pet ingest / cutout removal (sub-project 2).
- Terminal jump-back UI and `JumpTarget` *resolution* (sub-project 3 — this change only defines the struct and threads it).
- Cross-restart persistence of session state (in-memory only here).
- Additional tools (Cursor/Gemini) beyond Claude Code + Codex.

## Decisions

**1. Stateful reducer as a Core value type, owned by an App actor.**
`SessionState` (pure `struct`, `Equatable`/`Sendable`) lives in `VibePetCore/Session/` so the reducer is unit-tested without UI. The App holds and mutates it behind the existing main-actor/`BridgeServerHost` boundary; no new concurrency model.
*Alternative rejected — lightweight stateless (map new hooks to one-shot bubbles):* cannot hold "running until PostToolUse" and gives no multi-session/jump-back base (design doc §9 "Rejected 轻量版 Y").

**2. Four converged phases, not one-per-hook.** The dozen lifecycle hooks mostly update summary/metadata; real phases converge to `running / waitingForApproval / waitingForAnswer / completed`. So only ~4 phases (and ~5 animation rows downstream). Keeps the reducer and `AgentEvent` table small.

**3. Both channels feed the reducer.** Notification envelopes → translate to `AgentEvent` → `apply`. Decision envelopes → `permissionRequested`/`questionAsked` on entry (phase → waiting) before blocking; user resolve → `resolvePermission`/`answerQuestion`; timeout/defer → `actionableStateResolved`. The wire mechanism and `requestId` pairing are untouched.

**4. Reducer invariants protect the decision loop.** `activityUpdated` must not downgrade a session that is `waitingForApproval/Answer` (concurrent events can't clear a pending decision); non-`sessionStarted` events for unknown sessions are ignored. These make concurrent event interleavings deterministic.

**5. Stable `sessionID` added to `SourceInfo`; `sessionShortId` kept for display.** Reducer needs a cross-event-stable key. Claude: payload `session_id`; Codex: session/thread id. Adapters populate it.

**6. Process-liveness sweep as fail-open backstop.** App periodically enumerates live agent processes; `markProcessLiveness` reaps sessions missing for 2 consecutive checks (→ ended/completed, dropped from visible). Covers a `SessionEnd` that never arrives (bridge cut, killed process) so the pet/menu-bar don't show "stuck-visible" sessions.

**7. Phased 1a → 1b.** 1a wires the reducer using the existing 4 event kinds; 1b fans out the remaining lifecycle hooks. Avoids a big-bang change.

## Risks / Trade-offs

- **`SessionEnd` never arrives → stuck-visible session** → process-liveness sweep reaps after N misses.
- **Concurrent events clobber a pending decision** → reducer invariant: `activityUpdated` never downgrades a waiting phase.
- **New hook payload shapes unknown / drift across tool versions** → pin with real-sample fixtures (spike); parse fail-open (drop on missing/unknown, never throw/block).
- **Codex new hooks may need user trust** → installer marks `installedNeedsTrust`; don't claim active until a real Codex event is seen; writes stay idempotent and don't assume exclusivity.
- **Tool hook timeout < VibePet countdown** → installer rejects/guards combinations where tool `timeout` ≤ decision deadline.
- **Liveness polling overhead** → bound poll period; enumeration cost is a spike item.

## Migration Plan

- Additive only: new `Session/` module, new `SourceInfo` fields (default-safe for existing decode), new adapter branches, new installer hook keys. No wire-format break (`version` stays 1; new fields are optional/additive).
- Re-running `install` registers the new hook entries idempotently and records them in the manifest; `uninstall` removes exactly those. No data migration (in-memory state only).
- Rollback: `uninstall` removes the added hook entries; reverting code drops the reducer layer — the existing stateless decision loop still functions because the mechanism was never changed.

## Open Questions

(Spike items to pin during implementation, per design doc §8 — resolve against real fixtures.)
- Exact stable `sessionID` field name/availability per tool (Claude `session_id`; Codex session vs thread id).
- Payload shapes for `SubagentStart/Stop`, `PreCompact`, `StopFailure`, and Codex `SessionStart` — fix via captured fixtures.
- Whether Claude `SessionStart` fires every turn and its ordering vs `UserPromptSubmit` (confirms when `running` is entered).
- Process-enumeration method and polling period/cost for the liveness sweep.

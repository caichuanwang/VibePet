## 1. Core session model (`VibePetCore/Session/`)

- [x] 1.1 Add `SessionPhase` enum (`running`/`waitingForApproval`/`waitingForAnswer`/`completed`, `Codable`/`Sendable`/`CaseIterable`) with `requiresAttention`; unit-test the two true / two false cases.
- [x] 1.2 Add `JumpTarget` struct (`terminalApp`, optional `workspaceName`/`paneTitle`/`workingDirectory`/`terminalTTY`/`codexThreadID`; `Equatable`/`Sendable`/`Codable`) with a Codable round-trip test.
- [x] 1.3 Add `AgentSession` (all fields incl. liveness + derived `isVisible`) with a Codable round-trip test and an `isVisible`-for-attention test.
- [x] 1.4 Add `AgentEvent` tagged sum type (7 cases, each carrying `sessionID` + `timestamp`; `sessionCompleted` carries `isError`/`isSessionEnd`).
- [x] 1.5 Implement `SessionState` with `sessionsByID` and `apply(_:)`; cover determinism, `sessionStarted` upsert preserving `firstSeenAt`, `activityUpdated` not downgrading a waiting session, and unknown-session non-start events ignored.
- [x] 1.6 Implement `sessionCompleted` handling (completed / `isError` / `isSessionEnd`) with tests.
- [x] 1.7 Implement `resolvePermission`, `answerQuestion`, and `actionableStateResolved` transitions with tests (approved→running, deny→completed, answer→running, resolve only affects waiting).
- [x] 1.8 Implement `markProcessLiveness` reaping (2 consecutive misses → ended/completed/non-visible; reset on re-seen) with tests.
- [x] 1.9 Implement derived aggregates (`visibleSessions`, `runningCount`, `attentionCount`, `activeActionableSession`) and pet-activity derivation (attention→deciding, started→greeting once, else idle) with tests.

## 2. Bridge protocol — stable session identity

- [x] 2.1 Extend `SourceInfo` with `sessionID: String` and optional `jumpTarget: JumpTarget?`; keep `sessionShortId`.
- [x] 2.2 Update `BridgeEnvelope` Codable round-trip test to assert `sessionID`/`jumpTarget` preservation and `sessionID` ≠ `sessionShortId` independence.

## 3. Adapters — full hook lifecycle → `AgentEvent`

- [x] 3.1 Capture real-sample fixtures under `Tests/Fixtures/claude/` for the new Claude hooks (`SessionStart`, `UserPromptSubmit`, `PostToolUse`, `SubagentStart`, `SubagentStop`, `SessionEnd`, `StopFailure`, `PermissionDenied`, `PreCompact`) and Codex `SessionStart`/`UserPromptSubmit` (spike: pin field names + `sessionID`).
- [x] 3.2 `ClaudeCodeAdapter`: populate `SourceInfo.sessionID` from `session_id`; test it.
- [x] 3.3 `ClaudeCodeAdapter`: map each lifecycle hook to the correct `AgentEvent` per spec; tests per event (incl. `StopFailure`→error, `SessionEnd`→session-end).
- [x] 3.4 `ClaudeCodeAdapter`: malformed/missing-field lifecycle payload fails open (drop + readable fallback, no throw); test.
- [x] 3.5 `CodexAdapter`: populate `SourceInfo.sessionID` from session/thread id across existing paths; test.
- [x] 3.6 `CodexAdapter`: map `SessionStart`→`sessionStarted`, `UserPromptSubmit`→`activityUpdated`; unknown/missing-id event returns `nil`; tests.

## 4. App wiring — reducer as source of truth

- [x] 4.1 Add the App-owned `SessionState` holder on the main actor; `BridgeServerHost` applies notification envelopes as `AgentEvent`s.
- [x] 4.2 Decision path: enter `permissionRequested`/`questionAsked` before blocking; on resolve call `resolvePermission`/`answerQuestion`; on timeout/dismiss reply `.defer` and apply `actionableStateResolved` — verify `requestId` pairing and fail-open unchanged.
- [x] 4.3 Drive `PetController` activity from derived `SessionState` (decide/greet/notify/idle) instead of per-envelope.
- [x] 4.4 Add the periodic process-liveness sweep that feeds `markProcessLiveness` (system enumeration behind an injectable closure so tests don't touch the real system).
- [x] 4.5 `StatusItemController`: show visible/active and needs-attention counts derived from `SessionState`; test the derivation.

## 5. Installer — register new hooks

- [x] 5.1 `ClaudeCodeConfigWriter`: register the new lifecycle hook keys idempotently, single-quoting the binary path; unit-test idempotence + quoting + manifest `writtenHooks` recording.
- [x] 5.2 `CodexConfigWriter`: register `SessionStart`/`UserPromptSubmit` (with `--tool codex`, `statusMessage: "Managed by VibePet"`) idempotently; unit-test.
- [x] 5.3 Verify precise uninstall removes exactly the new entries (manifest round-trip test) and guard that tool hook `timeout` exceeds the VibePet decision deadline. (Unit tests only — no real install smoke test.)

## 6. Regression & verification

- [x] 6.1 Confirm existing M4 approval / M5 question blocking round-trip and fail-open behavior is unchanged (regression tests green).
- [x] 6.2 Run `swift test` (re-run or `--filter` on intermittent SIGPIPE); update `docs/VibePet-PRD.md` §4 evolution markers (✨→🟢/🟡) for the landed `Session/` module + `SourceInfo` fields.

## 1. Core Data and Hook Capture

- [x] 1.1 Update `JumpTarget` in `VibePetCore` to include `terminalSessionID`, remove unsupported jump fields from the public initializer surface, and preserve decoding compatibility for omitted/legacy keys.
- [x] 1.2 Add Core terminal inference helpers for cmux, `TERM_PROGRAM`, iTerm fallback env, Ghostty fallback env, cwd-derived workspace name, and unknown-terminal fallback.
- [x] 1.3 Add injectable tty capture that tries `/usr/bin/tty`, falls back to `ps -p <ppid> -o tty=`, normalizes `/dev/...`, and fails open.
- [x] 1.4 Add injectable focused-terminal locator support for iTerm, Terminal.app, and gated Ghostty capture, with bounded execution and nil-on-failure behavior.
- [x] 1.5 Wire Claude Code and Codex adapters to attach best-effort `SourceInfo.jumpTarget` for recognized events without changing ignored-event or malformed-input behavior.
- [x] 1.6 Ensure `AgentEvent` creation and `SessionState.apply` preserve hook-captured jump targets and apply `jumpTargetUpdated` without phase/liveness side effects.

## 2. App Jump Resolution and Dispatch

- [x] 2.1 Implement `TerminalJumpService` in `VibePetApp` with injected open, AppleScript, process, and socket/IO runners.
- [x] 2.2 Add iTerm, Terminal.app, Ghostty, cmux, and VS Code dispatch paths with the exact matching priority from the specs.
- [x] 2.3 Add the fallback chain for recognized app activation, cwd opening, and unsupported-terminal errors while keeping UI callers silent.
- [x] 2.4 Implement `TerminalJumpTargetResolver` for Ghostty and Terminal.app snapshots, matching, corrected target generation, and empty-update fail-open behavior.
- [x] 2.5 Connect resolver output into the existing App/session monitoring path so corrected targets are applied through `jumpTargetUpdated` events without blocking bridge accepts.

## 3. Bubble and Card Interaction

- [x] 3.1 Extend `PetSurface`/`PetWindowSurface`/`PetController` presentation paths to pass a terminal jump action together with the existing `SourceInfo`.
- [x] 3.2 Add double-click jump-back to `SpeechBubble` body for status and completion content without disrupting hover pause, scrolling, dismissal, or auto-dismiss timers.
- [x] 3.3 Add double-click jump-back to `ApprovalCard` body while preserving Allow/Deny/Always-allow buttons, shortcuts, and countdown defer behavior.
- [x] 3.4 Update the terminal-approval "Handle in terminal" action to attempt jump-back when available and then resolve `.defer`.
- [x] 3.5 Add double-click jump-back to `QuestionCard` body while preserving option selection, freeform input, submit, shortcuts, and countdown defer behavior.

## 4. Verification

- [x] 4.1 Add unit tests for `JumpTarget` Codable compatibility, `SourceInfo.jumpTarget` round-trip, and ignored legacy jump keys.
- [x] 4.2 Add table-driven Core tests for terminal inference, cwd/workspace derivation, tty capture success/fallback/failure, and locator gate behavior.
- [x] 4.3 Add adapter tests proving Claude Code and Codex recognized events attach jump targets when env/locator data exists and still fail open when capture fails.
- [x] 4.4 Add `SessionState` tests for `jumpTargetUpdated` replacing only the target and preserving phase/liveness.
- [x] 4.5 Add App tests for `TerminalJumpService` dispatch and fallback ordering using injected side-effect recorders.
- [x] 4.6 Add App tests for `TerminalJumpTargetResolver` Ghostty/Terminal matching, unsupported-terminal skip behavior, and snapshot failure isolation.
- [x] 4.7 Add UI/controller tests proving status, completion, approval, terminal-approval, and question jump actions fire once and do not intercept existing controls.
- [x] 4.8 Run `swift test`; if a full run hits the known intermittent SIGPIPE, rerun the affected filter or full suite and record the result.
- [x] 4.9 Run `openspec validate "terminal-jumpback" --strict` before implementation handoff.

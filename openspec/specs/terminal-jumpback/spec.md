# terminal-jumpback Specification

## Purpose

Define terminal jump-back capture, correction, dispatch, fallback, and bubble/card interaction behavior.

## Requirements

### Requirement: Hook-time jump target capture

The adapters SHALL build an initial `JumpTarget` during `parseEvent(stdin:env:)` when terminal environment, cwd, tty, or a focused-terminal locator provides usable information. Terminal app inference SHALL prefer cmux environment first, then `TERM_PROGRAM`, then iTerm/Ghostty fallback environment, and SHALL otherwise use `"Unknown"`. The hook-time locator MUST be bounded, injected for tests, and fail-open: osascript failure, permission denial, timeout, or malformed output SHALL return no precise locator without throwing out of normal event parsing.

#### Scenario: iTerm and Terminal locators run for recognized hooks

- **WHEN** a recognized hook event is parsed from an iTerm or Terminal.app environment and the injected locator returns a precise session/tab snapshot
- **THEN** the envelope source carries a `JumpTarget` with the inferred terminal app, cwd-derived workspace fields, and the locator's session id, tty, or pane title values

#### Scenario: Ghostty locator is gated to safe hook events

- **WHEN** a Ghostty event is parsed for `sessionStart` or `userPromptSubmit`
- **THEN** the Ghostty locator is allowed to populate `terminalSessionID` and `paneTitle`

#### Scenario: Ghostty tool hooks do not reuse stale focus

- **WHEN** a Ghostty tool-class event is parsed after the safe hook window
- **THEN** the jump target preserves cwd-derived fields but omits precise session id/title values that could describe the wrong focused tab

#### Scenario: cmux and VS Code skip osascript locators

- **WHEN** a cmux or VS Code environment is parsed
- **THEN** no focused-terminal locator is invoked, cmux uses `CMUX_SURFACE_ID` as `terminalSessionID` when present, and VS Code relies on cwd

#### Scenario: Locator failure degrades without blocking hook parsing

- **WHEN** the injected locator fails, times out, or returns malformed output
- **THEN** parsing still returns the same normalized envelope shape with a degraded or nil `JumpTarget` and does not throw solely because terminal precision failed

### Requirement: App-side jump target resolver

`VibePetApp` SHALL provide a `TerminalJumpTargetResolver` that refreshes jump targets for live sessions without affecting session visibility, attachment, or liveness. The resolver SHALL inspect only Ghostty and Terminal.app sessions, fetch AppleScript snapshots with a bounded timeout, match Ghostty by `terminalSessionID`, then cwd, then title, and match Terminal.app by tty, then title. It SHALL return session-id keyed corrected `JumpTarget` values for changed targets only.

#### Scenario: Ghostty session is corrected from a snapshot

- **WHEN** a live Ghostty session has a jump target missing or stale session metadata and a snapshot matches by session id, cwd, or title
- **THEN** the resolver returns an updated `JumpTarget` containing the snapshot's session id, working directory, title, and workspace name

#### Scenario: Terminal tab is corrected from a snapshot

- **WHEN** a live Terminal.app session has a jump target with a tty or title that matches a Terminal snapshot
- **THEN** the resolver returns an updated `JumpTarget` containing the matched tty, title, and existing cwd-derived workspace fields

#### Scenario: Unsupported terminals are skipped by the resolver

- **WHEN** live sessions are for iTerm, cmux, VS Code, or an unknown terminal
- **THEN** the resolver does not query or return updates for those sessions

#### Scenario: Resolver failure is isolated from session liveness

- **WHEN** AppleScript snapshot fetching fails or times out
- **THEN** the resolver returns no updates and does not mark any session completed, detached, invisible, or errored

### Requirement: Terminal jump service dispatch

`VibePetApp` SHALL provide a `TerminalJumpService` that accepts a `JumpTarget` and dispatches through injected side-effect closures. It SHALL support iTerm AppleScript selection by session id then tty, Terminal.app AppleScript selection by tty then title, Ghostty AppleScript focus by session id then cwd/title, cmux Unix-socket JSON-RPC `surface.focus` by `terminalSessionID`, and VS Code CLI `code -r <cwd>`.

#### Scenario: iTerm jump uses precise session lookup first

- **WHEN** a target has `terminalApp == "iTerm"` and a non-empty `terminalSessionID`
- **THEN** the service invokes the iTerm AppleScript path that searches sessions by id before falling back to tty matching

#### Scenario: Terminal jump uses tty matching first

- **WHEN** a target has `terminalApp == "Terminal"` and a non-empty `terminalTTY`
- **THEN** the service invokes the Terminal.app AppleScript path that searches tabs by tty before falling back to title matching

#### Scenario: Ghostty jump supports session and cwd matching

- **WHEN** a target has `terminalApp == "Ghostty"`
- **THEN** the service invokes the Ghostty AppleScript path using session id before cwd or title matching

#### Scenario: cmux jump focuses a surface through the socket

- **WHEN** a target has `terminalApp == "cmux"` and a non-empty `terminalSessionID`
- **THEN** the service sends a `surface.focus` request for that surface id to the resolved cmux socket and best-effort activates the cmux app

#### Scenario: VS Code jump opens the workspace

- **WHEN** a target has `terminalApp == "VS Code"` and a working directory
- **THEN** the service runs `code -r <cwd>` through the injected process runner

### Requirement: Jump fallback chain

If a precise terminal jump path cannot focus a target, `TerminalJumpService` SHALL degrade in order: activate the recognized app bundle when available, open the working directory when available, and finally throw an unsupported-terminal error to non-UI callers. UI callers SHALL catch and silence that error so jump-back never interrupts the user.

#### Scenario: Precise jump miss activates the app

- **WHEN** a target's terminal app is recognized but precise session matching fails
- **THEN** the service attempts app activation before reporting failure

#### Scenario: Unknown terminal opens cwd

- **WHEN** a target has `terminalApp == "Unknown"` and a valid working directory
- **THEN** the service opens the working directory as the fallback action

#### Scenario: UI jump failures are silent

- **WHEN** a double-click jump action receives an unsupported target or all fallback actions fail
- **THEN** the UI remains usable and shows no blocking error dialog

### Requirement: Bubble and card jump interaction

All visible bubble/card body surfaces for `.approval`, `.question`, `.completion`, and `.status` content SHALL support double-click jump-back when `SourceInfo.jumpTarget` is present. The jump gesture SHALL be scoped to the non-control body/background area so action buttons, option controls, freeform fields, dismiss behavior, hover pause, countdowns, and keyboard shortcuts continue to behave as specified.

#### Scenario: Notification bubble double-click jumps once

- **WHEN** a status or completion bubble with a jump target is double-clicked on its body
- **THEN** the injected jump action is invoked exactly once with the source jump target

#### Scenario: Approval controls retain their behavior

- **WHEN** an approval card has a jump target and the user clicks Allow, Deny, Always allow, or a keyboard shortcut
- **THEN** the approval decision behavior remains unchanged and is not replaced by the jump gesture

#### Scenario: Question controls retain their behavior

- **WHEN** a question card has a jump target and the user selects options, types freeform text, or submits
- **THEN** the question answer behavior remains unchanged and is not replaced by the jump gesture

#### Scenario: Missing jump target is a no-op

- **WHEN** any bubble or card is double-clicked but its source has no jump target
- **THEN** no jump action is invoked and no error is presented

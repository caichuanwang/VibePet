## MODIFIED Requirements

### Requirement: Hook-time jump target capture

The adapters SHALL build an initial `JumpTarget` during `parseEvent(stdin:env:)` from facts attributable to the hook process. Terminal app inference SHALL prefer cmux environment first, then `TERM_PROGRAM`, then iTerm/Ghostty fallback environment, and SHALL otherwise use `"Unknown"`. iTerm and Terminal.app MAY use a bounded, injected hook-time locator. Ghostty MUST NOT combine a process-derived TTY/cwd with the unrelated frontmost terminal identifier; without an attributable identifier it SHALL leave `terminalSessionID` empty for App-side enrichment. cmux and VS Code behavior SHALL remain unchanged. Every locator MUST fail open on runner failure, permission denial, timeout, or malformed output.

#### Scenario: iTerm and Terminal locators run for recognized hooks

- **WHEN** a recognized hook event is parsed from an iTerm or Terminal.app environment and the injected locator returns a precise session/tab snapshot
- **THEN** the envelope source carries the attributable session id, tty, or pane title values

#### Scenario: Background Ghostty hook does not capture frontmost ID

- **WHEN** a Ghostty hook has a process TTY/cwd but no attributable terminal identifier
- **THEN** capture leaves `terminalSessionID` empty and lets the App resolver enrich it later

#### Scenario: cmux and VS Code skip osascript locators

- **WHEN** a cmux or VS Code environment is parsed
- **THEN** no focused-terminal locator is invoked, cmux uses `CMUX_SURFACE_ID` when present, and VS Code relies on cwd

#### Scenario: Locator failure degrades without blocking hook parsing

- **WHEN** the injected locator fails, times out, or returns malformed output
- **THEN** parsing returns the same normalized envelope shape with a degraded or nil `JumpTarget`

### Requirement: App-side jump target resolver

`VibePetApp` SHALL provide a `TerminalJumpTargetResolver` that refreshes jump targets for live sessions without affecting session visibility, attachment, or liveness. The resolver SHALL inspect only Ghostty and Terminal.app sessions and fetch AppleScript snapshots with a bounded timeout. It SHALL prioritize an exact existing session identifier, then normalized TTY. cwd and title are weak signals and MAY update a target only when exactly one unmatched session matches exactly one unmatched snapshot. cwd comparison SHALL use standardized full paths rather than substring containment. Ambiguous matches, empty snapshot fields, and runner failures SHALL produce no update and preserve existing precise fields.

#### Scenario: Ghostty session is corrected from a unique snapshot

- **WHEN** a live Ghostty session matches exactly one snapshot by id or unique standardized cwd/title
- **THEN** the resolver returns an updated target containing only non-empty snapshot precision

#### Scenario: Terminal tab is corrected from a unique snapshot

- **WHEN** a live Terminal.app session matches exactly one snapshot by normalized tty or a bidirectionally unique title
- **THEN** the resolver returns an updated target without erasing existing cwd-derived fields

#### Scenario: Duplicate Terminal titles are not assigned

- **WHEN** a Terminal title matches multiple sessions or one session matches multiple snapshots
- **THEN** no title-based target update occurs

#### Scenario: Unsupported terminals are skipped by the resolver

- **WHEN** live sessions are for iTerm, cmux, VS Code, or an unknown terminal
- **THEN** the resolver does not query or return updates for those sessions

#### Scenario: Resolver failure is isolated from session liveness

- **WHEN** AppleScript snapshot fetching fails or times out
- **THEN** no update is returned and no session is completed, detached, hidden, or marked errored

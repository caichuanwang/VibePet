## MODIFIED Requirements

### Requirement: JumpTarget data structure

`VibePetCore` SHALL define a `JumpTarget` value type (`Equatable`, `Sendable`, `Codable`) for terminal jump-back with the fields `terminalApp`, optional `workspaceName`, optional `paneTitle`, optional `workingDirectory`, optional `terminalSessionID`, and optional `terminalTTY`. This model SHALL describe the terminal/cwd/session information needed by the App jump service and resolver. It SHALL remain decoding-compatible with older envelopes that omit newly added fields, and it SHALL ignore removed or unknown legacy keys when decoding.

#### Scenario: JumpTarget round-trips through Codable

- **WHEN** a `JumpTarget` with any subset of optional terminal jump-back fields populated is encoded and decoded
- **THEN** the decoded value equals the original

#### Scenario: Missing optional terminal session id decodes as nil

- **WHEN** a pre-jumpback envelope is decoded with `terminalApp`, workspace, pane, cwd, and tty fields but no `terminalSessionID`
- **THEN** the decoded `JumpTarget.terminalSessionID` is `nil` and decoding succeeds

#### Scenario: Legacy unsupported locator keys do not break decoding

- **WHEN** a `JumpTarget` payload includes legacy keys such as `codexThreadID`, `tmuxTarget`, `tmuxSocketPath`, or `warpPaneUUID`
- **THEN** decoding succeeds and those unsupported keys do not affect the terminal jump-back fields

### Requirement: SessionState.apply is a deterministic pure reducer

`VibePetCore` SHALL define a `SessionState` value type (`Equatable`, `Sendable`) holding `private(set) var sessionsByID: [String: AgentSession]` and a `mutating func apply(_ event: AgentEvent)`. Applying the same event sequence to the same initial state SHALL always yield the same `sessionsByID` (pure function). `sessionStarted` SHALL upsert a `running` session, preserving an existing session's `firstSeenAt`. `activityUpdated` SHALL set phase to `running` and update `summary`, EXCEPT it SHALL NOT downgrade a session currently in `waitingForApproval`/`waitingForAnswer` (concurrent activity must not clear a pending decision). `jumpTargetUpdated` SHALL replace the existing session's `jumpTarget` without changing its phase, liveness fields, or visibility derivation. A non-`sessionStarted` event for an unknown `sessionID` SHALL be ignored.

#### Scenario: Event sequence produces deterministic state

- **WHEN** a given `[AgentEvent]` sequence is applied to an empty `SessionState`
- **THEN** the resulting `sessionsByID` is identical on every run

#### Scenario: sessionStarted preserves existing firstSeenAt

- **WHEN** `sessionStarted` is applied for a `sessionID` that already exists
- **THEN** the session's `firstSeenAt` is unchanged and its phase becomes `running`

#### Scenario: activityUpdated does not clear a pending decision

- **WHEN** `activityUpdated` is applied to a session currently in `waitingForApproval` or `waitingForAnswer`
- **THEN** the session's phase remains the waiting phase rather than being downgraded to `running`

#### Scenario: jumpTargetUpdated changes only the jump target

- **WHEN** `jumpTargetUpdated` is applied to an existing waiting or running session
- **THEN** the session's `jumpTarget` is replaced and its phase, liveness fields, and visibility are otherwise unchanged

#### Scenario: Unknown session non-start event is ignored

- **WHEN** any event other than `sessionStarted` is applied for a `sessionID` not present in state
- **THEN** `sessionsByID` is unchanged

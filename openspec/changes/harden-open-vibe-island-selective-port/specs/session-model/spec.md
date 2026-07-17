## MODIFIED Requirements

### Requirement: SessionState.apply is a deterministic pure reducer

`VibePetCore` SHALL define `SessionState` as an `Equatable`, `Sendable` value with private-set sessions and a mutating `apply` that returns whether canonical state truly changed. Replaying a duplicate event SHALL be a no-op. An existing session's duplicate `sessionStarted` SHALL only enrich missing jump metadata and preserve its first-seen time, phase, summary, recency, liveness, error, and end state. Stale activity/completion SHALL not move lifecycle state backward; newer activity MAY reopen a turn-level completion but MUST NOT revive a native-ended session or clear a waiting decision. Late native SessionEnd MAY merge terminal end bits without overwriting newer content. Jump metadata MAY arrive late but MUST only fill missing fields.

#### Scenario: Duplicate start preserves waiting and completion

- **WHEN** a later duplicate `sessionStarted` arrives for a waiting or turn-completed session
- **THEN** it does not reset the phase, summary, recency, or liveness fields

#### Scenario: sessionStarted preserves existing firstSeenAt

- **WHEN** `sessionStarted` is applied for a `sessionID` that already exists
- **THEN** the session's `firstSeenAt` and lifecycle state are unchanged while missing jump metadata may be filled

#### Scenario: activityUpdated does not clear a pending decision

- **WHEN** `activityUpdated` is applied to a session currently in `waitingForApproval` or `waitingForAnswer`
- **THEN** the session's phase remains the waiting phase rather than being downgraded to `running`

#### Scenario: jumpTargetUpdated changes only the jump target

- **WHEN** `jumpTargetUpdated` is applied to an existing waiting or running session
- **THEN** missing jump metadata is enriched and its phase, liveness fields, and visibility are otherwise unchanged

#### Scenario: Unknown session non-start event is ignored

- **WHEN** any event other than `sessionStarted` is applied for a `sessionID` not present in state
- **THEN** `sessionsByID` is unchanged

#### Scenario: New activity reopens only a turn-level completion

- **WHEN** newer activity follows a turn-level completion
- **THEN** the session returns to running, but the same event cannot revive an ended session

#### Scenario: Late SessionEnd preserves newer content

- **WHEN** a native session-end event is older than the session's latest content
- **THEN** end/liveness bits are applied while the newer summary, error, and timestamp remain unchanged

#### Scenario: Exact replay has no transition

- **WHEN** any event is applied twice
- **THEN** the second application returns false and leaves state equal to the first result

## ADDED Requirements

### Requirement: Discovery and liveness reconciliation is conservative

Process liveness SHALL require two consecutive misses before ending a non-actionable session. Waiting approval/question sessions MUST remain visible through process gaps. A process-discovered placeholder SHALL merge with a hook session only on one unique exact claim; ambiguity SHALL preserve both sessions. Async liveness sampling SHALL apply only while its Host generation remains active. Any session added or canonically changed after the sampled snapshot SHALL be treated as alive for that sweep so stale results cannot add a process miss after newer hook activity.

#### Scenario: One liveness miss does not hide a session

- **WHEN** a running session is absent from one process sweep
- **THEN** it remains alive and visible until a second confirmed miss

#### Scenario: Ambiguous discovery does not merge

- **WHEN** more than one hook session matches a discovered placeholder's available identity
- **THEN** no session is rekeyed or removed

#### Scenario: Stop invalidates a pending initial sweep

- **WHEN** the Host stops before or while its initial liveness provider is suspended
- **THEN** the provider is not started when avoidable and no result from that generation is imported or published after stop

#### Scenario: Hook activity wins over an older liveness sample

- **WHEN** an existing session changes from a hook event while a liveness provider or terminal resolver is suspended
- **THEN** the older sample does not increment that session's process-miss count

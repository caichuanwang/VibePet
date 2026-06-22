## ADDED Requirements

### Requirement: Menu bar shows multi-session aggregate counts

`VibePetApp`'s `NSStatusItem` SHALL surface multi-session aggregation derived from `SessionState`: the count of visible/active sessions and the count of sessions that need attention (waiting for approval or answer). These counts SHALL update as `SessionState` changes and SHALL be pure derivations (no per-envelope bespoke state).

#### Scenario: Menu bar reflects active and needs-attention counts

- **WHEN** `SessionState` holds multiple sessions, some running and some waiting for approval/answer
- **THEN** the menu bar shows the visible/active session count and a separate needs-attention count matching `SessionState`'s `visibleSessions` and `attentionCount`

#### Scenario: Counts drop when sessions complete or are reaped

- **WHEN** sessions complete or are reaped by the process-liveness sweep
- **THEN** the menu bar's active and needs-attention counts decrease accordingly

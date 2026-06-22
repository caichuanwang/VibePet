## ADDED Requirements

### Requirement: SessionPhase enumerates the four converged phases

`VibePetCore` SHALL define a `SessionPhase` (`String`-backed, `Codable`, `Sendable`, `CaseIterable`) with exactly four cases — `running`, `waitingForApproval`, `waitingForAnswer`, `completed` — and SHALL expose `requiresAttention: Bool` that is `true` for `waitingForApproval` and `waitingForAnswer` and `false` otherwise. The dozen-plus lifecycle hooks converge onto these four phases.

#### Scenario: requiresAttention is true only for waiting phases

- **WHEN** `requiresAttention` is read on `.waitingForApproval` or `.waitingForAnswer`
- **THEN** it returns `true`

#### Scenario: requiresAttention is false for running and completed

- **WHEN** `requiresAttention` is read on `.running` or `.completed`
- **THEN** it returns `false`

### Requirement: AgentSession value type

`VibePetCore` SHALL define an `AgentSession` value type (`Equatable`, `Sendable`, `Codable`) carrying a stable `id: String`, `title`, `tool: ToolKind`, `phase: SessionPhase`, `summary`, `updatedAt: Date`, `firstSeenAt: Date`, an optional `jumpTarget: JumpTarget?`, and the fail-open liveness fields `isSessionEnded: Bool`, `isProcessAlive: Bool`, `processNotSeenCount: Int`. It SHALL expose a derived `isVisible: Bool` that is `true` when the phase `requiresAttention`, OR the session is neither ended nor process-dead, OR it completed recently.

#### Scenario: AgentSession round-trips through Codable

- **WHEN** an `AgentSession` is encoded to JSON and decoded back
- **THEN** the decoded value equals the original across all fields

#### Scenario: Attention-requiring session is visible

- **WHEN** `isVisible` is read on a session whose phase `requiresAttention`
- **THEN** it returns `true` regardless of liveness fields

### Requirement: AgentEvent vocabulary

`VibePetCore` SHALL define `AgentEvent` as a tagged sum type where every case carries a `sessionID: String` and a `timestamp: Date`, with cases: `sessionStarted`, `activityUpdated`, `permissionRequested`, `questionAsked`, `sessionCompleted` (carrying `isError` and `isSessionEnd` flags), `jumpTargetUpdated`, and `actionableStateResolved`. The type SHALL be `Sendable`.

#### Scenario: Every case carries session identity and timestamp

- **WHEN** any `AgentEvent` case is constructed
- **THEN** it exposes a `sessionID` and a `timestamp`

### Requirement: JumpTarget data structure

`VibePetCore` SHALL define a `JumpTarget` value type (`Equatable`, `Sendable`, `Codable`) with the fields `terminalApp`, optional `workspaceName`, optional `paneTitle`, optional `workingDirectory`, optional `terminalTTY`, and optional `codexThreadID`. This change SHALL only define and pass `JumpTarget` through events; resolving it from the environment is out of scope (sub-project 3).

#### Scenario: JumpTarget round-trips through Codable

- **WHEN** a `JumpTarget` with any subset of optional fields populated is encoded and decoded
- **THEN** the decoded value equals the original

### Requirement: SessionState.apply is a deterministic pure reducer

`VibePetCore` SHALL define a `SessionState` value type (`Equatable`, `Sendable`) holding `private(set) var sessionsByID: [String: AgentSession]` and a `mutating func apply(_ event: AgentEvent)`. Applying the same event sequence to the same initial state SHALL always yield the same `sessionsByID` (pure function). `sessionStarted` SHALL upsert a `running` session, preserving an existing session's `firstSeenAt`. `activityUpdated` SHALL set phase to `running` and update `summary`, EXCEPT it SHALL NOT downgrade a session currently in `waitingForApproval`/`waitingForAnswer` (concurrent activity must not clear a pending decision). A non-`sessionStarted` event for an unknown `sessionID` SHALL be ignored.

#### Scenario: Event sequence produces deterministic state

- **WHEN** a given `[AgentEvent]` sequence is applied to an empty `SessionState`
- **THEN** the resulting `sessionsByID` is identical on every run

#### Scenario: sessionStarted preserves existing firstSeenAt

- **WHEN** `sessionStarted` is applied for a `sessionID` that already exists
- **THEN** the session's `firstSeenAt` is unchanged and its phase becomes `running`

#### Scenario: activityUpdated does not clear a pending decision

- **WHEN** `activityUpdated` is applied to a session currently in `waitingForApproval` or `waitingForAnswer`
- **THEN** the session's phase remains the waiting phase rather than being downgraded to `running`

#### Scenario: Unknown session non-start event is ignored

- **WHEN** any event other than `sessionStarted` is applied for a `sessionID` not present in state
- **THEN** `sessionsByID` is unchanged

### Requirement: Decision entry and resolution transitions

`SessionState` SHALL map decision events and user resolutions onto phases. `permissionRequested` SHALL set phase `waitingForApproval`; `questionAsked` SHALL set phase `waitingForAnswer`. `mutating func resolvePermission(sessionID:approved:at:)` SHALL set the session to `running` when `approved` is `true` and to `completed` when `false`. `mutating func answerQuestion(sessionID:summary:at:)` SHALL set the session to `running` and update its summary. The `actionableStateResolved` event SHALL return a session to `running` ONLY when it is currently in a waiting phase, and otherwise leave it unchanged (models the timeout fail-open and user-handled-in-terminal cases).

#### Scenario: Approved permission returns session to running

- **WHEN** `resolvePermission` is called with `approved: true` on a `waitingForApproval` session
- **THEN** the session phase becomes `running`

#### Scenario: Denied permission completes the session

- **WHEN** `resolvePermission` is called with `approved: false`
- **THEN** the session phase becomes `completed`

#### Scenario: Answering a question returns to running

- **WHEN** `answerQuestion` is called on a `waitingForAnswer` session
- **THEN** the session phase becomes `running` and its summary is updated

#### Scenario: actionableStateResolved only affects waiting sessions

- **WHEN** `actionableStateResolved` is applied to a session that is `running` or `completed`
- **THEN** the session is left unchanged

### Requirement: sessionCompleted marks completion, error, and end

`SessionState.apply` of `sessionCompleted` SHALL set the session phase to `completed`, set `isError` when the event's error flag is set, and set `isSessionEnded` when the event's session-end flag is set.

#### Scenario: Stop completes the session

- **WHEN** a `sessionCompleted` event with neither flag set is applied
- **THEN** the session phase is `completed` and it is not marked ended or error

#### Scenario: SessionEnd marks the session ended

- **WHEN** a `sessionCompleted` event with the session-end flag set is applied
- **THEN** the session is `completed` and `isSessionEnded` is `true`

### Requirement: Process-liveness reaping reaps stuck-visible sessions

`SessionState` SHALL define `@discardableResult mutating func markProcessLiveness(aliveSessionIDs: Set<String>) -> Set<String>`. A session not present in `aliveSessionIDs` SHALL increment `processNotSeenCount`; after two consecutive misses (and not freshly `running`/attention) it SHALL be marked `isProcessAlive == false`, `isSessionEnded == true`, phase `completed`, and dropped from the visible set. A session present in `aliveSessionIDs` SHALL reset its `processNotSeenCount`. This is the fail-open backstop for a `SessionEnd` that never arrives.

#### Scenario: Two consecutive misses reap the session

- **WHEN** `markProcessLiveness` is called twice without a session's id in `aliveSessionIDs`
- **THEN** that session becomes ended, `completed`, and is excluded from `visibleSessions`

#### Scenario: Liveness resets when the process is seen again

- **WHEN** a session previously missed once is included in `aliveSessionIDs`
- **THEN** its `processNotSeenCount` resets to zero and it is not reaped

### Requirement: Derived aggregates and pet activity

`SessionState` SHALL expose pure derivations: `visibleSessions` (sessions whose `isVisible` is `true`), `runningCount`, `attentionCount` (sessions whose phase `requiresAttention`), and `activeActionableSession` (a session needing attention, if any). It SHALL derive a pet activity such that any attention-requiring session maps to `deciding`; a just-started session maps to `greeting` once; otherwise the activity is `idle` (the dedicated running animation row is deferred to sub-project 2). Derivations SHALL be pure functions of `sessionsByID`.

#### Scenario: Attention session drives deciding activity

- **WHEN** at least one session is `waitingForApproval` or `waitingForAnswer`
- **THEN** the derived pet activity is `deciding` and `attentionCount` is at least 1

#### Scenario: Counts reflect visible and attention sessions

- **WHEN** state holds a mix of running, waiting, and reaped sessions
- **THEN** `visibleSessions` excludes reaped sessions and `attentionCount` counts only waiting sessions

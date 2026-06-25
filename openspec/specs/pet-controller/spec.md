## Purpose

Define the `PetController` state machine and the `BridgeServerHost` routing that drives pet behavior and bubble presentation from received bridge envelopes.
## Requirements
### Requirement: Pet state machine for idle, greet, and notify

`VibePetApp` SHALL define a `PetController` driving a state machine over `idle`, `greet`, `notify`, and `decide` states per the technical design §5.2. The controller's current activity SHALL be derived from the App's `SessionState` (the single source of truth) rather than from a single envelope: any attention-requiring session drives `decide`; a freshly started session drives `greet` once; completion/status envelopes drive `notify`; otherwise `idle`. `idle` plays breathing/idle animation; `greet` plays the greeting; `notify` shows a non-interactive bubble carrying `completion` / `status`; `decide` highlights the pet for attention and shows an interactive bubble for response-requiring content (`approval` / `question`). When presenting any bubble/card, the controller SHALL preserve the envelope `SourceInfo` including its optional jump target and SHALL provide the surface with a terminal jump action.

#### Scenario: Notification content enters notify state

- **WHEN** a `.completion` or `.status` envelope is applied to `SessionState` and the session needs no attention
- **THEN** it transitions to `notify` and surfaces the corresponding bubble

#### Scenario: Returns to idle after the bubble dismisses

- **WHEN** the notify bubble auto-dismisses or is dismissed and no session needs attention
- **THEN** `PetController` returns to `idle`

#### Scenario: Attention-requiring session enters decide state

- **WHEN** `SessionState` holds a session whose phase `requiresAttention` (a pending `.approval` or `.question`)
- **THEN** `PetController` transitions to `decide`, highlights the pet, and presents the interactive bubble

#### Scenario: Presentation preserves source jump target

- **WHEN** `PetController` presents status, completion, approval, or question content from an envelope whose source has a jump target
- **THEN** the surface receives that source and a jump action capable of invoking terminal jump-back for the same target

### Requirement: Bridge server routes envelopes to the pet controller

`VibePetApp` SHALL run a `BridgeServer` via a `BridgeServerHost` on launch. For each received `BridgeEnvelope`, `BridgeServerHost` SHALL update the App's `SessionState` on the main actor -- translating notification envelopes into `AgentEvent`s and applying them, and entering `permissionRequested`/`questionAsked` for decision envelopes before blocking -- and the `PetController`'s presentation SHALL be driven by the resulting derived state and the envelope's `BubbleContent`. When an envelope source includes a jump target, `BridgeServerHost` SHALL preserve it in the applied session event and presentation path; later resolver-produced corrections SHALL be applied through `jumpTargetUpdated` events without blocking the accept loop.

#### Scenario: Server starts on app launch

- **WHEN** the App launches
- **THEN** `BridgeServerHost` starts a `BridgeServer` listening on the bridge socket

#### Scenario: Received notification updates session state and reaches the controller

- **WHEN** the running `BridgeServer` receives a notification envelope from a client
- **THEN** `BridgeServerHost` applies the corresponding `AgentEvent` to `SessionState` and `PetController` presents the matching bubble from the derived state

#### Scenario: Received jump target is stored with the session

- **WHEN** the running `BridgeServer` receives an envelope whose source includes a jump target and the envelope maps to a session event
- **THEN** the resulting session state stores that jump target for the session without changing fail-open behavior

#### Scenario: Resolver update applies without starving connections

- **WHEN** the terminal jump target resolver returns a corrected target for a live session
- **THEN** `BridgeServerHost` applies a `jumpTargetUpdated` event and continues serving other bridge connections

### Requirement: Approval response round-trip with requestId pairing

`BridgeServerHost` SHALL, for an envelope whose `content.needsResponse` is `true`, mark the session `waitingForApproval`/`waitingForAnswer` in `SessionState`, route it to `PetController`'s `decide` state, and await the user's decision, then reply on the same connection with a `BridgeResponseEnvelope` whose `requestId` matches the request. On resolution it SHALL also update `SessionState`: "Deny" maps to `deny(reason:)` and `resolvePermission(approved: false)`; "Allow once" to `allowOnce` and `resolvePermission(approved: true)`; "Always allow" -- when supported -- to `allowAlways(scopeHint:)` and `resolvePermission(approved: true)`; an answered question to `answerQuestion`. If the decision times out or the bubble is dismissed without a decision, it SHALL reply `.defer` and apply `actionableStateResolved` (returning the session to `running`, native flow unchanged). The await SHALL NOT block the accept loop or other connections.

#### Scenario: Deny replies with a paired deny and completes the session

- **WHEN** the user picks "Deny" on the approval card for a request
- **THEN** `BridgeServerHost` replies a `BridgeResponseEnvelope` with the matching `requestId` and `approval(deny(reason:))`, and the session phase becomes `completed`

#### Scenario: Allow once replies with a paired allowOnce and resumes running

- **WHEN** the user picks "Allow once" on the approval card for a request
- **THEN** `BridgeServerHost` replies a `BridgeResponseEnvelope` with the matching `requestId` and `approval(allowOnce)`, and the session phase returns to `running`

#### Scenario: No decision replies with defer and resolves the actionable state

- **WHEN** the decision deadline elapses or the card is dismissed without a decision
- **THEN** `BridgeServerHost` replies `.defer` with the matching `requestId` and applies `actionableStateResolved` so the session returns to `running` without blocking the tool

#### Scenario: Awaiting a decision does not starve other connections

- **WHEN** one connection is blocked awaiting a user decision
- **THEN** the accept loop and other in-flight connections continue to be served

### Requirement: Question response round-trip with requestId pairing

`BridgeServerHost` and `PetController` SHALL, for an envelope whose `content` is `.question`, present a `QuestionCard` in the `decide` state (rather than an `ApprovalCard`) and await the user's answer, then reply on the same connection with a `BridgeResponseEnvelope` whose `requestId` matches the request and whose `response` is `.question(QuestionAnswer)`. If the answer times out or the card is dismissed without a submission, it SHALL reply `.defer`. The await SHALL NOT block the accept loop or other connections. Question cards SHALL participate in the decision queue and the `decide` priority alongside approval cards.

#### Scenario: Question content presents a question card

- **WHEN** a `.question` envelope is routed to `PetController`'s `decide` state
- **THEN** a `QuestionCard` is presented for that content rather than an approval card, and the pet enters `decide`

#### Scenario: Submitted answer replies with a paired question response

- **WHEN** the user submits the question card for a request
- **THEN** `BridgeServerHost` replies a `BridgeResponseEnvelope` with the matching `requestId` and `question(QuestionAnswer)`

#### Scenario: No answer replies with defer

- **WHEN** the question card's deadline elapses or it is dismissed without a submission
- **THEN** the reply is a `BridgeResponseEnvelope` with the matching `requestId` and `.defer`

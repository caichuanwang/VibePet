## MODIFIED Requirements

### Requirement: Pet state machine for idle, greet, and notify

`VibePetApp` SHALL define a `PetController` driving a state machine over `idle`, `greet`, `notify`, and `decide` states per the technical design §5.2. The controller's current activity SHALL be **derived from the App's `SessionState`** (the single source of truth) rather than from a single envelope: any attention-requiring session drives `decide`; a freshly started session drives `greet` once; completion/status envelopes drive `notify`; otherwise `idle`. `idle` plays breathing/idle animation; `greet` plays the greeting; `notify` shows a non-interactive bubble carrying `completion` / `status`; `decide` highlights the pet for attention and shows an interactive bubble for response-requiring content (`approval` / `question`).

#### Scenario: Notification content enters notify state

- **WHEN** a `.completion` or `.status` envelope is applied to `SessionState` and the session needs no attention
- **THEN** `PetController` transitions to `notify` and surfaces the corresponding bubble

#### Scenario: Returns to idle after the bubble dismisses

- **WHEN** the notify bubble auto-dismisses or is dismissed and no session needs attention
- **THEN** `PetController` returns to `idle`

#### Scenario: Attention-requiring session enters decide state

- **WHEN** `SessionState` holds a session whose phase `requiresAttention` (a pending `.approval` or `.question`)
- **THEN** `PetController` transitions to `decide`, highlights the pet, and presents the interactive bubble

### Requirement: Bridge server routes envelopes to the pet controller

`VibePetApp` SHALL run a `BridgeServer` via a `BridgeServerHost` on launch. For each received `BridgeEnvelope`, `BridgeServerHost` SHALL update the App's `SessionState` on the main actor — translating notification envelopes into `AgentEvent`s and applying them, and entering `permissionRequested`/`questionAsked` for decision envelopes before blocking — and the `PetController`'s presentation SHALL be driven by the resulting derived state and the envelope's `BubbleContent`.

#### Scenario: Server starts on app launch

- **WHEN** the App launches
- **THEN** `BridgeServerHost` starts a `BridgeServer` listening on the bridge socket

#### Scenario: Received notification updates session state and reaches the controller

- **WHEN** the running `BridgeServer` receives a notification envelope
- **THEN** `BridgeServerHost` applies the corresponding `AgentEvent` to `SessionState` and `PetController` presents the matching bubble from the derived state

### Requirement: Approval response round-trip with requestId pairing

`BridgeServerHost` SHALL, for an envelope whose `content.needsResponse` is `true`, mark the session `waitingForApproval`/`waitingForAnswer` in `SessionState`, route it to `PetController`'s `decide` state, and await the user's decision, then reply on the same connection with a `BridgeResponseEnvelope` whose `requestId` matches the request. On resolution it SHALL also update `SessionState`: "Deny" maps to `deny(reason:)` and `resolvePermission(approved: false)`; "Allow once" to `allowOnce` and `resolvePermission(approved: true)`; "Always allow" — when supported — to `allowAlways(scopeHint:)` and `resolvePermission(approved: true)`; an answered question to `answerQuestion`. If the decision times out or the bubble is dismissed without a decision, it SHALL reply `.defer` and apply `actionableStateResolved` (returning the session to `running`, native flow unchanged). The await SHALL NOT block the accept loop or other connections.

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

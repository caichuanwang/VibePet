## MODIFIED Requirements

### Requirement: Approval response round-trip with requestId pairing

`BridgeServerHost` SHALL, for an envelope whose `content.needsResponse` is `true`, mark the session `waitingForApproval`/`waitingForAnswer` in `SessionState`, route it to `PetController`'s `decide` state, and await the user's decision indefinitely (there is NO App-side decision timeout), then reply on the same connection with a `BridgeResponseEnvelope` whose `requestId` matches the request. On resolution it SHALL also update `SessionState`: "Deny" maps to `deny(reason:)` and `resolvePermission(approved: false)`; "Allow once" to `allowOnce` and `resolvePermission(approved: true)`; "Always allow" -- when supported -- to `allowAlways(scopeHint:)` and `resolvePermission(approved: true)`; an answered question to `answerQuestion`. If the bubble is dismissed without a decision (or the pet is hidden so no card can be presented), it SHALL reply `.defer` and apply `actionableStateResolved` (returning the session to `running`, native flow unchanged). The CLI hook's own read timeout remains the ultimate fail-open backstop should the user never act. The await SHALL NOT block the accept loop or other connections, and the decision continuation SHALL remain single-owner so a card is never resumed twice.

#### Scenario: Deny replies with a paired deny and completes the session

- **WHEN** the user picks "Deny" on the approval card for a request
- **THEN** `BridgeServerHost` replies a `BridgeResponseEnvelope` with the matching `requestId` and `approval(deny(reason:))`, and the session phase becomes `completed`

#### Scenario: Allow once replies with a paired allowOnce and resumes running

- **WHEN** the user picks "Allow once" on the approval card for a request
- **THEN** `BridgeServerHost` replies a `BridgeResponseEnvelope` with the matching `requestId` and `approval(allowOnce)`, and the session phase returns to `running`

#### Scenario: Pending approval waits indefinitely for the user

- **WHEN** an approval card is presented and the user has not yet acted
- **THEN** the card stays presented with no countdown and the request remains pending (no automatic `.defer` is emitted by the App)

#### Scenario: Dismissal replies with defer and resolves the actionable state

- **WHEN** the card is dismissed without a decision, or the pet is hidden so the card cannot be presented
- **THEN** `BridgeServerHost` replies `.defer` with the matching `requestId` and applies `actionableStateResolved` so the session returns to `running` without blocking the tool

#### Scenario: Awaiting a decision does not starve other connections

- **WHEN** one connection is blocked awaiting a user decision
- **THEN** the accept loop and other in-flight connections continue to be served

### Requirement: Question response round-trip with requestId pairing

`BridgeServerHost` and `PetController` SHALL, for an envelope whose `content` is `.question`, present a `QuestionCard` in the `decide` state (rather than an `ApprovalCard`) and await the user's answer indefinitely (there is NO App-side decision timeout), then reply on the same connection with a `BridgeResponseEnvelope` whose `requestId` matches the request and whose `response` is `.question(QuestionAnswer)`. If the card is dismissed without a submission, it SHALL reply `.defer`. The CLI hook's own read timeout remains the ultimate fail-open backstop. The await SHALL NOT block the accept loop or other connections. Question cards SHALL participate in the decision queue and the `decide` priority alongside approval cards.

#### Scenario: Question content presents a question card

- **WHEN** a `.question` envelope is routed to `PetController`'s `decide` state
- **THEN** a `QuestionCard` is presented for that content rather than an approval card, and the pet enters `decide`

#### Scenario: Submitted answer replies with a paired question response

- **WHEN** the user submits the question card for a request
- **THEN** `BridgeServerHost` replies a `BridgeResponseEnvelope` with the matching `requestId` and `question(QuestionAnswer)`

#### Scenario: Unsubmitted question waits indefinitely

- **WHEN** a question card is presented and the user has not yet submitted
- **THEN** the card stays presented with no countdown and the request remains pending (no automatic `.defer` is emitted by the App)

#### Scenario: Dismissal replies with defer

- **WHEN** the question card is dismissed without a submission
- **THEN** the reply is a `BridgeResponseEnvelope` with the matching `requestId` and `.defer`

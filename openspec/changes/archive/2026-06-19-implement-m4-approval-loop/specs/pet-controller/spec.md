## MODIFIED Requirements

### Requirement: Pet state machine for idle, greet, and notify

`VibePetApp` SHALL define a `PetController` driving a state machine over `idle`, `greet`, `notify`, and `decide` states per the technical design §5.2. `idle` plays breathing/idle animation; `greet` plays the greeting; `notify` shows a non-interactive bubble carrying `completion` / `status`; `decide` highlights the pet for attention and shows an interactive approval bubble for response-requiring content (`approval` in this milestone; `question` in M5).

#### Scenario: Notification content enters notify state

- **WHEN** `PetController` receives a `BridgeEnvelope` whose `content` is `.completion` or `.status`
- **THEN** it transitions to `notify` and surfaces the corresponding bubble

#### Scenario: Returns to idle after the bubble dismisses

- **WHEN** the notify bubble auto-dismisses or is dismissed
- **THEN** `PetController` returns to `idle`

#### Scenario: Response-required content enters decide state

- **WHEN** `PetController` receives content whose `needsResponse` is `true` (an `.approval`)
- **THEN** it transitions to `decide`, highlights the pet, and presents the interactive approval bubble

## ADDED Requirements

### Requirement: Approval response round-trip with requestId pairing

`BridgeServerHost` SHALL, for an envelope whose `content.needsResponse` is `true`, route it to `PetController`'s `decide` state and await the user's decision, then reply on the same connection with a `BridgeResponseEnvelope` whose `requestId` matches the request. "Deny" SHALL map to `deny(reason:)`, "Allow once" to `allowOnce`, and — when allowAlways is supported — "Always allow" to `allowAlways(scopeHint:)`. If the decision times out or the bubble is dismissed without a decision, it SHALL reply `.defer`. The await SHALL NOT block the accept loop or other connections.

#### Scenario: Deny replies with a paired deny

- **WHEN** the user picks "Deny" on the approval card for a request
- **THEN** `BridgeServerHost` replies a `BridgeResponseEnvelope` with the matching `requestId` and `approval(deny(reason:))`

#### Scenario: Allow once replies with a paired allowOnce

- **WHEN** the user picks "Allow once" on the approval card for a request
- **THEN** `BridgeServerHost` replies a `BridgeResponseEnvelope` with the matching `requestId` and `approval(allowOnce)`

#### Scenario: No decision replies with defer

- **WHEN** the decision deadline elapses or the card is dismissed without a decision
- **THEN** `BridgeServerHost` replies a `BridgeResponseEnvelope` with the matching `requestId` and `.defer`

#### Scenario: Awaiting a decision does not starve other connections

- **WHEN** one connection is blocked awaiting a user decision
- **THEN** the accept loop and other in-flight connections continue to be served

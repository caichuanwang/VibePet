## Purpose

Define the `PetController` state machine and the `BridgeServerHost` routing that drives pet behavior and bubble presentation from received bridge envelopes.

## Requirements

### Requirement: Pet state machine for idle, greet, and notify

`VibePetApp` SHALL define a `PetController` driving a state machine over `idle`, `greet`, and `notify` states per the technical design §5.2. `idle` plays breathing/idle animation; `greet` plays the greeting; `notify` shows a non-interactive bubble carrying `completion` / `status`. The `decide` state for `approval` / `question` is out of scope for this milestone.

#### Scenario: Notification content enters notify state

- **WHEN** `PetController` receives a `BridgeEnvelope` whose `content` is `.completion` or `.status`
- **THEN** it transitions to `notify` and surfaces the corresponding bubble

#### Scenario: Returns to idle after the bubble dismisses

- **WHEN** the notify bubble auto-dismisses or is dismissed
- **THEN** `PetController` returns to `idle`

#### Scenario: Response-required content is not handled in this milestone

- **WHEN** `PetController` receives content whose `needsResponse` is `true`
- **THEN** it does not enter an approval/question interaction in this milestone (the `decide` state is deferred to M4)

### Requirement: Bridge server routes envelopes to the pet controller

`VibePetApp` SHALL run a `BridgeServer` via a `BridgeServerHost` on launch, and SHALL route each received `BridgeEnvelope` to the `PetController` on the main actor so bubble presentation is driven by `BubbleContent`.

#### Scenario: Server starts on app launch

- **WHEN** the App launches
- **THEN** `BridgeServerHost` starts a `BridgeServer` listening on the bridge socket

#### Scenario: Received envelope reaches the controller

- **WHEN** the running `BridgeServer` receives a notification envelope from a client
- **THEN** `BridgeServerHost` forwards it to `PetController`, which presents the matching bubble

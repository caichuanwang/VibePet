## MODIFIED Requirements

### Requirement: Approval response round-trip with requestId pairing

`BridgeServerHost` SHALL mark response-bearing approval content actionable in canonical `SessionState`, route it to `PetController`, and await that request independently. The App SHALL fail it open after a tool-specific deadline below the CLI deadline (86,385 seconds for Claude Code; 3,585 seconds for Codex), or immediately on peer disconnect or App stop. Every resolution SHALL reply at most once with the matching `requestId` and clear the matching continuation, card, badge, and actionable state without blocking other connections.

#### Scenario: Allow once replies with a paired response

- **WHEN** the user allows an approval before its deadline
- **THEN** the matching response is sent once and the session returns to running

#### Scenario: Deny replies with a paired deny and completes the session

- **WHEN** the user denies an approval before its deadline
- **THEN** the matching deny response is sent once and the session becomes completed

#### Scenario: App deadline fails open and ignores a late click

- **WHEN** the user does not act before the tool-specific App deadline
- **THEN** the App resolves the request as `.defer`, clears its UI/state, and ignores a later callback

#### Scenario: Peer disconnect cancels only the matching request

- **WHEN** a displayed approval's hook connection closes
- **THEN** that request is failed open and cleared while unrelated queued or in-flight decisions remain valid

#### Scenario: Native SessionEnd cancels all pending requests for its session

- **WHEN** a native SessionEnd arrives while one or more approvals or questions for the same session are pending
- **THEN** every matching continuation fails open exactly once, all matching UI is cleared, and the ended session remains completed

#### Scenario: Decision arriving after native SessionEnd is not presented

- **WHEN** a native SessionEnd is reduced before a decision for that session reaches App registration
- **THEN** the later decision immediately returns `.defer` without being queued, displayed, or changing the completed session, even after liveness removes that session from visible canonical state

#### Scenario: Dismissal replies with defer and resolves actionable state

- **WHEN** the card is dismissed without a decision, or the pet is hidden so no card can be presented
- **THEN** the matching request replies `.defer` and the session returns to running

#### Scenario: Awaiting a decision does not starve other connections

- **WHEN** one approval awaits user action
- **THEN** other connections and session events continue to be handled

### Requirement: Question response round-trip with requestId pairing

`BridgeServerHost` and `PetController` SHALL present `.question` content in the same request-scoped queue and deadline system as approvals. A submitted answer SHALL produce one matching `.question(QuestionAnswer)` response; dismissal, deadline, peer disconnect, hidden pet, or App stop SHALL produce `.defer` and clear the matching actionable state.

#### Scenario: Question content presents a question card

- **WHEN** a `.question` envelope is routed to `PetController`'s `decide` state
- **THEN** a `QuestionCard` is presented rather than an approval card

#### Scenario: Submitted answer replies once

- **WHEN** the user submits a question before its deadline
- **THEN** one matching question response is returned and the session resumes running

#### Scenario: Unsubmitted question expires fail-open

- **WHEN** a question remains unanswered at its App deadline
- **THEN** it is removed, returns `.defer`, and does not leave an attention badge

#### Scenario: Dismissal replies with defer

- **WHEN** the question card is dismissed without a submission
- **THEN** the matching request replies `.defer` and clears its actionable state

#### Scenario: Awaiting a question does not starve other connections

- **WHEN** one question awaits user input
- **THEN** other connections and session events continue to be handled

## ADDED Requirements

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

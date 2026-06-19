## ADDED Requirements

### Requirement: Independent queued response bubbles keyed by requestId

`VibePetApp` SHALL track multiple response-requiring bubbles independently, keyed by `requestId`, in FIFO order with the earliest arrival on top. Each queued request SHALL retain its own content and pairing so decisions are routed back to the correct request.

#### Scenario: Two approvals are queued independently

- **WHEN** two `.approval` envelopes with distinct `requestId`s arrive before either is answered
- **THEN** both are tracked independently and the earliest-arriving one is on top

### Requirement: Stacked peeking presentation with remaining count

Behind the top card, at most 2 cards SHALL peek a thin edge, and when more than the visible cards remain the stack SHALL show a "还有 N 个待处理" count.

#### Scenario: Extra approvals surface a remaining count

- **WHEN** more response-requiring bubbles are queued than are visibly peeking
- **THEN** the stack shows a "还有 N 个待处理" count for the remainder

### Requirement: Per-card countdown and silent timeout pop

Each peeking card SHALL run its own countdown; on timeout it SHALL silently `defer` and pop from the stack without requiring user interaction.

#### Scenario: Timed-out card defers and pops

- **WHEN** a queued card's countdown reaches zero before it is answered
- **THEN** it silently defers (fail-open) and is removed from the stack

### Requirement: State priority ordering

Presentation priority SHALL be `decide` > `notify` > `greet`. While a `decide` card is present, incoming notification content SHALL only accumulate a small badge rather than interrupt the decision.

#### Scenario: Notification during decide only badges

- **WHEN** a `.completion` or `.status` envelope arrives while a `decide` card is presented
- **THEN** it is accumulated as a small badge instead of replacing or interrupting the approval card

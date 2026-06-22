## Purpose

Define the normalized bridge message and response protocol shared by tool hooks and the app.

## Requirements

### Requirement: Normalized bridge envelope

`VibePetCore` SHALL define a `BridgeEnvelope` carrying `version` (=1), `requestId` (UUID), `source` (`SourceInfo` with `tool`/`projectName`/`sessionShortId`/`cwd`, plus a stable `sessionID: String` and an optional `jumpTarget: JumpTarget?`), and `content` (`BubbleContent`). `sessionID` SHALL be a cross-event-stable identifier the reducer keys sessions on, while `sessionShortId` is retained for display. `ToolKind` SHALL enumerate `claudeCode` and `codex`. All types SHALL be `Codable` and `Sendable`.

#### Scenario: Envelope round-trips through Codable

- **WHEN** a `BridgeEnvelope` is encoded to JSON and decoded back
- **THEN** the decoded value equals the original, including `version`, `requestId`, `source` (with `sessionID` and any `jumpTarget`), and `content`

#### Scenario: SourceInfo exposes a stable sessionID distinct from the display short id

- **WHEN** a `SourceInfo` is constructed with both a `sessionID` and a `sessionShortId`
- **THEN** both fields are preserved independently through encode/decode and `sessionID` is the value used to key the session reducer

### Requirement: Bubble content with four interaction cases

`BubbleContent` SHALL be a tagged enum with exactly four cases — `approval(ApprovalContent)`, `question(QuestionContent)`, `completion(CompletionContent)`, `status(StatusContent)` — and SHALL define the supporting structures `ApprovalContent`, `QuestionContent`, `QuestionItem`, `QuestionOption`, `CompletionContent`, `StatusContent`, `ActionPreview`, `AlwaysAllowOption`, and `RiskLevel` per the technical design §3.2.

#### Scenario: Each content case round-trips

- **WHEN** an envelope is built with each of the four `BubbleContent` cases and run through encode/decode
- **THEN** every case decodes back to its original associated value with no data loss

#### Scenario: ActionPreview variants encode distinctly

- **WHEN** each `ActionPreview` case (`command`, `fileChange`, `fileRead`, `network`, `generic`) is encoded and decoded
- **THEN** the case discriminator and associated values are preserved

### Requirement: needsResponse classification

`BubbleContent` SHALL expose a `needsResponse: Bool` that returns `true` for `approval` and `question` and `false` for `completion` and `status`.

#### Scenario: Approval and question require a response

- **WHEN** `needsResponse` is read on an `.approval` or `.question` content
- **THEN** it returns `true`

#### Scenario: Completion and status do not require a response

- **WHEN** `needsResponse` is read on a `.completion` or `.status` content
- **THEN** it returns `false`

### Requirement: Bridge response model

`VibePetCore` SHALL define `BridgeResponseEnvelope` (`requestId` + `response`) and `BridgeResponse` with cases `approval(ApprovalDecision)`, `question(QuestionAnswer)`, and `defer`. `ApprovalDecision` SHALL provide `allowOnce`, `allowAlways(scopeHint:)`, and `deny(reason:)`. `QuestionAnswer` SHALL carry `answers` and `freeform` keyed by question header. All types SHALL be `Codable` and `Sendable`.

#### Scenario: Response envelope round-trips with request pairing

- **WHEN** a `BridgeResponseEnvelope` is encoded and decoded
- **THEN** the `requestId` and the `response` case (including associated values such as `deny` reason or `allowAlways` scopeHint) are preserved

#### Scenario: Defer is representable

- **WHEN** a `BridgeResponse.defer` is encoded and decoded
- **THEN** it decodes back to `.defer`

## MODIFIED Requirements

### Requirement: Normalized bridge envelope

`VibePetCore` SHALL define a `BridgeEnvelope` carrying `version` (=1), `requestId` (UUID), `source` (`SourceInfo` with `tool`/`projectName`/`sessionShortId`/`cwd`, plus a stable `sessionID: String` and an optional `jumpTarget: JumpTarget?`), and `content` (`BubbleContent`). `sessionID` SHALL be a cross-event-stable identifier the reducer keys sessions on, while `sessionShortId` is retained for display. `ToolKind` SHALL enumerate `claudeCode` and `codex`. All types SHALL be `Codable` and `Sendable`.

#### Scenario: Envelope round-trips through Codable

- **WHEN** a `BridgeEnvelope` is encoded to JSON and decoded back
- **THEN** the decoded value equals the original, including `version`, `requestId`, `source` (with `sessionID` and any `jumpTarget`), and `content`

#### Scenario: SourceInfo exposes a stable sessionID distinct from the display short id

- **WHEN** a `SourceInfo` is constructed with both a `sessionID` and a `sessionShortId`
- **THEN** both fields are preserved independently through encode/decode and `sessionID` is the value used to key the session reducer

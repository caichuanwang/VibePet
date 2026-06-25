## MODIFIED Requirements

### Requirement: Normalized bridge envelope

`VibePetCore` SHALL define a `BridgeEnvelope` carrying `version` (=1), `requestId` (UUID), `source` (`SourceInfo` with `tool`/`projectName`/`sessionShortId`/`cwd`, plus a stable `sessionID: String` and an optional `jumpTarget: JumpTarget?`), and `content` (`BubbleContent`). `sessionID` SHALL be a cross-event-stable identifier the reducer keys sessions on, while `sessionShortId` is retained for display. `SourceInfo.jumpTarget` SHALL carry the hook-captured terminal jump-back initial value when available and SHALL decode to `nil` when absent for older hook payloads. `ToolKind` SHALL enumerate `claudeCode` and `codex`. All types SHALL be `Codable` and `Sendable`.

#### Scenario: Envelope round-trips through Codable

- **WHEN** a `BridgeEnvelope` is encoded to JSON and decoded back
- **THEN** the decoded value equals the original, including `version`, `requestId`, `source` (with `sessionID` and any hook-captured `jumpTarget`), and `content`

#### Scenario: SourceInfo exposes a stable sessionID distinct from the display short id

- **WHEN** a `SourceInfo` is constructed with both a `sessionID` and a `sessionShortId`
- **THEN** both fields are preserved independently through encode/decode and `sessionID` is the value used to key the session reducer

#### Scenario: Missing jumpTarget remains backward compatible

- **WHEN** an older bridge envelope without `source.jumpTarget` is decoded
- **THEN** decoding succeeds and `source.jumpTarget` is `nil`

#### Scenario: Captured jumpTarget is preserved for App routing

- **WHEN** a hook adapter includes a terminal jump target in `SourceInfo`
- **THEN** the value is preserved through bridge envelope encoding/decoding and remains available to the App presentation and session reducer paths

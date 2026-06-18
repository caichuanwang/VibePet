## ADDED Requirements

### Requirement: ToolAdapter protocol

`VibePetCore` SHALL define a `ToolAdapter` protocol (conforming to `Sendable`) with: a `tool: ToolKind` property; `parseEvent(stdin: Data, env: [String: String]) throws -> BridgeEnvelope?` that normalizes a tool's native event into a `BridgeEnvelope` (returning `nil` for events it does not care about); and `encodeResponse(_ response: BridgeResponse, for envelope: BridgeEnvelope) -> Data` that renders a user response into the tool's expected stdout bytes.

#### Scenario: Protocol method signatures align with bridge models

- **WHEN** the protocol is compiled against the `BridgeEnvelope` and `BridgeResponse` models
- **THEN** compilation succeeds with no signature mismatch

#### Scenario: Mock adapter conforms and compiles

- **WHEN** a test-only mock type conforms to `ToolAdapter`
- **THEN** it compiles and can return a `BridgeEnvelope` from `parseEvent` and `Data` from `encodeResponse`

#### Scenario: Unrecognized event yields nil

- **WHEN** a mock adapter's `parseEvent` is given input it is configured to ignore
- **THEN** it returns `nil` rather than throwing

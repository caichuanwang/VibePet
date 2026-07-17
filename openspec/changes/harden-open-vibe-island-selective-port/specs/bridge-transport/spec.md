## MODIFIED Requirements

### Requirement: Stale socket cleanup on startup

The App SHALL clean up and recreate a residual `bridge.sock` only when the path is a Unix socket owned by the current user inside the private VibePet support directory. Ordinary files, directories, foreign-owned sockets, and nodes whose device/inode identity changes between verification and removal MUST be preserved and server startup SHALL fail safely.

#### Scenario: Owned stale Unix socket is replaced

- **WHEN** an unreachable current-user Unix socket exists at `bridge.sock` and the server starts
- **THEN** the server removes that socket and binds successfully

#### Scenario: Ordinary path node is preserved

- **WHEN** an ordinary file or directory exists at `bridge.sock`
- **THEN** server startup fails with an unsafe-path error and preserves the node unchanged

#### Scenario: Replacement node is preserved on stop

- **WHEN** the bound socket path is replaced with another node before the server stops
- **THEN** stop does not remove the replacement because its device/inode identity differs

## ADDED Requirements

### Requirement: Bounded one-request NDJSON framing

Each accepted connection SHALL decode at most one NDJSON request frame. The frame payload MUST NOT exceed 4 MiB and MUST arrive within a monotonic two-second deadline measured from accept; partial input, drip-fed input, malformed data, EOF, and extra frames SHALL terminate the connection without extending the deadline or changing protocol state.

#### Scenario: Drip-fed request exceeds the absolute deadline

- **WHEN** a peer sends bytes often enough to avoid an idle timeout but does not complete the first frame within two seconds of accept
- **THEN** the server closes the connection and performs no unbounded wait or allocation

#### Scenario: Frame exceeds the maximum by one byte

- **WHEN** a frame payload is 4 MiB plus one byte before its newline
- **THEN** the server rejects it as oversized and fails open

#### Scenario: Maximum valid frame is accepted over a socket

- **WHEN** an exact 4 MiB frame and newline are delivered over a local socket within two seconds
- **THEN** the server's bounded chunked reader returns the complete frame before the absolute deadline

### Requirement: Bounded client request writes

`BridgeClient` SHALL reject an encoded request larger than 4 MiB before connecting. It SHALL apply one monotonic absolute deadline to the complete request write so a peer that accepts but does not read cannot block either notification or decision hook execution indefinitely.

#### Scenario: Peer accepts without reading

- **WHEN** the App-side peer accepts a maximum-size request but does not drain the socket
- **THEN** the client returns a typed write-timeout error at its absolute write deadline and the hook fails open

### Requirement: Decision response identity and peer cancellation

`BridgeClient` SHALL accept exactly one response whose `requestId` matches its request and SHALL apply one monotonic absolute deadline to the entire response frame. After decoding a decision request, `BridgeServer` SHALL monitor EOF/HUP and unexpected extra input; it SHALL cancel the matching request by ID so App actionable UI/state clears within two seconds.

#### Scenario: Drip-fed response cannot extend the CLI budget

- **WHEN** a server sends response bytes below the socket idle timeout but does not complete the frame before the configured client deadline
- **THEN** `BridgeClient` returns a read-timeout error at the absolute deadline

#### Scenario: Mismatched response is rejected

- **WHEN** the response envelope carries a different `requestId`
- **THEN** `BridgeClient` returns an invalid-response error and the hook fails open

#### Scenario: Peer disconnect clears a displayed decision

- **WHEN** a decision has entered canonical waiting state and the hook peer disconnects
- **THEN** the matching continuation, card, badge, and actionable session state are cleared within two seconds without affecting another request

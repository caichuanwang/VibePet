## Purpose

Define the local Unix socket transport used for hook-to-app bridge communication.

## Requirements

### Requirement: Socket path and permissions

`VibePetCore` SHALL resolve the bridge socket to `~/Library/Application Support/VibePet/bridge.sock`, creating the parent directory with mode `0700` and the socket with mode `0600`, accessible only to the current user.

#### Scenario: Directory and socket created with restrictive permissions

- **WHEN** the bridge server binds the socket for the first time
- **THEN** the `VibePet` support directory exists with mode `0700` and the socket file has mode `0600`

### Requirement: Newline-delimited JSON round trip

`BridgeServer` SHALL listen on the socket and `BridgeClient` SHALL connect and exchange newline-delimited JSON messages, completing at least one full request/response round trip locally.

#### Scenario: Client and server exchange one message

- **WHEN** a `BridgeClient` connects to a running `BridgeServer` and sends one newline-terminated JSON envelope
- **THEN** the server decodes it and the client can receive a newline-terminated JSON response over the same connection

### Requirement: Stale socket cleanup on startup

The App SHALL clean up and recreate any residual socket file when starting, so a leftover socket from a previous run does not block binding.

#### Scenario: Leftover socket is replaced

- **WHEN** a stale `bridge.sock` exists and the server starts
- **THEN** the server removes the stale file and binds successfully

### Requirement: Explicit failure on connection error

`BridgeClient` SHALL return a clear, typed error when it cannot connect (e.g., server not running or socket missing) rather than hanging indefinitely.

#### Scenario: Connection failure surfaces an error

- **WHEN** a `BridgeClient` attempts to connect with no server listening
- **THEN** it returns a distinguishable connection error promptly

## Purpose

Define the local Unix socket transport used for hook-to-app bridge communication.

## Requirements

### Requirement: Socket path and permissions

`VibePetCore` SHALL resolve the bridge socket to `~/Library/Application Support/VibePet/bridge.sock`, creating the parent directory with mode `0700` and the socket with mode `0600`, accessible only to the current user. The `VibePet` support directory SHALL be created through a single shared "ensure support directory exists at `0700`" utility used by both the socket path resolver and `ConfigStore`, so the directory is stably `0700` regardless of which writer creates it first.

#### Scenario: Directory and socket created with restrictive permissions

- **WHEN** the bridge server binds the socket for the first time
- **THEN** the `VibePet` support directory exists with mode `0700` and the socket file has mode `0600`

#### Scenario: Directory is 0700 even when config is written first

- **WHEN** `ConfigStore` creates the support directory before the bridge server starts
- **THEN** the directory is created with mode `0700` (not the default umask), so the socket's parent directory is user-private before it carries traffic

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

`BridgeClient` SHALL return a clear, typed error when it cannot connect (e.g., server not running or socket missing) rather than hanging indefinitely. The connect attempt SHALL be bounded by a deadline so a non-accepting or stalled peer cannot block the client past that deadline.

#### Scenario: Connection failure surfaces an error

- **WHEN** a `BridgeClient` attempts to connect with no server listening
- **THEN** it returns a distinguishable connection error promptly

#### Scenario: Connect respects a deadline

- **WHEN** a `BridgeClient` connect cannot complete within its configured deadline
- **THEN** it returns a typed timeout error rather than blocking indefinitely

### Requirement: Blocking socket I/O off the cooperative pool

`BridgeServer` SHALL NOT run blocking `accept` / `read` / `write` on the Swift concurrency cooperative thread pool. Blocking socket operations SHALL run on a dedicated dispatch queue / thread (or use non-blocking sockets with an event source) so that the accept loop and concurrent connection handlers cannot starve the cooperative executor.

#### Scenario: Accept loop does not occupy a cooperative thread

- **WHEN** `BridgeServer` is listening and handling connections
- **THEN** its blocking accept/read/write run off the Swift concurrency cooperative pool, leaving cooperative threads free

#### Scenario: Concurrent connections do not deadlock the executor

- **WHEN** multiple connections are handled at once
- **THEN** no cooperative-pool starvation or deadlock occurs

### Requirement: Interruptible shutdown without start/stop race

`BridgeServer.stop()` SHALL reliably interrupt a thread blocked in `accept()` on Darwin without relying on undefined `close()`-wakeup behavior, and SHALL register the listening file descriptor into server state before the accept task starts so a `stop()` landing in the start window cannot leak the descriptor.

#### Scenario: Stop interrupts a blocked accept

- **WHEN** `stop()` is called while a thread is blocked in `accept()`
- **THEN** the accept unblocks and the server shuts down without relying on undefined close-wakeup behavior

#### Scenario: Stop during startup does not leak the descriptor

- **WHEN** `stop()` is called immediately after `start()`, before the accept loop is fully running
- **THEN** the listening descriptor is closed exactly once and not leaked

### Requirement: Client read timeout

`BridgeClient` SHALL bound its response read with a deadline so that a server which accepts a connection but never replies cannot block the client indefinitely; on deadline it SHALL return a typed timeout error that the CLI can map to a `defer` fail-open outcome.

#### Scenario: Stalled server read times out

- **WHEN** a `BridgeClient` waits for a response that never arrives
- **THEN** the read returns a typed timeout error at the deadline rather than blocking forever

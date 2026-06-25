## MODIFIED Requirements

### Requirement: Hook CLI reads stdin and normalizes via adapter

`VibePetHooks` SHALL read a tool's native event JSON from stdin, select the appropriate `ToolAdapter`, and call `parseEvent(stdin:env:)` to normalize it into a `BridgeEnvelope`. The selected adapter SHALL use the supplied environment to attach a best-effort terminal jump target when terminal app, cwd, tty, or locator data is available. When the adapter returns `nil` (an event it does not care about) the CLI SHALL exit `0` without contacting the App.

#### Scenario: Notification event is normalized

- **WHEN** `VibePetHooks` receives a recognized notification event on stdin
- **THEN** it produces a `BridgeEnvelope` whose `content` is a non-response form (`.completion` or `.status`)

#### Scenario: Recognized event includes terminal jump target when available

- **WHEN** `VibePetHooks` receives a recognized event and the adapter can infer terminal jump-back data from `env`, cwd, tty, or an injected locator
- **THEN** the resulting `BridgeEnvelope.source.jumpTarget` contains that best-effort terminal target

#### Scenario: Ignored event exits cleanly

- **WHEN** the selected adapter's `parseEvent` returns `nil` for the stdin event
- **THEN** the CLI exits `0` without opening a socket connection

### Requirement: Hook CLI fails open when the App is unreachable

If the App is not running, the socket connection fails, the socket is broken, stdin input is malformed, or terminal jump-target capture fails, `VibePetHooks` SHALL fall back to the tool's native flow within ≤2s by emitting no output and exiting `0`, rather than hanging. Empty stdout is the tool-native `defer`/decline for both tools: Claude Code treats no JSON as a non-decision, and Codex treats no output (and any non-JSON) as "no decision → native approval flow".

#### Scenario: App not running yields prompt defer

- **WHEN** `VibePetHooks` runs with no App listening on the bridge socket
- **THEN** it emits no output, exits `0`, and returns within ≤2s

#### Scenario: Malformed stdin does not hang

- **WHEN** stdin contains input that cannot be parsed into a known event
- **THEN** the CLI defers to the native flow and exits without error to the tool

#### Scenario: Jump target capture failure does not hang

- **WHEN** terminal app inference, tty capture, or the focused-terminal locator fails while parsing an otherwise recognized hook event
- **THEN** the CLI still follows the normal envelope send or defer behavior and does not emit an error to the tool because jump-back precision failed

# VibePet

VibePet is a native macOS desktop pet for vibe coding workflows. An animated 2D pet lives on your desktop and acts as a visible approval surface for AI coding tools such as Claude Code and Codex: when an agent needs you to allow, deny, or answer something, VibePet surfaces it in a desktop bubble so you can act without hunting through terminal windows.

The pet also reflects ongoing session state (running a tool / waiting on you / done / failed), aggregates multiple sessions across terminals and tools, and lets you double-click any bubble to jump back to the terminal it came from. Pets use the standard Codex pet format (spritesheet) sourced in place from `~/.codex/pets/`, so VibePet hosts the wider Codex pet ecosystem.

VibePet is **local-first**: bridge transport, hook handling, pet sourcing, and rendering all run on the user's machine. No account, cloud sync, telemetry, or remote generation is required.

VibePet is a **GPL-3.0 open-source project**. The project currently does not use buyout, subscription, or in-app-purchase pricing.

See the [PRD](docs/VibePet-PRD.md) for product direction, architecture, and the code map.

## Current Status

The repository contains the Swift Package and the core implementation — normalized bridge models, Unix socket transport, the Claude Code / Codex tool adapters, the manifest-driven hook installer, configuration and asset persistence, and the floating pet window with bubbles — plus unit and end-to-end tests.

Work in progress is designed in [`docs/superpowers/specs/`](docs/superpowers/specs/): a persistent multi-session `SessionState` reducer with full hook-lifecycle coverage, the Codex spritesheet pet host, and terminal jump-back.

## Requirements

- macOS 14 or newer
- Xcode toolchain with Swift 6 support

## Quick Start

Build all package targets:

```sh
swift build
```

Run the test suite:

```sh
swift test
```

Launch the app:

```sh
swift run VibePetApp
```

Run the helper CLIs:

```sh
swift run VibePetHooks   # hook bridge helper (invoked by AI tools)
swift run VibePetSetup   # install / uninstall hook configuration
```

## Package Layout

```text
VibePetCore/    Shared, UI-independent logic:
                  Bridge/      normalized envelope + Unix socket transport + hook runtime
                  Adapters/    Claude Code / Codex tool adapters + risk classifier
                  Install/     manifest-driven hook installer (idempotent, precise uninstall)
                  Persistence/ config + pet asset storage
                  Geometry/    bubble anchoring, screen snap, sprite hit-mask
                  Pet/         pet state machine
VibePetApp/     macOS app: floating pet window, bubbles, menu bar, settings, bridge host
VibePetHooks/   CLI invoked by AI tool hooks
VibePetSetup/   CLI that installs/uninstalls hook configuration
Tests/          XCTest suite (core, app, setup, E2E) and fixtures
docs/           PRD (long-lived), current-version specs, and archived docs
openspec/       Executable specifications and archived changes
```

`VibePetCore` is intentionally UI-independent so it can be shared by the app, hook CLI, setup CLI, and tests. It must not import AppKit or SwiftUI.

## Architecture Overview

The hook ↔ app bridge uses a Unix domain socket (newline-delimited JSON) at `~/Library/Application Support/VibePet/bridge.sock`, with two channels:

1. `VibePetHooks` receives a tool event from Claude Code or Codex on stdin.
2. A `ToolAdapter` normalizes the tool-specific payload into a `BridgeEnvelope`.
3. `BridgeClient` sends it over the socket to `VibePetApp`'s `BridgeServer`.
4. The app renders the appropriate pet bubble:
   - **Decision channel (blocking):** approval / question events block the hook while the user acts in the bubble; the response is returned over the same connection and encoded back into the tool's expected stdout.
   - **Notification channel (non-blocking):** completion / status and lifecycle events fire-and-forget.
5. If anything fails — app not running, socket error, malformed input, or timeout — hooks **fail open** (`defer`) so the developer is never blocked.

The app holds a persistent `SessionState` reducer as the single source of truth; both channels feed it, and the pet's animation plus the menu-bar counts are derived from aggregated multi-session state. See the [PRD](docs/VibePet-PRD.md) §3 and the specs for details.

## Documentation Map

- [PRD (long-lived main document)](docs/VibePet-PRD.md) — product direction, architecture, code map, cross-cutting technical approach
- [Current-version specs](docs/superpowers/specs/) — session model + full hooks, Codex pet host, terminal jump-back
- [Archived docs](docs/archive/) — historical PRD, technical plan, task breakdown, code archive
- [Contributor guide](AGENTS.md) — repository conventions, commands, commit guidance
- [OpenSpec project specs](openspec/specs/)

Read the PRD for product intent and architecture; read the relevant spec in `docs/superpowers/specs/` before starting a new implementation slice.

## Testing

The project uses XCTest. Tests are split across `Tests/VibePetCoreTests/` (core logic), `Tests/VibePetAppTests/` (app layer), `Tests/VibePetSetupTests/` (installer), and `Tests/E2E/` (end-to-end approval/question/notification flows).

```sh
swift test
```

Notes:

- Installer/config-writer logic is verified by **unit tests only** — never real install smoke tests, since writes hit the real `~/.codex` / `~/.claude` even with `$HOME` overridden.
- A full `swift test` run may occasionally die with an intermittent SIGPIPE (signal 13) mid-run despite zero failures; re-run or use `--filter` rather than treating it as a regression.

## Privacy and Safety

VibePet is local-first: no account, cloud sync, telemetry, or remote generation service is required. Do not add network generation, telemetry, or upload paths without an explicit product change and user authorization design.

Hook and bridge changes must preserve **fail-open** behavior: if VibePet is not running, cannot connect, times out, or encounters malformed input, AI coding tools must fall back to their native approval flow instead of hanging.

## Acknowledgements

VibePet explicitly draws architectural and implementation inspiration from [open-vibe-island](https://github.com/Octane0411/open-vibe-island) by Octane0411 and its contributors. In particular, its package split, normalized hook and session models, Unix-socket bridge, hook installer patterns, and terminal jump-back approach informed VibePet's design. VibePet adapts those ideas to its own scope and models, replacing the notch-oriented interface with a desktop pet and a Codex spritesheet pet host.

## Contributing

Keep changes small and tied to a documented spec. Prefer adding or updating focused XCTest coverage for bridge encoding, adapter behavior, persistence, the installer, and fail-open paths. See [AGENTS.md](AGENTS.md) for repository conventions, commands, and commit guidance.

## License

VibePet is licensed under the [GNU General Public License v3.0](LICENSE).

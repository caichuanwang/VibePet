# VibePet

VibePet is a native macOS desktop pet for vibe coding workflows. The MVP goal is to turn a user-provided pet or character photo into a lightweight 2D desktop companion, then use that companion as a visible approval surface for AI coding tools such as Claude Code and Codex.

When an agent needs permission, VibePet will surface the request in a desktop bubble so the user can allow, deny, or defer without hunting through terminal windows. The project is designed to be local-first: photo cutout, bridge transport, and hook handling run on the user's machine.

## Current Status

The repository currently contains the Swift Package scaffold, core bridge models, Unix socket bridge infrastructure, configuration persistence, local cutout generation, asset storage, and unit tests for core behavior.

The app target is still a minimal runnable macOS window. The full floating pet UI, speech bubbles, hook installer behavior, and end-to-end Claude Code/Codex integrations are tracked in the project docs and OpenSpec files.

## Requirements

- macOS 14 or newer
- Xcode toolchain with Swift 6 support
- Apple Silicon recommended for Vision-based local cutout performance

## Quick Start

Build all package targets:

```sh
swift build
```

Run the test suite:

```sh
swift test
```

Launch the current app shell:

```sh
swift run VibePetApp
```

Run the helper CLIs:

```sh
swift run VibePetHooks
swift run VibePetSetup
swift run CutoutBenchmark
```

## Package Layout

```text
VibePetCore/        Shared models, bridge, generation, persistence, adapters
VibePetApp/         macOS app executable
VibePetHooks/       CLI invoked by AI tool hooks
VibePetSetup/       CLI intended to install/uninstall hook configuration
Tools/              Developer and benchmark tools
Tests/              XCTest suite and image fixtures
docs/               Product, technical, and MVP planning documents
openspec/           Executable specifications and archived changes
```

`VibePetCore` is intentionally UI-independent so it can be shared by the app, hook CLI, setup CLI, tests, and benchmark tooling.

## Architecture Overview

The intended MVP flow is:

1. `VibePetHooks` receives a tool event from Claude Code or Codex.
2. A `ToolAdapter` normalizes the tool-specific payload into a `BridgeEnvelope`.
3. `BridgeClient` sends newline-delimited JSON over a Unix domain socket.
4. `VibePetApp` receives the event through `BridgeServer` and renders the appropriate pet bubble.
5. For approval or question events, the app returns a `BridgeResponseEnvelope`; if anything fails, hooks should fail open rather than blocking the developer.

Local photo-to-pet generation is handled through `PetGenerator`, with `LocalCutoutGenerator` providing the MVP implementation using Apple's Vision foreground mask APIs.

## Documentation Map

- [Product requirements](docs/VibePet-PRD.md)
- [Technical implementation plan](docs/VibePet-技术实现方案.md)
- [MVP task breakdown](docs/VibePet-MVP-任务拆解.md)
- [Contributor guide](AGENTS.md)
- [OpenSpec project specs](openspec/specs/)

Read the PRD for product intent, the technical plan for architecture and tradeoffs, and the MVP task breakdown before starting a new implementation slice.

## Testing

The project uses XCTest. Core tests live in `Tests/VibePetCoreTests/`; image fixtures for local cutout behavior live in `Tests/Fixtures/photos/`.

Run all tests with:

```sh
swift test
```

Run the cutout benchmark tool when changing Vision generation, image post-processing, or asset persistence:

```sh
swift run CutoutBenchmark
```

## Privacy and Safety

The MVP is local-first. Photos should be processed on-device, and no account, cloud sync, telemetry, or remote generation service is required for the current scope.

Hook and bridge changes must preserve fail-open behavior: if VibePet is not running, cannot connect, times out, or encounters malformed input, AI coding tools should fall back to their native approval flow instead of hanging.

## Contributing

Keep changes small and tied to the documented milestones. Prefer adding or updating focused XCTest coverage for bridge encoding, adapter behavior, persistence, generation, and fail-open paths. See [AGENTS.md](AGENTS.md) for repository conventions, commands, and commit guidance.

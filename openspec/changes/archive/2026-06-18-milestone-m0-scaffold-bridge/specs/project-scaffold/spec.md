## ADDED Requirements

### Requirement: Swift Package with four targets

The project SHALL be a single Swift Package declaring four targets: `VibePetCore` (library), `VibePetApp`, `VibePetHooks`, and `VibePetSetup` (executables), targeting macOS 14+ and Swift 6.x.

#### Scenario: Package builds all targets

- **WHEN** a developer runs `swift build` at the repository root
- **THEN** the build succeeds and produces artifacts for all four targets

#### Scenario: Core library is UI-independent

- **WHEN** `VibePetCore` is compiled
- **THEN** it links no UI framework (AppKit/SwiftUI) and can be imported by `VibePetHooks` and `VibePetSetup`

### Requirement: Minimal runnable App window

The `VibePetApp` target SHALL launch and present a minimal window without requiring any pet asset or bridge connection.

#### Scenario: App launches an empty window

- **WHEN** `VibePetApp` is run
- **THEN** a minimal window appears and the process stays alive without crashing

### Requirement: Test scaffold runs under CI

The package SHALL include a `Tests/` directory wired so that `swift test` runs successfully even when no test assertions exist yet.

#### Scenario: Test command succeeds on empty suite

- **WHEN** a developer runs `swift build && swift test`
- **THEN** both commands exit with status 0

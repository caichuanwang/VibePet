# error-presentation Specification

## Purpose

Define a unified, UI-framework-independent error presenter that maps pet import, installation, and bridge errors to readable messages and suggested actions for consumption across the app's surfaces.

## Requirements

### Requirement: Unified error presentation maps errors to readable guidance

`VibePetApp` SHALL provide an `ErrorPresenter` that maps Codex pet package import, installation, and bridge errors to a readable message and a suggested action. The mapping logic SHALL be UI-framework-independent (testable without AppKit/SwiftUI) and consumed by the import panel, settings page, and bubbles.

#### Scenario: Invalid pet package explains the package contract

- **WHEN** importing a pet fails because `pet.json` or the spritesheet is missing or invalid
- **THEN** the presenter yields a readable message and guidance to provide a Codex pet zip or folder

#### Scenario: Codex needs-trust maps to /hooks guidance

- **WHEN** an install/status result reports Codex `installedNeedsTrust`
- **THEN** the presenter yields a message guiding the user to confirm the hook in Codex `/hooks`

#### Scenario: Install failure yields a readable cause and rollback hint

- **WHEN** an install operation fails
- **THEN** the presenter yields a readable cause and a hint that the original config was backed up / can be restored

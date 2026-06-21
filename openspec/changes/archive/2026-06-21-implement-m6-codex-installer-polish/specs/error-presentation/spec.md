## ADDED Requirements

### Requirement: Unified error presentation maps errors to readable guidance

`VibePetApp` SHALL provide an `ErrorPresenter` that maps generation, installation, and bridge errors to a readable message and a suggested action, per the technical design §7 error table. The mapping logic SHALL be UI-framework-independent (testable without AppKit/SwiftUI) and consumed by the import panel, settings page, and bubbles.

#### Scenario: No-subject generation error suggests another photo

- **WHEN** generation fails with `GenError.noSubject`
- **THEN** the presenter yields a readable message and a "try another photo / retry" suggested action

#### Scenario: Codex needs-trust maps to /hooks guidance

- **WHEN** an install/status result reports Codex `installedNeedsTrust`
- **THEN** the presenter yields a message guiding the user to confirm the hook in Codex `/hooks`

#### Scenario: Install failure yields a readable cause and rollback hint

- **WHEN** an install operation fails
- **THEN** the presenter yields a readable cause and a hint that the original config was backed up / can be restored

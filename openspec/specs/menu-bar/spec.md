# menu-bar Specification

## Purpose
TBD - created by archiving change implement-m2-desktop-pet-window. Update Purpose after archive.
## Requirements
### Requirement: Menu bar status item with core entries

`VibePetApp` SHALL provide an `NSStatusItem` whose menu contains entries for: show/hide pet, switch pet, import pet, open settings, and quit (technical design §5.4). Each entry SHALL be wired to the corresponding behavior.

#### Scenario: Menu exposes all core entries

- **WHEN** the user opens the menu bar status item
- **THEN** the menu lists show/hide pet, switch pet, import pet, open settings, and quit

#### Scenario: Show/hide toggles pet window visibility

- **WHEN** the user selects the show/hide pet entry
- **THEN** the pet window visibility toggles accordingly

#### Scenario: Import opens the import panel

- **WHEN** the user selects "import pet"
- **THEN** the Codex pet import panel (`PetImportPanel`) is presented

#### Scenario: Switch pet changes the active pet

- **WHEN** the user selects a different pet under "switch pet"
- **THEN** `config.activePetID` is updated and the displayed pet changes to that asset

#### Scenario: Quit terminates the app

- **WHEN** the user selects quit
- **THEN** the application terminates

### Requirement: Menu bar shows multi-session aggregate counts

`VibePetApp`'s `NSStatusItem` SHALL surface multi-session aggregation derived from `SessionState`: the count of visible/active sessions and the count of sessions that need attention (waiting for approval or answer). These counts SHALL update as `SessionState` changes and SHALL be pure derivations (no per-envelope bespoke state).

#### Scenario: Menu bar reflects active and needs-attention counts

- **WHEN** `SessionState` holds multiple sessions, some running and some waiting for approval/answer
- **THEN** the menu bar shows the visible/active session count and a separate needs-attention count matching `SessionState`'s `visibleSessions` and `attentionCount`

#### Scenario: Counts drop when sessions complete or are reaped

- **WHEN** sessions complete or are reaped by the process-liveness sweep
- **THEN** the menu bar's active and needs-attention counts decrease accordingly

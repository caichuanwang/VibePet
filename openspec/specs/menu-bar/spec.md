# menu-bar Specification

## Purpose
TBD - created by archiving change implement-m2-desktop-pet-window. Update Purpose after archive.
## Requirements
### Requirement: Menu bar status item with core entries

`VibePetApp` SHALL provide an `NSStatusItem` whose menu contains entries for: show/hide pet, switch pet, import new photo, open settings, and quit (technical design §5.4). Each entry SHALL be wired to the corresponding behavior.

#### Scenario: Menu exposes all core entries

- **WHEN** the user opens the menu bar status item
- **THEN** the menu lists show/hide pet, switch pet, import new photo, open settings, and quit

#### Scenario: Show/hide toggles pet window visibility

- **WHEN** the user selects the show/hide pet entry
- **THEN** the pet window visibility toggles accordingly

#### Scenario: Import opens the import panel

- **WHEN** the user selects "import new photo"
- **THEN** the import → generate panel (`PetImportPanel`) is presented

#### Scenario: Switch pet changes the active pet

- **WHEN** the user selects a different pet under "switch pet"
- **THEN** `config.activePetID` is updated and the displayed pet changes to that asset

#### Scenario: Quit terminates the app

- **WHEN** the user selects quit
- **THEN** the application terminates


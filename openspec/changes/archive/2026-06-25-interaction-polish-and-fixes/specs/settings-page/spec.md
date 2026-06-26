## MODIFIED Requirements

### Requirement: Settings page exposes runtime preferences

The settings page SHALL let the user configure launch-at-login and active Codex pet selection, persisting them via `app-configuration`. It SHALL provide an import action for Codex pet zip files and folders. The settings page SHALL NOT expose a decision-timeout control, since 0.3 removes the App-side decision timeout (decisions wait until the user acts).

#### Scenario: No decision-timeout control is shown

- **WHEN** the user opens settings
- **THEN** there is no decision-timeout slider or field anywhere in the page

#### Scenario: Launch-at-login toggles

- **WHEN** the user toggles launch-at-login
- **THEN** the preference is persisted and reflected on next launch

#### Scenario: Pet selection persists

- **WHEN** the user selects a pet in settings
- **THEN** `config.activePetID` is updated to that pet slug and the desktop pet refreshes

#### Scenario: Import action is available

- **WHEN** the user opens settings
- **THEN** an import pet action is available for zip files and folders

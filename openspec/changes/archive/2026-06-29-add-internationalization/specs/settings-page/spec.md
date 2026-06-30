## MODIFIED Requirements

### Requirement: Settings page exposes runtime preferences

The settings page SHALL let the user configure launch-at-login, app language, and active Codex pet selection, persisting app-owned preferences via `app-configuration`. The language control SHALL offer Simplified Chinese and English using stable option labels `简体中文` and `English`, SHALL reflect the currently configured language when settings opens, and SHALL persist changes so all app-owned visible UI text uses the selected language. It SHALL provide an import action for Codex pet zip files and folders. The settings page SHALL NOT expose a decision-timeout control, since 0.3 removes the App-side decision timeout (decisions wait until the user acts).

#### Scenario: No decision-timeout control is shown

- **WHEN** the user opens settings
- **THEN** there is no decision-timeout slider or field anywhere in the page

#### Scenario: Launch-at-login toggles

- **WHEN** the user toggles launch-at-login
- **THEN** the preference is persisted and reflected on next launch

#### Scenario: Language selection reflects current config

- **WHEN** the user opens settings
- **THEN** the language selector shows the language stored in `AppConfig`

#### Scenario: Language selection persists and updates UI

- **WHEN** the user changes the language selector to Simplified Chinese or English
- **THEN** `config.language` is updated and app-owned visible UI text uses the selected language

#### Scenario: Pet selection persists

- **WHEN** the user selects a pet in settings
- **THEN** `config.activePetID` is updated to that pet slug and the desktop pet refreshes

#### Scenario: Import action is available

- **WHEN** the user opens settings
- **THEN** an import pet action is available for zip files and folders

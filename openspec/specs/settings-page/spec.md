# settings-page Specification

## Purpose

Define the app settings page: per-tool hook enablement and install controls, runtime preferences, and pet switching/import.

## Requirements

### Requirement: Settings page exposes tool enablement and install controls

`VibePetApp` SHALL provide a settings page that lets the user enable tools (Claude Code / Codex) and trigger one-click install/uninstall of hooks via `VibePetSetup`. For each tool it SHALL display the installation state, binary version, and trust state derived from the install manifest/status. When Codex is `installedNeedsTrust`, or when the managed Codex hook set has changed and requires a reinstall, the page SHALL show readable `/hooks` trust or reinstall guidance.

#### Scenario: Per-tool install state is displayed

- **WHEN** the settings page opens
- **THEN** each tool shows its install state, binary version, and trust state from `VibePetSetup status`

#### Scenario: One-click install/uninstall

- **WHEN** the user clicks install or uninstall for a tool
- **THEN** the corresponding `VibePetSetup` action runs and the displayed state refreshes

#### Scenario: Codex needs-trust shows /hooks guidance

- **WHEN** Codex is in `installedNeedsTrust`
- **THEN** the page shows guidance to confirm the hook in Codex `/hooks`

#### Scenario: Managed hook drift prompts reinstall

- **WHEN** a previously installed tool is missing a managed hook entry required by the current app version
- **THEN** the page shows readable guidance that the managed hooks changed and a reinstall/repair is needed

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

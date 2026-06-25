# settings-page Specification

## Purpose

Define the app settings page: per-tool hook enablement and install controls, runtime preferences, and pet switching/import.

## Requirements

### Requirement: Settings page exposes tool enablement and install controls

`VibePetApp` SHALL provide a settings page that lets the user enable tools (Claude Code / Codex) and trigger one-click install/uninstall of hooks via `VibePetSetup`. For each tool it SHALL display the installation state, binary version, and trust state derived from the install manifest/status. When Codex is `installedNeedsTrust`, the page SHALL show readable `/hooks` trust guidance.

#### Scenario: Per-tool install state is displayed

- **WHEN** the settings page opens
- **THEN** each tool shows its install state, binary version, and trust state from `VibePetSetup status`

#### Scenario: One-click install/uninstall

- **WHEN** the user clicks install or uninstall for a tool
- **THEN** the corresponding `VibePetSetup` action runs and the displayed state refreshes

#### Scenario: Codex needs-trust shows /hooks guidance

- **WHEN** Codex is in `installedNeedsTrust`
- **THEN** the page shows guidance to confirm the hook in Codex `/hooks`

### Requirement: Settings page exposes runtime preferences

The settings page SHALL let the user configure the decision timeout, launch-at-login, and active Codex pet selection, persisting them via `app-configuration`. It SHALL provide an import action for Codex pet zip files and folders.

#### Scenario: Decision timeout persists

- **WHEN** the user changes the decision timeout in settings
- **THEN** the new value is persisted in config and used by subsequent decisions

#### Scenario: Launch-at-login toggles

- **WHEN** the user toggles launch-at-login
- **THEN** the preference is persisted and reflected on next launch

#### Scenario: Pet selection persists

- **WHEN** the user selects a pet in settings
- **THEN** `config.activePetID` is updated to that pet slug and the desktop pet refreshes

#### Scenario: Import action is available

- **WHEN** the user opens settings
- **THEN** an import pet action is available for zip files and folders

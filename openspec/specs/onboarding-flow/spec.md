# onboarding-flow Specification

## Purpose
TBD - created by archiving change implement-m2-desktop-pet-window. Update Purpose after archive.
## Requirements
### Requirement: First-launch onboarding flow

`VibePetApp` SHALL provide a first-launch onboarding that guides the user, in order, through ① welcome, ② choose or import a Codex pet, and ③ install hooks. Step ② SHALL list aggregated pets from `PetAssetStore`; if none exist, it SHALL show a readable skippable empty state that points to `~/.codex/pets/` and direct zip/folder import. Step ③ SHALL be functional: it SHALL list only the tools detected on the machine (Claude Code shown when `~/.claude/` exists; Codex shown when its config exists), show each tool's installation state, allow installing per tool and skipping with "later", and show a readable hint when no tool is detected. When Codex is written but not yet trusted, step ③ SHALL surface `/hooks` trust guidance. Step ③ SHALL never block onboarding completion.

#### Scenario: Welcome then choose pet then install on first launch

- **WHEN** the app launches for the first time
- **THEN** it shows welcome, then a choose/import pet step, then the install-hooks step

#### Scenario: Pet selection persists

- **WHEN** the user selects an available pet during onboarding
- **THEN** `config.activePetID` is set to that pet slug

#### Scenario: Install step lists only detected tools

- **WHEN** onboarding reaches the install-hooks step
- **THEN** it lists only tools detected on the machine, each with its installation state, and lets the user install or skip

#### Scenario: No detected tool shows a skippable hint

- **WHEN** no supported tool configuration is detected at the install-hooks step
- **THEN** it shows a readable hint and lets the user continue without installing

#### Scenario: Codex written-but-untrusted shows /hooks guidance

- **WHEN** the user installs Codex hooks during onboarding and trust is pending
- **THEN** the step surfaces guidance to confirm the hook in Codex `/hooks`

### Requirement: Onboarding appears only once

Onboarding SHALL appear only on first launch. Completion SHALL be recorded via the `app-configuration` onboarding-completed marker so that subsequent launches go straight to the desktop pet without showing onboarding.

#### Scenario: Subsequent launches skip onboarding

- **WHEN** the onboarding-completed marker is set and the app launches again
- **THEN** onboarding is not shown and the app proceeds directly to the desktop pet

# onboarding-flow Specification

## Purpose
TBD - created by archiving change implement-m2-desktop-pet-window. Update Purpose after archive.
## Requirements
### Requirement: First-launch onboarding flow

`VibePetApp` SHALL provide a first-launch onboarding that guides the user, in order, through ① welcome and ② generate pet (reusing `PetImportPanel`). On completion the generated pet SHALL land on the desktop and enter idle standby (technical design §5.4, PRD US-0①②). Step ③ (install hooks) SHALL be present only as a placeholder and is wired up in M6.

#### Scenario: Welcome then generate on first launch

- **WHEN** the app launches for the first time
- **THEN** it shows the welcome step, then the generate-pet step backed by `PetImportPanel`

#### Scenario: Completion places the pet in idle

- **WHEN** the user completes the generate-pet step of onboarding
- **THEN** the pet is placed on the desktop and enters idle standby

#### Scenario: Step three is a placeholder

- **WHEN** the onboarding reaches the install-hooks step in M2
- **THEN** it shows a placeholder (not yet functional) and does not block completion

### Requirement: Onboarding appears only once

Onboarding SHALL appear only on first launch. Completion SHALL be recorded via the `app-configuration` onboarding-completed marker so that subsequent launches go straight to the desktop pet without showing onboarding.

#### Scenario: Subsequent launches skip onboarding

- **WHEN** the onboarding-completed marker is set and the app launches again
- **THEN** onboarding is not shown and the app proceeds directly to the desktop pet


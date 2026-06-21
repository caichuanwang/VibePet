## MODIFIED Requirements

### Requirement: First-launch onboarding flow

`VibePetApp` SHALL provide a first-launch onboarding that guides the user, in order, through ① welcome, ② generate pet (reusing `PetImportPanel`), and ③ install hooks. On completion of step ② the generated pet SHALL land on the desktop and enter idle standby (technical design §5.4, PRD US-0①②③). Step ③ SHALL be functional: it SHALL list only the tools detected on the machine (Claude Code shown when `~/.claude/` exists; Codex shown when its config exists), show each tool's installation state, allow installing per tool and skipping with "later", and show a readable hint when no tool is detected. When Codex is written but not yet trusted, step ③ SHALL surface `/hooks` trust guidance. Step ③ SHALL never block onboarding completion.

#### Scenario: Welcome then generate then install on first launch

- **WHEN** the app launches for the first time
- **THEN** it shows welcome, then the generate-pet step backed by `PetImportPanel`, then the install-hooks step

#### Scenario: Completion places the pet in idle

- **WHEN** the user completes the generate-pet step of onboarding
- **THEN** the pet is placed on the desktop and enters idle standby

#### Scenario: Install step lists only detected tools

- **WHEN** onboarding reaches the install-hooks step
- **THEN** it lists only tools detected on the machine, each with its installation state, and lets the user install or skip

#### Scenario: No detected tool shows a skippable hint

- **WHEN** no supported tool configuration is detected at the install-hooks step
- **THEN** it shows a readable hint and lets the user continue without installing

#### Scenario: Codex written-but-untrusted shows /hooks guidance

- **WHEN** the user installs Codex hooks during onboarding and trust is pending
- **THEN** the step surfaces guidance to confirm the hook in Codex `/hooks`

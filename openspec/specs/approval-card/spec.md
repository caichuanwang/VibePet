# approval-card Specification

## Purpose
TBD - created by archiving change implement-m4-approval-loop. Update Purpose after archive.
## Requirements
### Requirement: Three-section approval card layout

`VibePetApp` SHALL provide an `ApprovalCard` that renders `.approval` content in three sections per §5.3.3: a header showing the source (`tool · projectName · sessionShortId`) and a risk indicator, a body rendering the `ActionPreview` compactly, and a footer with a countdown and action buttons.

#### Scenario: Approval renders header, body, and footer

- **WHEN** an `.approval` envelope is presented in the `decide` state
- **THEN** the card shows the source + risk header, the `ActionPreview` body, and a footer with countdown and buttons

#### Scenario: ActionPreview renders compactly per variant

- **WHEN** the approval carries an `ActionPreview` (`command` / `fileChange` / `fileRead` / `network` / `generic`)
- **THEN** the body renders that variant in a compact form appropriate to its kind

### Requirement: Risk-driven styling and default focus

`ApprovalCard` SHALL set coloring and default keyboard focus by `risk`. `.high` SHALL default focus to "Deny" and SHALL require an explicit click/confirmation to allow; lower-risk levels MAY style differently but allowing SHALL still require an explicit action. Dangerous commands SHALL be highlighted (red), and a command body longer than 3 lines SHALL be truncated with the remainder elided.

#### Scenario: High risk defaults focus to deny

- **WHEN** an `.approval` with `risk == .high` is presented
- **THEN** the default focus is on "Deny" and allowing requires an explicit click

#### Scenario: Dangerous command is highlighted and truncated

- **WHEN** the command preview is flagged dangerous and exceeds 3 lines
- **THEN** it is shown in alert (red) styling and truncated past 3 lines

### Requirement: Action buttons and keyboard shortcuts

`ApprovalCard` SHALL provide a Deny button (esc), an Allow once button (⌘↩), and an Always allow button that SHALL be shown only when `alwaysAllow != nil`.

#### Scenario: Deny and allow-once expose shortcuts

- **WHEN** the card is focused
- **THEN** esc triggers Deny and ⌘↩ triggers Allow once

#### Scenario: Always-allow hidden when option absent

- **WHEN** the approval's `alwaysAllow` is `nil`
- **THEN** the card does not show an "Always allow" button

### Requirement: Approval countdown fails open

`ApprovalCard` SHALL display a countdown to the configured decision deadline; when it reaches zero the card SHALL fail open (defer) and surface a readable hint that the action was deferred to the native flow.

#### Scenario: Countdown reaching zero defers

- **WHEN** the approval countdown reaches zero with no user decision
- **THEN** the card defers (fail-open) and shows a readable timeout hint


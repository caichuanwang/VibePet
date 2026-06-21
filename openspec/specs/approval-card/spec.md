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

### Requirement: Terminal-approval downgrade form

`ApprovalCard` SHALL, when the presented `.approval` content has `requiresTerminalApproval == true`, hide the Allow/Deny/Always-allow buttons and instead render a single "Handle in terminal" button with a readable hint that the request must be handled in the tool's native terminal flow. In the MVP this button SHALL focus/copy the hint only (real jump-back is deferred to v1.1). The header (source + risk) and compact `ActionPreview` body SHALL still render. Dismissing or activating it SHALL resolve the request as a `defer` so the tool falls back to its native flow.

#### Scenario: Terminal-approval hides allow/deny

- **WHEN** an `.approval` with `requiresTerminalApproval == true` is presented
- **THEN** the card hides Allow/Deny/Always-allow and shows a single "Handle in terminal" button with a hint

#### Scenario: Header and body still render in terminal form

- **WHEN** the terminal-approval form is shown
- **THEN** the source + risk header and the compact `ActionPreview` body are still rendered

#### Scenario: Resolving terminal approval defers to native flow

- **WHEN** the user activates "Handle in terminal" or the card is dismissed
- **THEN** the request resolves as a `defer` so the tool uses its native approval flow


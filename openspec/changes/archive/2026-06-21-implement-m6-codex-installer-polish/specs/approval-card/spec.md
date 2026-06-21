## ADDED Requirements

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

## MODIFIED Requirements

### Requirement: Three-section approval card layout

`VibePetApp` SHALL provide an `ApprovalCard` that renders `.approval` content in three sections per §5.3.3: a header showing the source (`tool · projectName · sessionShortId`) and a risk indicator, a body rendering the `ActionPreview` compactly, and a footer with a countdown and action buttons. When the source carries a jump target, double-clicking the non-control card body SHALL invoke the injected terminal jump action once without changing the footer action behavior.

#### Scenario: Approval renders header, body, and footer

- **WHEN** an `.approval` envelope is presented in the `decide` state
- **THEN** the card shows the source + risk header, the `ActionPreview` body, and a footer with countdown and buttons

#### Scenario: ActionPreview renders compactly per variant

- **WHEN** the approval carries an `ActionPreview` (`command` / `fileChange` / `fileRead` / `network` / `generic`)
- **THEN** the body renders that variant in a compact form appropriate to its kind

#### Scenario: Double-click approval body jumps back

- **WHEN** an approval card with a source jump target is double-clicked on its body outside footer controls
- **THEN** the injected terminal jump action is invoked once with that jump target

### Requirement: Terminal-approval downgrade form

`ApprovalCard` SHALL, when the presented `.approval` content has `requiresTerminalApproval == true`, hide the Allow/Deny/Always-allow buttons and instead render a single "Handle in terminal" button with a readable hint that the request must be handled in the tool's native terminal flow. In this form the button SHALL attempt terminal jump-back when a source jump target exists, then resolve the request as a `defer` so the tool falls back to its native flow. The header (source + risk) and compact `ActionPreview` body SHALL still render. Dismissing it SHALL resolve the request as a `defer` so the tool falls back to its native approval flow.

#### Scenario: Terminal-approval hides allow/deny

- **WHEN** an `.approval` with `requiresTerminalApproval == true` is presented
- **THEN** the card hides Allow/Deny/Always-allow and shows a single "Handle in terminal" button with a hint

#### Scenario: Header and body still render in terminal form

- **WHEN** the terminal-approval form is shown
- **THEN** the source + risk header and the compact `ActionPreview` body are still rendered

#### Scenario: Handle in terminal jumps and defers

- **WHEN** the user activates "Handle in terminal" on a terminal-approval card with a source jump target
- **THEN** the card invokes the terminal jump action and resolves as a `defer` so the tool uses its native approval flow

#### Scenario: Resolving terminal approval without a jump target defers to native flow

- **WHEN** the user activates "Handle in terminal" or dismisses the terminal-approval card and no jump target is available
- **THEN** the request resolves as a `defer` so the tool uses its native approval flow

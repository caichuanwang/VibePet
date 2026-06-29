## MODIFIED Requirements

### Requirement: Three-section approval card layout

`VibePetApp` SHALL provide an `ApprovalCard` that renders `.approval` content as a decision-first card: a header showing the source (`tool · projectName · sessionShortId`) and a risk indicator, a body focused on the compact `ActionPreview`, and a footer with a left-side terminal jump affordance plus right-side decision buttons. The approval body SHALL NOT render user prompt or agent output conversation context; the requested action preview is the primary content. When the source carries a jump target, double-clicking the non-control card body SHALL invoke the injected terminal jump action once without changing the footer action behavior.

#### Scenario: Approval renders source, action preview, and footer

- **WHEN** an `.approval` envelope is presented in the `decide` state
- **THEN** the card shows the source + risk header, the `ActionPreview` body, and a footer with terminal and decision controls

#### Scenario: Approval omits conversation context

- **WHEN** an approval is presented while session user prompt or agent summary context exists
- **THEN** the approval body does not show user/agent conversation rows and instead emphasizes the requested action preview

#### Scenario: ActionPreview renders compactly per variant

- **WHEN** the approval carries an `ActionPreview` (`command` / `fileChange` / `fileRead` / `network` / `generic`)
- **THEN** the body renders that variant in a compact form appropriate to its kind

#### Scenario: Double-click approval body jumps back

- **WHEN** an approval card with a source jump target is double-clicked on its body outside footer controls
- **THEN** the injected terminal jump action is invoked once with that jump target

### Requirement: Action buttons and keyboard shortcuts

`ApprovalCard` SHALL provide a left-side "Back to terminal" button, a Deny button (esc), an Allow once button (⌘↩), and an Always allow button that SHALL be shown only when `alwaysAllow != nil`. Activating "Back to terminal" in a normal approval SHALL invoke jump-back when a source jump target exists and SHALL NOT resolve the approval request. Deny, Allow once, and Always allow SHALL resolve exactly once with their existing `BridgeResponse` meanings.

#### Scenario: Back to terminal does not resolve normal approval

- **WHEN** a normal approval card has a jump target and the user activates "Back to terminal"
- **THEN** the card invokes the injected terminal jump action and leaves the approval pending

#### Scenario: Deny and allow-once expose shortcuts

- **WHEN** the card is focused
- **THEN** esc triggers Deny and ⌘↩ triggers Allow once

#### Scenario: Always-allow hidden when option absent

- **WHEN** the approval's `alwaysAllow` is `nil`
- **THEN** the card does not show an "Always allow" button

#### Scenario: Always-allow resolves with scope hint

- **WHEN** the approval's `alwaysAllow` is present and the user activates the Always allow button
- **THEN** the card resolves exactly once with an allow-always approval response preserving the option's scope hint

### Requirement: Terminal-approval downgrade form

`ApprovalCard` SHALL, when the presented `.approval` content has `requiresTerminalApproval == true`, hide the Allow/Deny/Always-allow buttons and instead render a single "Back to terminal" or "Handle in terminal" affordance with a readable hint that the request must be handled in the tool's native terminal flow. In this form the button SHALL attempt terminal jump-back when a source jump target exists, then resolve the request as a `defer` so the tool falls back to its native flow. The header (source + risk) and compact `ActionPreview` body SHALL still render. Dismissing it SHALL resolve the request as a `defer` so the tool falls back to its native approval flow.

#### Scenario: Terminal-approval hides allow/deny

- **WHEN** an `.approval` with `requiresTerminalApproval == true` is presented
- **THEN** the card hides Allow/Deny/Always-allow and shows a terminal-handling affordance with a hint

#### Scenario: Header and body still render in terminal form

- **WHEN** the terminal-approval form is shown
- **THEN** the source + risk header and the compact `ActionPreview` body are still rendered

#### Scenario: Handle in terminal jumps and defers

- **WHEN** the user activates the terminal-handling affordance on a terminal-approval card with a source jump target
- **THEN** the card invokes the terminal jump action and resolves as a `defer` so the tool uses its native approval flow

#### Scenario: Resolving terminal approval without a jump target defers to native flow

- **WHEN** the user activates the terminal-handling affordance or dismisses the terminal-approval card and no jump target is available
- **THEN** the request resolves as a `defer` so the tool uses its native approval flow

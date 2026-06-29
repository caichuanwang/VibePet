## MODIFIED Requirements

### Requirement: Bubble and card jump interaction

All visible bubble/card body surfaces for `.approval`, `.question`, `.completion`, and `.status` content SHALL support double-click jump-back when `SourceInfo.jumpTarget` is present. Interactive approval and question cards SHALL also expose an explicit "Back to terminal" control when a source jump target is available or when the terminal fallback is useful. The jump gesture and explicit control SHALL be scoped so action buttons, option controls, freeform fields, navigation buttons, submit controls, dismiss behavior, hover pause, countdowns, and keyboard shortcuts continue to behave as specified. A normal approval/question "Back to terminal" action SHALL invoke jump-back only and SHALL NOT resolve the pending request; terminal-only approval downgrade remains the exception and SHALL resolve as `defer`.

#### Scenario: Notification bubble double-click jumps once

- **WHEN** a status or completion bubble with a jump target is double-clicked on its body
- **THEN** the injected jump action is invoked exactly once with the source jump target

#### Scenario: Approval controls retain their behavior

- **WHEN** an approval card has a jump target and the user clicks Allow, Deny, Always allow, or a keyboard shortcut
- **THEN** the approval decision behavior remains unchanged and is not replaced by the jump gesture

#### Scenario: Normal approval back-to-terminal leaves request pending

- **WHEN** a normal approval card has a jump target and the user clicks Back to terminal
- **THEN** the injected jump action is invoked and the pending request remains unresolved

#### Scenario: Terminal-only approval back-to-terminal defers

- **WHEN** a terminal-only approval downgrade card is shown and the user clicks the terminal handling control
- **THEN** the injected jump action is attempted and the request resolves as `defer`

#### Scenario: Question controls retain their behavior

- **WHEN** a question card has a jump target and the user selects options, types freeform text, navigates between questions, or submits
- **THEN** the question answer behavior remains unchanged and is not replaced by the jump gesture

#### Scenario: Normal question back-to-terminal leaves request pending

- **WHEN** a question card has a jump target and the user clicks Back to terminal
- **THEN** the injected jump action is invoked and the pending question remains unresolved

#### Scenario: Missing jump target is a no-op

- **WHEN** any bubble or card is double-clicked but its source has no jump target
- **THEN** no jump action is invoked and no error is presented

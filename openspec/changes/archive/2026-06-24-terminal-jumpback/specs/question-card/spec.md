## MODIFIED Requirements

### Requirement: Question card renders each question item

`QuestionCard` SHALL render a `.question` content's `QuestionContent` by showing the `title` (when non-empty) and, for each `QuestionItem`, its `prompt` followed by its `options`. Each `QuestionOption` SHALL display its `label` and, when present, its `detail` on a secondary muted line. The card SHALL also show the source header. When the source carries a jump target, double-clicking the non-control card body SHALL invoke the injected terminal jump action once without changing option, freeform input, submit, or countdown behavior.

#### Scenario: Multi-question content renders every item

- **WHEN** `QuestionCard` is given a `QuestionContent` with one or more `QuestionItem`
- **THEN** it renders each item's `prompt` and all `options` with each option's `label` and `detail`

#### Scenario: Double-click question body jumps back

- **WHEN** a question card with a source jump target is double-clicked on its body outside option controls, text fields, and submit controls
- **THEN** the injected terminal jump action is invoked once with that jump target

### Requirement: Submit collects a QuestionAnswer keyed by header

`QuestionCard` SHALL provide a submit affordance (`⌘↩`) that resolves the card with `.question(QuestionAnswer)` whose `answers` map each item's `header` to one string value — single-select as the chosen label, multi-select as the chosen labels joined with `", "`, and a freeform ("其他") choice contributing the typed text in place of its label (matching how Claude Code's CLI inlines free text into the answer value). Submit SHALL be disabled until at least one question is answered. The terminal jump gesture SHALL NOT intercept submit controls or keyboard submission.

#### Scenario: Submit resolves with selected answers

- **WHEN** the user has made a selection and triggers submit
- **THEN** `QuestionCard` resolves with `.question(QuestionAnswer)` whose `answers` is keyed by each item's `header` and reflects the selection

#### Scenario: Submit is not replaced by jump gesture

- **WHEN** a question card has a source jump target and the user activates submit with the button or `⌘↩`
- **THEN** the card resolves with the question answer and does not invoke jump-back instead of submission

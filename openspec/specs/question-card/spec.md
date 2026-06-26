## Purpose

Define how `QuestionCard` renders `.question` content and collects a `QuestionAnswer` from the user within the `decide` state.

## Requirements

### Requirement: Question card renders each question item

`QuestionCard` SHALL render a `.question` content's `QuestionContent` by showing the `title` (when non-empty) and, for each `QuestionItem`, its `prompt` followed by its `options`. Each `QuestionOption` SHALL display its `label` and, when present, its `detail` on a secondary muted line. The card SHALL also show the source header. When the source carries a jump target, double-clicking the non-control card body SHALL invoke the injected terminal jump action once without changing option, freeform input, or submit behavior.

#### Scenario: Multi-question content renders every item

- **WHEN** `QuestionCard` is given a `QuestionContent` with one or more `QuestionItem`
- **THEN** it renders each item's `prompt` and all `options` with each option's `label` and `detail`

#### Scenario: Double-click question body jumps back

- **WHEN** a question card with a source jump target is double-clicked on its body outside option controls, text fields, and submit controls
- **THEN** the injected terminal jump action is invoked once with that jump target

### Requirement: Single-select and multi-select rendering

`QuestionCard` SHALL render an item whose `multiSelect` is `false` with single-choice controls (radio) such that selecting one option replaces any prior selection, and an item whose `multiSelect` is `true` with multi-choice controls (checkbox) such that multiple options can be selected.

#### Scenario: Single-select keeps one option

- **WHEN** an item with `multiSelect == false` is rendered and the user selects a second option
- **THEN** only the most recently selected option remains selected

#### Scenario: Multi-select keeps several options

- **WHEN** an item with `multiSelect == true` is rendered and the user selects two options
- **THEN** both options remain selected

### Requirement: Freeform option expands a text field

`QuestionCard` SHALL, when a selected `QuestionOption` has `allowsFreeform == true` (the synthetic "其他" choice the adapter appends to every question), present an editable text field for that option. The typed text SHALL contribute to the answer value in place of the option's label.

#### Scenario: Selecting a freeform option reveals a text field

- **WHEN** the user selects the "其他" option whose `allowsFreeform` is `true`
- **THEN** `QuestionCard` shows a text field bound to that option, and the typed text becomes the answer value under the item's `header`

#### Scenario: Submit waits for freeform text

- **WHEN** a freeform option is selected but its text field is empty
- **THEN** submit is disabled until the user types text (or deselects the option)

### Requirement: Submit collects a QuestionAnswer keyed by header

`QuestionCard` SHALL provide a submit affordance (`⌘↩`) that resolves the card with `.question(QuestionAnswer)` whose `answers` map each item's `header` to one string value — single-select as the chosen label, multi-select as the chosen labels joined with `", "`, and a freeform ("其他") choice contributing the typed text in place of its label (matching how Claude Code's CLI inlines free text into the answer value). Submit SHALL be disabled until every question in the card is answered: each question MUST have at least one selected option, and any selected freeform ("其他") option MUST carry non-empty text, so a multi-topic `AskUserQuestion` can never be submitted with some topics left unanswered. The terminal jump gesture SHALL NOT intercept submit controls or keyboard submission.

#### Scenario: Submit resolves with selected answers

- **WHEN** the user has answered every question and triggers submit
- **THEN** `QuestionCard` resolves with `.question(QuestionAnswer)` whose `answers` is keyed by each item's `header` and reflects every question's selection

#### Scenario: Submit is disabled until all questions are answered

- **WHEN** a card presents multiple questions and the user has answered only some of them
- **THEN** the submit affordance remains disabled until each remaining question has a valid selection

#### Scenario: Freeform selection requires text before submit

- **WHEN** a selected option is the freeform ("其他") choice with empty text
- **THEN** submit remains disabled until non-empty text is entered for that question

#### Scenario: Submit is not replaced by jump gesture

- **WHEN** a question card has a source jump target and the user activates submit with the button or `⌘↩`
- **THEN** the card resolves with the question answer and does not invoke jump-back instead of submission

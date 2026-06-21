## Purpose

Define how `QuestionCard` renders `.question` content and collects a `QuestionAnswer` from the user within the `decide` state.

## Requirements

### Requirement: Question card renders each question item

`QuestionCard` SHALL render a `.question` content's `QuestionContent` by showing the `title` (when non-empty) and, for each `QuestionItem`, its `prompt` followed by its `options`. Each `QuestionOption` SHALL display its `label` and, when present, its `detail` on a secondary muted line. The card SHALL also show the source header.

#### Scenario: Multi-question content renders every item

- **WHEN** `QuestionCard` is given a `QuestionContent` with one or more `QuestionItem`
- **THEN** it renders each item's `prompt` and all `options` with each option's `label` and `detail`

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

`QuestionCard` SHALL provide a submit affordance (`⌘↩`) that resolves the card with `.question(QuestionAnswer)` whose `answers` map each item's `header` to one string value — single-select as the chosen label, multi-select as the chosen labels joined with `", "`, and a freeform ("其他") choice contributing the typed text in place of its label (matching how Claude Code's CLI inlines free text into the answer value). Submit SHALL be disabled until at least one question is answered.

#### Scenario: Submit resolves with selected answers

- **WHEN** the user has made a selection and triggers submit
- **THEN** `QuestionCard` resolves with `.question(QuestionAnswer)` whose `answers` is keyed by each item's `header` and reflects the selection

### Requirement: Question card countdown fails open to defer

`QuestionCard` SHALL run a decision countdown sourced from the configured decision timeout and SHALL resolve to `.defer` when the countdown elapses or the card is dismissed without a submission, so the tool falls back to its native prompt.

#### Scenario: Countdown elapses without submission

- **WHEN** the question card's countdown reaches zero before the user submits
- **THEN** the card resolves to `.defer`

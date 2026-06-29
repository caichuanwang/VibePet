## MODIFIED Requirements

### Requirement: Question card renders each question item

`QuestionCard` SHALL render `.question` content as a question-first card with a source header, optionally muted user/agent context when provided by the presentation layer, and the current `QuestionItem` as the primary body content. For single-question content, the card SHALL show that one item's `prompt` followed by its `options`. For multi-question content, the card SHALL show exactly one `QuestionItem` at a time with progress and navigation controls rather than rendering all items in one vertical list. Each `QuestionOption` SHALL display its `label` and, when present, its `detail` on a secondary muted line. When the source carries a jump target, double-clicking the non-control card body SHALL invoke the injected terminal jump action once without changing option, freeform input, navigation, or submit behavior.

#### Scenario: Single-question content renders directly

- **WHEN** `QuestionCard` is given a `QuestionContent` with one `QuestionItem`
- **THEN** it renders that item's prompt and all options with each option's label and detail

#### Scenario: Multi-question content renders one item at a time

- **WHEN** `QuestionCard` is given a `QuestionContent` with multiple `QuestionItem` values
- **THEN** it renders only the current item's prompt/options and shows progress plus previous/next navigation

#### Scenario: Muted context does not dominate question

- **WHEN** session user prompt or agent summary context is provided to a question card
- **THEN** the card renders that context with muted styling above the question and keeps the current question visually primary

#### Scenario: Double-click question body jumps back

- **WHEN** a question card with a source jump target is double-clicked on its body outside option controls, text fields, navigation buttons, and submit controls
- **THEN** the injected terminal jump action is invoked once with that jump target

### Requirement: Single-select and multi-select rendering

`QuestionCard` SHALL render an item whose `multiSelect` is `false` with single-choice controls (radio) such that selecting one option replaces any prior selection, and an item whose `multiSelect` is `true` with multi-choice controls (checkbox) such that multiple options can be selected. In multi-question mode, selection state SHALL be preserved per `QuestionItem.header` when navigating between questions.

#### Scenario: Single-select keeps one option

- **WHEN** an item with `multiSelect == false` is rendered and the user selects a second option
- **THEN** only the most recently selected option remains selected

#### Scenario: Multi-select keeps several options

- **WHEN** an item with `multiSelect == true` is rendered and the user selects two options
- **THEN** both options remain selected

#### Scenario: Navigation preserves prior selections

- **WHEN** the user answers one page of a multi-question card, navigates away, and returns to that page
- **THEN** the previously selected options and freeform text for that question are still shown

### Requirement: Submit collects a QuestionAnswer keyed by header

`QuestionCard` SHALL provide a submit affordance (`⌘↩`) that resolves the card with `.question(QuestionAnswer)` whose `answers` map each item's `header` to one string value — single-select as the chosen label, multi-select as the chosen labels joined with `", "`, and a freeform ("其他") choice contributing the typed text in place of its label (matching how Claude Code's CLI inlines free text into the answer value). Submit SHALL be visible only for a single-question card or on the final page of a multi-question card. Submit SHALL be disabled until every question in the card is answered: each question MUST have at least one selected option, and any selected freeform ("其他") option MUST carry non-empty text, so a multi-topic `AskUserQuestion` can never be submitted with some topics left unanswered. The terminal jump gesture SHALL NOT intercept submit controls or keyboard submission.

#### Scenario: Submit resolves with selected answers

- **WHEN** the user has answered every question and triggers submit
- **THEN** `QuestionCard` resolves with `.question(QuestionAnswer)` whose `answers` is keyed by each item's `header` and reflects every question's selection

#### Scenario: Submit is hidden until final page in multi-question mode

- **WHEN** a multi-question card is showing a non-final question page
- **THEN** the footer shows navigation/continue affordance rather than the final submit action

#### Scenario: Submit is disabled until all questions are answered

- **WHEN** a card presents multiple questions and the user has answered only some of them
- **THEN** the submit affordance remains disabled until each remaining question has a valid selection

#### Scenario: Freeform selection requires text before submit

- **WHEN** a selected option is the freeform ("其他") choice with empty text
- **THEN** submit remains disabled until non-empty text is entered for that question

#### Scenario: Submit is not replaced by jump gesture

- **WHEN** a question card has a source jump target and the user activates submit with the button or `⌘↩`
- **THEN** the card resolves with the question answer and does not invoke jump-back instead of submission

## ADDED Requirements

### Requirement: Multi-question navigation controls

`QuestionCard` SHALL provide previous/next navigation controls for multi-question content. The previous control SHALL be disabled on the first question, the next control SHALL be disabled on the final question, and the next control SHALL NOT advance when the current question has no valid answer. The footer SHALL keep "Back to terminal" on the left and question progression or submit actions on the right.

#### Scenario: Next waits for current answer

- **WHEN** a multi-question card is on a question page with no valid answer
- **THEN** activating Next does not advance to another question

#### Scenario: Previous returns to answered question

- **WHEN** the user is on a later question page and activates Previous
- **THEN** the card shows the prior question with its previous answer state intact

#### Scenario: Footer separates terminal and answer actions

- **WHEN** a question card is presented with a jump target
- **THEN** the footer places Back to terminal separately from question navigation or submit controls

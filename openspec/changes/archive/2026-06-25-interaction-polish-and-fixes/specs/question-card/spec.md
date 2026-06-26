## MODIFIED Requirements

### Requirement: Submit collects a QuestionAnswer keyed by header

`QuestionCard` SHALL provide a submit affordance (`⌘↩`) that resolves the card with `.question(QuestionAnswer)` whose `answers` map each item's `header` to one string value — single-select as the chosen label, multi-select as the chosen labels joined with `", "`, and a freeform ("其他") choice contributing the typed text in place of its label (matching how Claude Code's CLI inlines free text into the answer value). Submit SHALL be disabled until EVERY question in the card is answered — each question MUST have at least one selected option, and any selected freeform ("其他") option MUST carry non-empty text — so a multi-topic `AskUserQuestion` can never be submitted with some topics left unanswered. The terminal jump gesture SHALL NOT intercept submit controls or keyboard submission.

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

## REMOVED Requirements

### Requirement: Question card countdown fails open to defer

**Reason**: 0.3 移除 App 侧决策超时——问答卡一直挂起直到用户提交，不再有倒计时或到点自动 `.defer`。最终 fail-open 兜底改由 CLI hook 自身的读超时承担。

**Migration**: `QuestionCard` 不再接收 `timeout` 参数，也不渲染倒计时；移除卡片内的倒计时计时器与到零 `.defer` 路径。dismissal（未提交即关闭）仍解析为 `.defer`，使工具回落到原生提问流。

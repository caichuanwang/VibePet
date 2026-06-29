## 1. Regression Tests First

- [x] 1.1 Add `SpeechBubble`/surface tests or view projection helpers proving status/live bubbles render no footer/action row while keeping source header, body text, auto-dismiss, hover pause, and body double-click jump-back semantics.
- [x] 1.2 Extend `ApprovalCardTests` to cover the new footer split: normal approval Back to terminal invokes jump only and does not resolve, Deny/Allow once/Always allow resolve exactly once, and Always allow is hidden when absent.
- [x] 1.3 Extend `ApprovalCardTests` or snapshot-style helpers to prove normal approval layout omits user/agent context and foregrounds `ActionPreview`, while terminal-only approval still resolves `.defer`.
- [x] 1.4 Extend `QuestionCardTests` with pure paging state coverage: current page index, previous/next enabled states, next blocked until current question valid, selections/freeform preserved across navigation, and submit visible only on a single-question card or final multi-question page.
- [x] 1.5 Extend `BubbleJumpActionTests` or card tests to prove explicit Back to terminal on normal approvals/questions invokes the jump action without resolving the pending request and does not intercept option, navigation, text field, or submit controls.

## 2. Shared Presentation Plumbing

- [x] 2.1 Add a small UI-only conversation context model for muted question context (`latestUserPrompt`, `agentSummary`) without changing `BridgeEnvelope`, `BubbleContent`, or adapter encoding.
- [x] 2.2 Derive and pass that context from the existing `PetController` / `PetWindowSurface` card construction boundary using `SessionState` data when available.
- [x] 2.3 Add shared footer/action styling helpers in `BubbleTheme` or local private views so Back to terminal stays visually separated from agent decision/answer buttons.

## 3. Live And Approval Bubble Redesign

- [x] 3.1 Update `SpeechBubble` status/live rendering to match the compact prototype: source header plus body only, no bottom button bar, no reserved footer spacing.
- [x] 3.2 Update `ApprovalCard` body layout to remove conversation context and emphasize `ActionPreview`, risk label, truncation, and terminal-only hints.
- [x] 3.3 Update `ApprovalCard` footer so normal approvals show left-side Back to terminal and right-side Deny / Allow once / Always allow when available.
- [x] 3.4 Preserve keyboard shortcuts and focus behavior: high risk defaults to Deny, esc denies, default submit allows once, and Always allow keeps its scope hint.
- [x] 3.5 Preserve terminal-only approval downgrade behavior: hide decision buttons, show terminal handling affordance, attempt jump if possible, then resolve `.defer`.

## 4. Question Card Redesign

- [x] 4.1 Update `QuestionCard` to render optional user/agent context with muted styling above the question body.
- [x] 4.2 Refactor question state into per-header selections/freeform plus current question index, preserving existing `QuestionAnswer` collection format.
- [x] 4.3 Render single-question content directly with options, freeform entry, Back to terminal, and Submit.
- [x] 4.4 Render multi-question content as one question per page with progress count/dots, previous/next navigation, answered-state preservation, and final-page Submit.
- [x] 4.5 Disable Next until the current question is valid; disable Submit until every question is valid; keep freeform validation unchanged.
- [x] 4.6 Ensure Back to terminal on question cards jumps without resolving, while Submit resolves exactly once with `.question(QuestionAnswer)`.

## 5. Surface, Sizing, And Accessibility

- [x] 5.1 Update measuring/sizing in `PetWindowSurface` so compact live bubbles and paged question cards anchor correctly and stay within visible frame bounds.
- [x] 5.2 Keep `BubbleStackView` pending-card depth cues compatible with the redesigned approval/question footers and pending count labels.
- [x] 5.3 Add VoiceOver labels for question progress, previous/next controls, disabled submit states, Back to terminal, and approval decisions.
- [x] 5.4 Verify controls do not overlap at narrow widths and that text truncation/scrolling remains bounded to bubble dimensions.

## 6. Verification

- [x] 6.1 Run targeted app tests: `swift test --filter ApprovalCardTests`, `swift test --filter QuestionCardTests`, `swift test --filter BubbleJumpActionTests`, and `swift test --filter BubbleQueueTests`.
- [x] 6.2 Run targeted bubble/surface tests affected by layout changes, including `SpeechBubbleMarkdownTests`, `NotificationBubbleFlowTests`, and `OverlayWindowBehaviorTests` if touched.
- [x] 6.3 Run E2E approval/question tests: `swift test --filter ApprovalFlowTests` and `swift test --filter QuestionFlowTests`.
- [x] 6.4 Run full `swift test`; if the known intermittent SIGPIPE appears, rerun or narrow to the failing filter and record the outcome.

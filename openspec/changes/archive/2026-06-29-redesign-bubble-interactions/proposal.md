## Why

The current bubble surfaces expose the right primitives, but the information hierarchy is inconsistent: running bubbles are too action-heavy, approvals spend space on low-priority context, and multi-question prompts can become tall panels instead of pet-adjacent bubbles. The HTML prototype in `docs/bubble-content-redesign.html` establishes a tighter bubble-first layout that should now become the implementation contract.

## What Changes

- Redesign the running/status-style bubble so live activity is compact and has no bottom button bar.
- Redesign approval cards to emphasize the requested action preview and decision buttons, omitting user/agent conversation context from the approval body.
- Keep approval button behavior complete: return to terminal, deny, allow once, always allow when available, terminal-only fallback, keyboard shortcuts, and fail-open response semantics.
- Redesign question cards so user and agent context is visually muted while the current question remains primary.
- Change multi-question rendering from an all-at-once vertical list to a paged one-question-at-a-time flow with previous/next navigation, answered-state tracking, and submit only when all questions are complete.
- Preserve terminal jump-back behavior on card bodies and explicit "Back to terminal" controls without intercepting approval or question controls.
- Use open-vibe-island as the behavioral reference for session spotlight hierarchy, question prompts, actionable-state resolution, and jump-back affordances, adapted to VibePet's smaller Claude Code + Codex scope.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `speech-bubble`: Running/status bubble layout and action density requirements change.
- `approval-card`: Approval body hierarchy and complete button behavior requirements change.
- `question-card`: Single-question and multi-question interaction requirements change.
- `terminal-jumpback`: Explicit jump-back controls are added alongside existing body double-click behavior.

## Impact

- Affected app UI files: `VibePetApp/Bubble/SpeechBubble.swift`, `VibePetApp/Bubble/ApprovalCard.swift`, `VibePetApp/Bubble/QuestionCard.swift`, `VibePetApp/Bubble/BubbleStackView.swift`, and shared `BubbleTheme` helpers as needed.
- Affected state/queue wiring: approval and question response callbacks, pending counts, focus handling, and keyboard shortcuts.
- Affected tests: `SpeechBubbleMarkdownTests`, `ApprovalCardTests`, `QuestionCardTests`, `BubbleJumpActionTests`, `BubbleQueueTests`, and related E2E approval/question tests.
- No new network behavior, dependencies, or external services.

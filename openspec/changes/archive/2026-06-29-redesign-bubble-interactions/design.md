## Context

VibePet already has separate bubble surfaces for non-interactive notifications (`SpeechBubble`) and response-bearing cards (`ApprovalCard`, `QuestionCard`). Those surfaces are wired through `PetController` / `PetWindowSurface`, backed by `BubbleQueue` for FIFO interactive requests, and resolve to `BridgeResponse` values that preserve the hook runtime's fail-open contract.

The current UI was built incrementally. It correctly renders status/completion, approval, and question content, but it does not yet match the tighter bubble-first prototype in `docs/bubble-content-redesign.html`. The prototype intentionally avoids a panel-like treatment: running updates are compact, approvals foreground the requested action, and multi-question prompts page through one question at a time. open-vibe-island is the behavior reference for session spotlight hierarchy, actionable question state, and jump-back affordances, but VibePet remains scoped to Claude Code + Codex and local-first operation.

## Goals / Non-Goals

**Goals:**

- Make live/status bubbles compact and remove bottom action bars from non-interactive running updates.
- Make approvals decision-first: source/risk header, action preview, and complete action buttons without low-priority user/agent context.
- Preserve all approval actions and response semantics: return to terminal, deny, allow once, always allow, terminal-only defer, keyboard shortcuts, queue advancement, and fail-open dismissal.
- Make question cards context-aware but question-first: muted user/agent context, one current question in focus, freeform entry when needed, and explicit submission.
- Convert multi-question prompts to a paged flow with previous/next controls, answered-state tracking, and submit only after the final valid answer set is complete.
- Keep body double-click jump-back and add explicit "Back to terminal" controls without stealing option, text field, button, keyboard shortcut, hover, or dismissal behavior.

**Non-Goals:**

- No bridge protocol expansion for transcript history or rich assistant messages.
- No new network calls, telemetry, external services, or dependencies.
- No open-vibe-island feature imports beyond adapted UI and state-management patterns.
- No change to hook install paths, stable hook binary behavior, or fail-open transport rules.

## Decisions

### Keep data model changes local to presentation

The question and approval cards should not require a bridge protocol change. Approval data already carries `ApprovalContent`; question data already carries `QuestionContent`; session context exists in `SessionState` as `latestUserPrompt`, `summary`, source, and jump target. Implementation should pass a small optional presentation context from `PetController` / `PetWindowSurface` into cards when available.

Alternative considered: add user/agent context fields to `BridgeEnvelope`. Rejected because hook payloads do not consistently provide richer context, and this would couple UI polish to bridge compatibility.

### Split notification and interactive action density

`SpeechBubble` should keep status/completion lightweight. Running/live updates should not show a bottom button bar; terminal jump remains available by double-clicking the body when a jump target exists. Interactive cards keep explicit bottom actions because they block a tool flow.

Alternative considered: add a "Back to terminal" button to all bubbles. Rejected because it makes live updates read like panels and conflicts with the prototype's compact running state.

### Make approval body action-first

Approval cards should omit user/agent conversation context and spend body space on `ActionPreview`: command/file/network/generic preview, risk label, truncation, and required terminal downgrade hints. The footer stays split: left-side "Back to terminal" affordance, right-side decisions. The terminal-only form still jumps if possible and resolves `.defer` so the native tool flow continues.

Alternative considered: keep conversation context above action preview with muted styling. Rejected because approvals are time-sensitive decisions and need immediate command/request visibility.

### Page multi-question cards inside one request

`QuestionCard` should maintain local state for the current question index, selections, and freeform text. When `questions.count == 1`, it behaves as a simple single-page question. When multiple questions are present, it shows one `QuestionItem` at a time with previous/next controls, progress dots or count, and an answered summary. Next is enabled only when the current page is valid. Submit appears on the final page and remains disabled until all questions are valid.

Alternative considered: show every `QuestionItem` in one scrollable card. Rejected because long cards turn the pet bubble into a panel and make footer actions harder to keep visible.

### Keep response collection compatible with current adapters

Collected `QuestionAnswer.answers` remains keyed by `QuestionItem.header`, with single-select as the chosen label, multi-select labels joined by `", "`, and selected freeform options contributing typed text in place of their label. This keeps Claude Code question encoding behavior stable.

### Preserve existing queue and single-resolution guarantees

The redesign should not change `BubbleQueue` semantics. Each pending decision remains keyed by request id; only the front request is interactive; resolving a card removes the matching front request exactly once. New navigation inside a multi-question card must be local UI state, not separate queued decisions.

## Risks / Trade-offs

- Multi-question paging can hide unanswered questions → show progress/count, answered summary, and disable submit until all pages are valid.
- Extra card context plumbing could duplicate session projection logic → keep the presentation context small and derive it at the existing card construction boundary.
- Explicit "Back to terminal" could be mistaken for deferring the request → for normal approvals/questions it only jumps; it MUST NOT resolve the request unless the card is in terminal-only approval mode.
- Keyboard shortcuts can conflict with text fields → submit shortcuts must not fire while freeform text is invalid, and jump gestures must stay scoped away from controls.
- Visual compaction can reduce accessibility context → preserve VoiceOver labels for source, status, current question count, options, buttons, and disabled submit state.

## Migration Plan

1. Add presentation helpers and focused tests for live bubble, approval, and question behavior.
2. Update SwiftUI card layouts and local state without changing bridge serialization.
3. Update queue/surface construction only where needed to pass optional session context and explicit jump actions.
4. Run targeted app tests for cards, jump actions, queue behavior, and markdown bubbles.
5. Run `swift test` for full regression coverage because bridge/session/adapter behavior must remain fail-open.

Rollback is straightforward: revert card/view changes and tests. No persisted data or protocol migration is introduced.

## Open Questions

- Whether the production UI should include an answered-summary strip for multi-question prompts exactly as the prototype shows, or use only progress count/dots. The implementation can start with count/dots plus disabled submit and add a summary if visual space remains acceptable.

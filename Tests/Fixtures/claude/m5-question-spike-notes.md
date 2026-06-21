# M5-0 · Claude Code AskUserQuestion `updatedInput` schema spike — conclusion

**Date:** 2026-06-20
**Claude Code hooks docs:** https://code.claude.com/docs/en/hooks
**Agent SDK user-input docs (authoritative on the answer format):** https://code.claude.com/docs/en/agent-sdk/user-input
**Changelog:** https://code.claude.com/docs/en/changelog (v2.1.85)
**Reference implementation:** Open Island (Octane0411/open-vibe-island) — `ClaudeHooks.swift` / `IslandPanelView.swift` / `BridgeServer.swift`

## Question

Can a `PreToolUse` hook **answer** an `AskUserQuestion` call — return
`permissionDecision:"allow"` plus an `updatedInput` that supplies the user's
selection — so the tool proceeds **without prompting** the user natively? This is
the headline mechanism for M5 (PRD §4.1, US-3b).

## Finding: SUPPORTED (Claude Code ≥ 2.1.85)

The official changelog (v2.1.85) states:

> PreToolUse hooks can now satisfy `AskUserQuestion` by returning `updatedInput`
> alongside `permissionDecision: "allow"`, enabling headless integrations that
> collect answers via their own UI.

This is exactly VibePet's use case: collect the answer in the pet bubble, then
write it back via `updatedInput`.

Corroborated by the `AskUserQuestion` tool input schema, whose `tool_input`
carries answer-bearing fields (not just the questions):

- `questions: [{ question, header, multiSelect, options: [{ label, description }] }]`
- `answers`: object keyed by **question text**, value = selected option `label`.
- `annotations`: optional per-question notes/preview (not needed to answer; see below).

Because `answers` is an *input* field that the permission component fills,
`updatedInput` can supply it — refuting the earlier (wrong) assumption that the
answer was purely tool output.

### Answer value format (verified against the SDK user-input docs)

The Agent SDK "Response format" section is authoritative:

- **Multi-select**: *"pass an array of labels **or** join them with `", "`."* This build
  joins with `", "` (fits the `[String: String]` answer map; matches the SDK's own
  reference `parseResponse` and Open Island).
- **Free text ("Other")**: *"Use the user's custom text as the answer value (not the
  word 'Other')."* So freeform text goes **into the `answers` value**, not a separate
  field. There is **no `annotations` output requirement** (Open Island only emits it
  when non-empty, and its UI never populates it). The CLIs add an "Other" choice
  client-side for every question — this build mirrors that by appending a synthetic
  `其他` (`allowsFreeform`) option per question and stripping it back out of
  `updatedInput.questions`.
- **Optional `response`** (not used here): a whole-card freeform reply that dismisses
  the structured questions; Claude then sees "The user responded: …".

Hook output shape:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "updatedInput": { "questions": [ ...original... ], "answers": { "<question text>": "<label>" } }
  }
}
```

`updatedInput` *replaces* the whole tool input, so the original `questions` must
be preserved alongside `answers`.

## Known version-dependent bugs (handle defensively)

- [#15897](https://github.com/anthropics/claude-code/issues/15897): with multiple
  `PreToolUse` hooks, a returned `updatedInput` can be ignored.
- [#52822](https://github.com/anthropics/claude-code/issues/52822) (v2.1.119
  regression): the hook runs and stdout is parsed, but the native prompt is still
  shown in interactive mode.

Mitigation: keep the fail-open countdown (App-side + CLI read deadline) so a
non-suppressing version still ends in `defer` → native prompt, never a hang.

## Decision (M5 ships the full path)

- `ClaudeCodeAdapter` parses `PreToolUse(tool_name == AskUserQuestion)` → `.question`.
- `QuestionCard` renders questions for in-bubble answering; `PetController.decide`
  presents it and pairs `.question(QuestionAnswer)` back by `requestId`.
- `encodeResponse(.question(answer))` → `allow` + `updatedInput` (answers keyed by
  question text, translated from `QuestionAnswer.answers` which is keyed by header;
  the synthetic `其他` option is removed from the rebuilt `questions`).
- Fail-open preserved: no usable selection / timeout → `defer` (no JSON, exit 0).

## Residual detail to verify against a live session

- The answer **format** is now determined from the SDK docs + Open Island (single =
  label; multi = `", "`-joined; free text = the typed value). What still benefits
  from a live Claude Code session is the **end-to-end** confirmation that a real
  ≥2.1.85 build accepts these values and suppresses the native prompt — the same
  live check the rest of the write-back path needs.

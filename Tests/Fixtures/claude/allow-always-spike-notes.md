# M4-3a · Claude Code allowAlways schema spike — conclusion

**Date:** 2026-06-19
**Claude Code hooks docs:** https://code.claude.com/docs/en/hooks.md (verified current)

## Question

Can a `PreToolUse` hook grant a **persistent or session-scoped** allow, so the
same tool/command is auto-allowed in the future without re-prompting? This gates
the "始终允许 / Always allow" button.

## Finding: NOT supported via the PreToolUse hook

A `PreToolUse` hook's `permissionDecision` (`allow` / `deny` / `ask`) is
**per-invocation only**. The hook output contract is:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"..."}}
```

`permissionDecision: "allow"` bypasses the permission prompt for **that single
call**. There is no field in the `PreToolUse` hook output to persist a rule.

The docs explicitly direct durable allow/deny to the **permission system**
(`settings.json` `permissions.allow` rules like `Bash(npm run *)`), not to hook
output:

> "Because the `if` filter is best-effort, use the permission system rather than
> a hook to enforce a hard allow or deny."

Writing to the user's `settings.json` from VibePet would be a side-effecting
config mutation outside the hook contract — out of scope for the M4 MVP and
risky to do silently.

## Decision (per M4-3a fallback)

`allowAlways` is recorded as **unsupported** for the Claude Code `PreToolUse`
path in the MVP:

- `ClaudeCodeAdapter` leaves `ApprovalContent.alwaysAllow == nil`.
- The approval UI hides the "始终允许" button (shown only when `alwaysAllow != nil`).
- `encodeResponse(.approval(.allowAlways))` degrades to a one-time `allow`
  (defensive only; the button cannot produce this decision when hidden).
- No downstream requirement treats `allowAlways` as a hard dependency.

Re-evaluate if Claude Code adds a hook-driven persistent permission mechanism.

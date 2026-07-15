# M4-3a · Claude Code allowAlways schema spike — updated conclusion

**Date:** 2026-06-19
**Claude Code hooks docs:** https://code.claude.com/docs/en/hooks.md (verified current)

## Question

Can a hook grant a **persistent or session-scoped** allow, so the same tool is
auto-allowed in the future without re-prompting? This gates the "始终允许 /
Always allow" button.

## Finding

`PreToolUse` does not support durable permission updates. `PermissionRequest`
does support a decision-level `updatedPermissions` field, which can add a
session-scoped allow rule.

### PreToolUse limitation

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

### PermissionRequest support

Claude Code `PermissionRequest` output accepts:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "updatedPermissions": [
        {
          "type": "addRules",
          "destination": "session",
          "rules": [{ "toolName": "Bash" }],
          "behavior": "allow"
        }
      ]
    }
  }
}
```

## Decision

VibePet enables `allowAlways` for Claude Code `PermissionRequest` approvals:

- `ClaudeCodeAdapter` sets `ApprovalContent.alwaysAllow` from `tool_name`.
- The approval UI shows "始终允许" when `alwaysAllow != nil`.
- `encodeResponse(.approval(.allowAlways(scopeHint: toolName)))` emits an
  `allow` decision with a session-scoped `addRules` permission update.
- The option is session-scoped only; VibePet still does not mutate user or
  project settings for persistent permissions.

Thanks for helping improve VibePet. A focused, reproducible issue is much easier to investigate and more likely to be acted on.

> The repository uses English for shared project documentation. Issues in Chinese are also welcome; please keep commands, logs, and error messages in their original form when possible.

## Choose the right issue type

- **Bug report:** Something supported by VibePet is broken or behaves unexpectedly.
- **Feature request:** You have a concrete use case that the current product does not cover.
- **Question, documentation, or other:** Open a blank issue with a clear title and enough context.
- **Security vulnerability:** **Do not post exploit details, credentials, or private data in a public issue.** Use an available private contact method. If none is listed, open only a minimal issue asking the maintainer how to report securely, without including vulnerability details.

Use the [issue chooser](https://github.com/caichuanwang/VibePet/issues/new/choose) to start.

## Before submitting

- Search [open and closed issues](https://github.com/caichuanwang/VibePet/issues?q=is%3Aissue) for duplicates.
- Confirm the problem is about VibePet rather than Claude Code, Codex, macOS, or a third-party pet package.
- If practical, reproduce it with the latest VibePet version or current `master` branch.
- Keep one problem or proposal per issue.
- Remove secrets, tokens, usernames, private prompts/session content, and identifying local paths from logs and screenshots.

## Make the issue actionable

For a **bug**, include:

- concise reproduction steps;
- expected and actual behavior;
- macOS, VibePet, Claude Code/Codex, and installation details that matter;
- minimal, redacted logs or screenshots;
- whether the native tool flow still works when VibePet is unavailable.

For a **feature request**, include:

- the user problem and who encounters it;
- a concrete example or workflow;
- the smallest useful outcome;
- alternatives or workarounds considered;
- any effect on VibePet's local-first privacy model or fail-open behavior.

## Project scope

VibePet currently targets **macOS 14+**, **Claude Code and Codex**, local-only operation, and Codex-format spritesheet pets. Proposals involving additional agents, network services, telemetry, cloud galleries, or App Store sandboxing need a clear product and privacy rationale and may be declined as out of scope.

Hook and bridge changes must preserve **fail-open behavior**: if VibePet is unavailable or fails, the coding tool must fall back to its native flow instead of hanging.

## What happens next

Maintainers may ask for more information, apply labels, merge duplicates, or close issues that cannot be reproduced or are outside the current scope. VibePet is maintained as an open-source project, so response and delivery times are not guaranteed. A 👍 reaction is preferred over a `+1` comment on an existing request.

Thank you for taking the time to make VibePet better.

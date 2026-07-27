# VibePet Open Vibe Island Full-Parity Migration Design

**Date:** 2026-07-27
**Status:** Approved
**Upstream baseline:** `open-vibe-island` commit `1e26dfc8d42bec0da7627986d49c2320b2593610`

## 1. Context

VibePet and Open Vibe Island solve the same core problem: expose local coding-agent sessions, decisions, questions, notifications, and navigation in a persistent macOS surface. Their primary product difference is presentation. Open Vibe Island uses a notch-centered island, while VibePet places the same interaction surface next to a desktop pet.

VibePet currently supports Claude Code and Codex through its own bridge, adapters, installer, session reducer, dashboard, and pet notification UI. Open Vibe Island has since developed a broader and more complete implementation covering more agents, richer session recovery, installation health, terminal integration, notifications, update support, and companion services.

There are no existing VibePet users whose persisted configuration or installed hooks must remain compatible. The migration can therefore replace internal models and storage formats instead of maintaining a long-lived compatibility layer.

Both repositories use GPL-3.0. Source copied or derived from Open Vibe Island must retain applicable copyright notices, remain GPL-3.0, identify the upstream repository, and record the exact source commit.

## 2. Product Decision

VibePet will become an Open Vibe Island functional distribution with a pet-centered presentation layer.

All upstream functionality is in scope except the notch-specific user interface. The pet, pet-adjacent dashboard, decision bubbles, animation system, asset import, transparent hit testing, drag behavior, and cross-Space window behavior remain VibePet-owned product surfaces.

The migration will use upstream-first replacement rather than incremental emulation. Shared models, transports, adapters, installers, discovery, persistence, and application services should retain upstream structure where practical so future upstream synchronization remains understandable.

## 3. Goals

1. Reach functional parity with the selected Open Vibe Island baseline outside notch-specific presentation.
2. Support the upstream agent set through one normalized event and session model.
3. Preserve VibePet's pet presentation, animation, asset, and window behavior.
4. Keep hooks and bridge operations fail-open under malformed input, missing app, socket failure, and timeout.
5. Keep agent-specific payload and configuration differences inside adapters and installers.
6. Make future upstream synchronization traceable through source mapping and a pinned baseline commit.
7. Finish each migration pair with a buildable, tested application rather than deferring integration until the end.

## 4. Non-Goals

1. Preserve compatibility with current development-only VibePet configuration, manifests, session caches, or installed hooks.
2. Preserve VibePet's current internal session and adapter architecture when the upstream equivalent replaces it.
3. Recreate the notch, island geometry, notch window placement, or notch-specific visual components.
4. Add telemetry, remote generation, a public pet gallery, or unrelated cloud storage.
5. Build or test the nested `open-vibe-island` package as part of VibePet verification.

## 5. Target Architecture

```text
Native agent hook / plugin / local transcript / process observation
                              |
                              v
                    Agent-specific boundary
              Adapter / installer / discovery reader
                              |
                              v
                  AgentEvent + AgentSession
                              |
                              v
                 Single SessionState reducer
                              |
                              v
                         AppModel
              +---------------+----------------+
              |               |                |
              v               v                v
       Session services   Local services   Presentation projection
       - persistence      - terminal       - dashboard
       - discovery        - notifications  - decision bubble
       - liveness         - sounds         - pet state
       - merging          - updates        - menu/settings
                          - Watch relay
                              |
                              v
                Pet window and pet-adjacent UI
```

### 5.1 Core

`VibePetCore` owns UI-independent types and behavior:

- normalized agent identifiers, events, sessions, phases, decisions, and metadata;
- pure session reduction and derived counts;
- bridge commands, responses, codecs, framing, and transport;
- hook payload adapters and response encoders;
- agent configuration writers, installers, manifests, health checks, and intent storage;
- bounded local discovery readers and safe session registries;
- workspace, process, usage, and terminal metadata models;
- Watch relay contracts that do not import AppKit or SwiftUI.

Core system effects must remain injectable. No Core test may touch real user configuration, execute UI automation, or require a running VibePet app.

### 5.2 App

`VibePetApp` owns the central observable `AppModel` and macOS effects:

- bridge hosting and command routing;
- process monitoring and startup discovery coordination;
- terminal probes, terminal jumping, text sending, and optional keystroke injection;
- notification sound routing and foreground-session suppression;
- launch-at-login, update checking, and Watch relay lifecycle;
- pet state projection, dashboard projection, settings, onboarding, and menu-bar presentation.

The AppModel is the single owner of UI-facing session state. Services publish inputs or execute effects; they do not maintain competing session collections.

### 5.3 Hooks and Setup

`VibePetHooks` remains a small fail-open executable:

1. select the native tool adapter;
2. read bounded input;
3. capture runtime context;
4. send one bridge request;
5. write output only when the native tool requires a response;
6. exit without blocking the tool when any step fails.

`VibePetSetup` provides explicit install, uninstall, repair, status, and diagnostics for every supported integration. App and Setup must construct the same installer and resolve the same configuration root.

### 5.4 Presentation

The following VibePet modules remain product-owned and are adapted rather than replaced:

- pet asset store and package import;
- sprite sheet animation and visual state mapping;
- transparent hit mask and drag behavior;
- pet overlay panel and cross-Space behavior;
- pet-adjacent dashboard placement;
- pet-adjacent approval, question, status, and completion bubbles;
- VibePet branding and localization.

Upstream notch views, notch shapes, island chrome, and notch placement controllers are excluded. Their state projections and actions may be reused, but they render through VibePet surfaces.

## 6. Supported Integrations

The normalized agent set is:

| Agent | Native boundary | Required support |
|---|---|---|
| Claude Code | JSON hooks and status line | Lifecycle, approval, question, usage, discovery, install health |
| Codex | JSON hooks and app-server metadata | Lifecycle, approval, usage, discovery, trust state, install health |
| Gemini CLI | Gemini hooks | Lifecycle, notification, completion compatibility, terminal metadata |
| OpenCode | JavaScript plugin | Lifecycle, permission, question, persistence, process detection |
| Cursor | Cursor hooks and transcripts | Lifecycle, metadata, discovery, install health |
| Qoder | Claude-compatible hooks | Lifecycle, approval, question, install health |
| Qwen Code | Claude-compatible hooks | Lifecycle, approval, question, install health |
| Factory / Droid | Claude-compatible hooks | Lifecycle, approval, question, install health |
| CodeBuddy | Claude-compatible hooks | Lifecycle, approval, question, install health |
| Kimi CLI | TOML-configured Claude-compatible hooks | Lifecycle, approval, question, dedicated safe installer |

Claude usage/status-line bridging is managed as an explicit integration capability even though it does not create a separate `AgentTool` session type.

## 7. Data and Control Flow

### 7.1 Inbound Events

Every native source is decoded by its own adapter. The adapter may enrich the payload with working directory, branch, TTY, terminal session, transcript, and tool metadata. It then emits a normalized `AgentEvent` or ignores an unsupported event.

The AppModel applies the event through one `SessionState` reducer. Dashboard rows, attention counts, running counts, pet animation, notification routing, and Watch payloads derive from the resulting state. No adapter may mutate presentation state directly.

### 7.2 Interactive Decisions

Approval and question requests carry a request identity through the bridge. The AppModel queues and presents the actionable item. The user's decision is encoded back into the native tool's response shape by the originating adapter.

Dismissal, timeout, app shutdown, bridge cancellation, and hidden-pet behavior must resolve through an explicit fail-open path. A late or duplicate response must be idempotent.

### 7.3 Discovery and Recovery

Startup recovery combines safe persisted projections, bounded local history readers, and process discovery. Merge precedence is exact session ID, precise terminal identity, and then unambiguous normalized working directory. Ambiguous matches remain separate.

Persisted projections exclude approval bodies, question answers, request identifiers, continuations, response queues, timeouts, and presentation state. Corrupt stores fail soft and are quarantined or ignored according to the upstream contract.

### 7.4 Presentation Routing

Actionable approval and question events always remain visible and bypass non-critical suppression. Lifecycle and status events update canonical state without creating duplicate UI. Completion and non-actionable notifications may be suppressed only when an exact foreground terminal identity matches.

The dashboard and anchored bubble must not present the same actionable session simultaneously. Pet animation is derived from aggregate session state with attention taking priority over ordinary running activity.

## 8. Failure and Safety Boundaries

1. Hook decode, connection, write, read, timeout, and malformed response failures return control to the native tool.
2. Unknown native events are ignored instead of terminating the hook process.
3. Bridge frames remain bounded, newline-delimited, request-correlated, and protected against SIGPIPE.
4. Installer mutation is non-destructive and idempotent. It preserves unrelated user hooks and configuration fields.
5. Install, uninstall, and repair update persisted intent only after successful filesystem mutation.
6. Local discovery rejects unsafe symlinks, oversized inputs, unbounded traversal, and ambiguous candidate merges.
7. Notification, sound, update, Watch, terminal probe, and Accessibility failures do not corrupt or block session state.
8. Accessibility and keystroke injection run only after a user-triggered action that requires them.
9. Network-capable services remain explicit and must not introduce telemetry or upload session content beyond their documented function.
10. Real user hook directories are never used by automated tests.

## 9. Source Migration Policy

Source may be copied directly from the pinned Open Vibe Island baseline because both projects are GPL-3.0. Copying follows these rules:

1. Preserve upstream copyright and license notices where present.
2. Add an attribution document mapping imported modules to the upstream repository and commit.
3. Prefer retaining upstream file boundaries and type names inside shared internals when product naming does not leak.
4. Rename product-facing paths, commands, bundle identifiers, socket names, status messages, and UI labels to VibePet.
5. Do not import notch-only files.
6. Do not stage or publish the nested `open-vibe-island/.git` repository.
7. Record meaningful deviations so a future upstream sync can distinguish VibePet changes from copied code.

## 10. Migration Milestones

### M0: Migration Baseline

- create the dedicated migration branch;
- pin and document the upstream commit;
- add attribution and source mapping;
- establish the retained/excluded file inventory;
- lock pet assets, animation, hit testing, dragging, Spaces, window positioning, and import behavior with regression tests;
- discard obsolete half-migration architecture instead of maintaining parallel models.

### M1: Shared Runtime Replacement

- migrate normalized agent, event, session, phase, metadata, and decision models;
- migrate the pure reducer and derived state;
- migrate bridge commands, responses, codecs, server, and client;
- establish the new AppModel boundary while keeping the app launchable;
- retain baseline Claude/Codex flows through the new runtime.

### M2: Complete Agent Integration

- migrate adapters, plugins, installers, manifests, health checks, and intent storage for all listed agents;
- route App and Setup through shared installer construction;
- migrate usage and status-line integrations;
- provide fixture-backed adapter and temporary-directory installer coverage.

### M3: Session Continuity

- migrate safe session registries and bounded local discovery;
- migrate process monitoring, liveness, startup restoration, and conservative merging;
- capture normalized workspace, branch, TTY, terminal session, transcript, and tool metadata;
- ensure late, duplicate, and stale events are idempotent.

### M4: Application Services

- migrate terminal jump and attachment resolution for supported terminals and IDEs;
- migrate foreground-session suppression, notification sounds, and terminal text sending;
- migrate optional keystroke injection, launch-at-login, update checking, and Watch relay;
- isolate every service failure from the canonical session reducer.

### M5: Pet Presentation Integration

- replace notch projections with pet-adjacent dashboard and bubble projections;
- connect approval, question, status, completion, and session navigation actions;
- migrate settings, onboarding, menu-bar controls, localization, and health presentation for all agents;
- preserve stable pet position, compact dashboard geometry, and non-duplicated decision UI.

### M6: Parity Closure

- port relevant upstream tests and retain VibePet-specific regression tests;
- audit the upstream product and architecture feature lists item by item;
- remove obsolete VibePet runtime paths made redundant by the migrated architecture;
- complete build, test, strict OpenSpec, import-boundary, licensing, and manual UI verification;
- document remaining intentional differences, limited to presentation and VibePet branding.

## 11. Verification Cadence

The request to test every two milestones is interpreted as running the complete verification gate after each functional pair. Focused tests and compilation checks still run during implementation to localize regressions.

### Baseline

M0 records the existing build, full test, OpenSpec, and pet-specific regression results before runtime replacement.

### Gate A: M1 + M2

- `swift build`;
- complete `swift test`;
- all adapter fixture tests;
- all installer/configuration tests in temporary directories;
- bridge fail-open and interactive round-trip tests;
- strict OpenSpec validation for the runtime and agent integration changes.

### Gate B: M3 + M4

- `swift build`;
- complete `swift test`;
- session registry, discovery budget, liveness, merge, and startup race tests;
- terminal, notification, update, Watch, and Accessibility service tests with injected effects;
- strict OpenSpec validation for continuity and application services.

### Gate C: M5 + M6

- `swift build`;
- complete `swift test`;
- pet presentation, dashboard, bubble, onboarding, settings, and E2E hook tests;
- `openspec validate --specs --strict` plus every active change target;
- `git diff --check` and Core/App import-boundary audit;
- source attribution and upstream parity audit;
- manual macOS verification of the pet, dashboard, decisions, terminal jump, notifications, and supported integrations.

No automated installer smoke test may write to real `~/.claude`, `~/.codex`, or another agent configuration root.

## 12. Branch and Existing Work Strategy

The full-parity migration starts from current `master` on `codex/open-vibe-island-full-parity`. The prior second selective-port work remains preserved in a stash and is not applied wholesale. Its validated VibePet-specific tests and behavioral decisions may be reintroduced selectively when they protect behavior not already covered upstream.

Each milestone should be reviewable in isolation. A commit must not mix source import, product adaptation, and unrelated cleanup when those changes can be separated safely.

## 13. Acceptance Criteria

The migration is complete when:

1. VibePet supports the full listed upstream agent set with install, health, lifecycle, and interactive behavior appropriate to each tool.
2. Shared session behavior comes from one normalized reducer and one AppModel-owned state collection.
3. Startup discovery, persistence, liveness, merging, terminal metadata, and exact jump-back behavior match the pinned upstream baseline.
4. Notification sounds, foreground suppression, terminal text sending, optional keystroke injection, launch-at-login, update checking, and Watch relay are integrated outside the reducer.
5. The notch UI and notch geometry are absent.
6. The pet, pet assets, animation, dragging, transparent hit testing, cross-Space behavior, dashboard, and bubbles remain functional.
7. All three paired verification gates pass with zero known errors.
8. GPL attribution identifies the upstream repository and pinned source commit.
9. Remaining differences from Open Vibe Island are documented and limited to VibePet presentation, branding, and explicitly approved platform adaptations.

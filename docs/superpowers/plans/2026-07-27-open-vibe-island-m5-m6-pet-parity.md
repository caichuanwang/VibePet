# Open Vibe Island M5-M6 Pet Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Present the complete upstream runtime through VibePet's pet-adjacent dashboard, bubbles, settings, onboarding, and menu while removing obsolete runtime paths and proving full non-notch parity.

**Architecture:** AppModel remains the only session owner. Pure presentation projections translate upstream session state into pet animation, dashboard sections, actionable bubbles, settings rows, onboarding eligibility, and menu summaries; pet windows and geometry remain product-owned.

**Tech Stack:** Swift 6.2, SwiftPM, SwiftUI, AppKit, MarkdownUI, XCTest, OpenSpec, local visual/manual verification.

**Spec:** `docs/superpowers/specs/2026-07-27-open-vibe-island-full-parity-design.md`

---

## Protected VibePet Files

These remain VibePet-owned and are modified only at explicit projection/action boundaries:

- `VibePetCore/Pet/`, `VibePetCore/Geometry/`, and pet persistence/import files;
- `VibePetApp/Pet/`, `VibePetApp/Window/`, and `VibePetApp/Import/`;
- `VibePetApp/Dashboard/` and `VibePetApp/Bubble/` geometry and visual components.

Upstream state/action references come from `AgentSession+Presentation.swift`, `AppModel.swift`, `AppModelTypes.swift`, `IslandPanelView.swift`, `UnifiedBars.swift`, `SettingsView.swift`, `AppearanceSettingsPane.swift`, and the Harness files. `V6NotchContent.swift`, `NotchShape.swift`, island chrome, and notch panel geometry are not imported.

### Task 1: Specify pet-surface parity and projection contracts

**Files:**
- Create: `openspec/changes/present-upstream-runtime-by-pet/`
- Create: `VibePetApp/Presentation/AgentSessionPresentation.swift`
- Test: `Tests/VibePetAppTests/AgentSessionPresentationTests.swift`

- [ ] **Step 1: Create and validate the OpenSpec change**

```bash
openspec new change present-upstream-runtime-by-pet
openspec validate present-upstream-runtime-by-pet --strict
```

Expected: strict validation succeeds after requirements cover pet state, dashboard, bubbles, settings, onboarding, menu, harness, and Gate C.

- [ ] **Step 2: Port upstream presentation tests before code**

Copy `AgentSessionPresentationTests.swift` and add VibePet cases for all ten agents, waiting/idle/running/completed/error phases, tool display names, detail fallback text, attention priority, and stable timestamps.

- [ ] **Step 3: Run projection tests red**

```bash
swift test --filter AgentSessionPresentation
```

Expected: presentation extension and complete agent labels are missing.

- [ ] **Step 4: Import only the non-visual presentation extension**

Copy upstream `AgentSession+Presentation.swift` to `VibePetApp/Presentation/AgentSessionPresentation.swift`. Rename modules/product labels and strip notch-specific size/chrome references. Keep pure labels, status, timestamps, summaries, and colors or map them into existing VibePet theme tokens.

- [ ] **Step 5: Run tests green and commit**

```bash
swift test --filter AgentSessionPresentation
git add VibePetApp/Presentation Tests/VibePetAppTests openspec/changes/present-upstream-runtime-by-pet
git commit -m "Project upstream sessions into VibePet presentation data" \
  -m "Constraint: Presentation is pure and contains no notch geometry or filesystem effects." \
  -m "Confidence: high" \
  -m "Scope-risk: moderate" \
  -m "Tested: AgentSessionPresentationTests; strict OpenSpec"
```

### Task 2: Drive pet animation from the canonical runtime

**Files:**
- Modify: `VibePetCore/Pet/PetStateMachine.swift`
- Modify: `VibePetApp/Pet/PetController.swift`, `PetAnimations.swift`
- Test: `PetStateMachineTests.swift`, `PetStatusIndicatorTests.swift`, `NotificationBubbleFlowTests.swift`

- [ ] **Step 1: Add aggregate-state table tests**

Use a table covering no sessions, idle, running, approval, question, completed, and error. Assert attention outranks running, error/completion do not erase another active session, and discovered-idle sessions do not animate as running.

- [ ] **Step 2: Run pet-state tests red**

```bash
swift test --filter 'PetStateMachine|PetStatusIndicator|NotificationBubbleFlow'
```

Expected: existing projections refer to old session models or miss new phases/tools.

- [ ] **Step 3: Replace the projection input, not the pet engine**

Use `apply_patch` so `PetController` observes immutable AppModel/session projections. Keep sprite rows, durations, hit masks, position, drag, and window state unchanged. Remove any PetController-owned mutable session store.

- [ ] **Step 4: Run tests green and commit**

```bash
swift test --filter 'PetStateMachine|PetStatusIndicator|NotificationBubbleFlow'
git add VibePetCore/Pet VibePetApp/Pet Tests
git commit -m "Drive pet behavior from normalized agent sessions" \
  -m "Constraint: Existing sprite and window behavior remains unchanged." \
  -m "Confidence: high" \
  -m "Scope-risk: moderate" \
  -m "Tested: pet state, status indicator, and notification flow suites"
```

### Task 3: Generalize the pet-adjacent dashboard for all agents

**Files:**
- Modify: `VibePetApp/Dashboard/SessionDashboardProjection.swift`, `SessionDashboardView.swift`, `SessionDashboardWindowController.swift`
- Test: `SessionDashboardProjectionTests.swift`, `OverlayWindowBehaviorTests.swift`

- [ ] **Step 1: Add dashboard projection matrix tests**

Cover every agent and phase, fixed state group order, project grouping, sorting, retention, stable selection, exact tool icon/name, removal eligibility, and no filesystem access in projection.

- [ ] **Step 2: Run dashboard tests red**

```bash
swift test --filter 'SessionDashboard|OverlayWindowBehavior'
```

Expected: old `ToolKind` and session fields fail or omit new agents.

- [ ] **Step 3: Adapt upstream rows/actions into existing pet geometry**

Use upstream `IslandPanelView.swift` and `UnifiedBars.swift` only as state/action references. Keep VibePet's compact window, pet anchor, selection stability, scroll behavior, and no nested-card layout. Render all agent labels/icons and wire actions to AppModel.

- [ ] **Step 4: Run tests green and commit**

```bash
swift test --filter 'SessionDashboard|OverlayWindowBehavior'
git add VibePetApp/Dashboard Tests/VibePetAppTests
git commit -m "Show every upstream agent in the pet dashboard" \
  -m "Constraint: Dashboard geometry remains compact and anchored to the pet." \
  -m "Confidence: high" \
  -m "Scope-risk: broad" \
  -m "Tested: dashboard projection and overlay-window suites"
```

### Task 4: Rewire approval, question, notification, and completion bubbles

**Files:**
- Modify: `VibePetApp/Bubble/*.swift`
- Modify: `VibePetApp/Pet/PetController.swift`
- Test: approval, question, queue, jump, sizing, markdown, and E2E suites

- [ ] **Step 1: Add normalized-action tests**

For Claude, Codex, OpenCode, and compatible agents, test allow/deny/defer/question answers, native response correlation, FIFO decisions, dismiss fail-open, dashboard duplicate suppression, completion/status non-actionability, and terminal jump actions.

- [ ] **Step 2: Run bubble tests red**

```bash
swift test --filter 'ApprovalCard|QuestionCard|BubbleQueue|BubbleJump|SpeechBubble|ApprovalFlow|QuestionFlow|NotificationFlow'
```

Expected: old response/content types fail against normalized AppModel actions.

- [ ] **Step 3: Rewire actions while preserving views**

Use `apply_patch` to translate AppModel actionable projections into existing cards. Keep the current visual hierarchy, measured sizing, Markdown rendering, whole-surface double-click jump, and tail-free shape. Remove adapter-specific branching from views.

- [ ] **Step 4: Run tests green and commit**

```bash
swift test --filter 'ApprovalCard|QuestionCard|BubbleQueue|BubbleJump|SpeechBubble|ApprovalFlow|QuestionFlow|NotificationFlow'
git add VibePetApp/Bubble VibePetApp/Pet Tests
git commit -m "Route normalized decisions through pet-adjacent bubbles" \
  -m "Constraint: Dashboard and bubbles never show the same actionable session simultaneously." \
  -m "Confidence: high" \
  -m "Scope-risk: broad" \
  -m "Tested: bubble UI, queue, jump, and interactive E2E suites"
```

### Task 5: Present all integrations in Settings, onboarding, and menu bar

**Files:**
- Modify: `VibePetApp/Settings/*.swift`, `VibePetApp/Onboarding/OnboardingFlow.swift`, `VibePetApp/MenuBar/StatusItemController.swift`
- Create/adapt: `VibePetApp/Settings/AppearanceSettingsPane.swift`
- Modify: `VibePetApp/AppLocalizer.swift`, `VibePetApp/Resources/*/Localizable.strings`
- Test: settings, localization, onboarding, coordinator, and menu suites

- [ ] **Step 1: Add tool-matrix presentation tests**

For all integrations, test detected/installing/installed/outdated/needs-trust/error/uninstalled states, successful operation intent changes, failure preservation, optional onboarding selection, launch-at-login, notification/suppression preferences, update controls, and fixed language self-names.

- [ ] **Step 2: Run settings tests red**

```bash
swift test --filter 'HookInstallCoordinator|Settings|Onboarding|AppLocalizer|StatusItemController'
```

Expected: old two-tool settings and onboarding models omit new agents/services.

- [ ] **Step 3: Adapt upstream settings semantics**

Use upstream `SettingsView.swift`, `AppearanceSettingsPane.swift`, and `HookInstallationCoordinator.swift` as behavior sources. Keep VibePet layout and branding. Render fact-driven rows for every integration, preserve explicit install/repair/uninstall actions, and add service preferences without hiding technical trust guidance.

- [ ] **Step 4: Merge localized resources**

Import upstream English, Simplified Chinese, and Traditional Chinese keys into VibePet resources, then update `AppLocalizer` call sites. Product-facing strings use VibePet; native agent names and config identifiers remain exact.

- [ ] **Step 5: Run tests green and commit**

```bash
swift test --filter 'HookInstallCoordinator|Settings|Onboarding|AppLocalizer|StatusItemController'
git add VibePetApp/Settings VibePetApp/Onboarding VibePetApp/MenuBar VibePetApp/AppLocalizer.swift VibePetApp/Resources Tests/VibePetAppTests
git commit -m "Expose full integration control through VibePet settings" \
  -m "Constraint: Rows reflect disk facts and explicit intent; startup refresh is read-only." \
  -m "Confidence: high" \
  -m "Scope-risk: broad" \
  -m "Tested: settings, onboarding, localization, coordinator, and menu suites"
```

### Task 6: Port non-notch harness and parity diagnostics

**Files:**
- Create: `VibePetApp/Harness/HarnessLaunchConfiguration.swift`, `HarnessRuntimeMonitor.swift`, `HarnessArtifactRecorder.swift`
- Test: matching upstream Harness tests

- [ ] **Step 1: Port harness tests**

Copy `HarnessLaunchConfigurationTests.swift` and `HarnessRuntimeMonitorTests.swift`, rename modules/product paths, and add assertions that harness startup targets the pet window rather than a notch surface.

- [ ] **Step 2: Run harness tests red**

```bash
swift test --filter Harness
```

Expected: harness types are absent.

- [ ] **Step 3: Import non-notch harness services**

Copy the three pinned Harness App files. Remove island/notch scenario dependencies; retain launch parsing, runtime health monitoring, and artifact recording. Point artifacts at VibePet UI and session diagnostics.

- [ ] **Step 4: Run tests green and commit**

```bash
swift test --filter Harness
git add VibePetApp/Harness Tests/VibePetAppTests
git commit -m "Add repeatable diagnostics for the pet runtime" \
  -m "Constraint: Harness behavior observes VibePet and imports no notch UI." \
  -m "Confidence: high" \
  -m "Scope-risk: moderate" \
  -m "Tested: harness launch and runtime monitor suites"
```

### Task 7: Remove obsolete runtime paths and complete the parity ledger

**Files:**
- Delete: superseded VibePet-only adapter, bridge, installer, and state files identified by compiler/reference audit
- Update: `docs/upstream/open-vibe-island.md`
- Create: `docs/open-vibe-island-parity.md`
- Update: `openspec/changes/present-upstream-runtime-by-pet/tasks.md`

- [ ] **Step 1: Audit references before deletion**

```bash
rg -n 'ToolKind|BridgeEnvelope|BridgeResponse|HookRuntime|SessionModels|BridgeServerHost' VibePetCore VibePetApp VibePetHooks VibePetSetup Tests
```

Classify each remaining match as migrated contract, pet adapter, or obsolete path. Delete only obsolete paths after their consumers are gone.

- [ ] **Step 2: Prove notch exclusion and source attribution**

```bash
rg -n 'NotchShape|V6NotchContent|IslandChromeMetrics|OpenedIslandSurfaceShape' VibePetCore VibePetApp VibePetHooks VibePetSetup
git ls-files | rg '^open-vibe-island/'
```

Expected: no notch source references; the nested upstream clone is not tracked.

- [ ] **Step 3: Write the parity ledger**

Create `docs/open-vibe-island-parity.md` with every upstream product capability marked `ported`, `pet-adapted`, or `excluded-notch`, and link each row to a VibePet source path and test. Update the attribution table with every copied file and meaningful deviation.

- [ ] **Step 4: Normalize the three known legacy main specs**

Update these existing main specs to contain `## Purpose` and `## Requirements` wrappers without changing requirement meaning:

```text
openspec/specs/codex-pet-import/spec.md
openspec/specs/codex-pet-source/spec.md
openspec/specs/sprite-animation/spec.md
```

Run:

```bash
openspec validate codex-pet-import --strict
openspec validate codex-pet-source --strict
openspec validate sprite-animation --strict
```

Expected: all three specifications validate. This closes the pre-existing blocker to the final `--specs --strict` gate.

- [ ] **Step 5: Compile after deletion and commit**

```bash
swift build
git add -A VibePetCore VibePetApp VibePetHooks VibePetSetup Tests docs openspec/changes/present-upstream-runtime-by-pet
git commit -m "Remove the superseded pre-parity runtime" \
  -m "Constraint: Only paths replaced by the normalized upstream runtime are removed." \
  -m "Confidence: medium" \
  -m "Scope-risk: broad" \
  -m "Tested: swift build; reference, notch, and tracked-upstream audits"
```

### Task 8: Run Gate C after M5 and M6

**Files:**
- Update: all three active OpenSpec task files
- Update: `docs/open-vibe-island-parity.md`, `docs/upstream/open-vibe-island.md`

- [ ] **Step 1: Run the complete paired gate**

```bash
swift build
swift test
openspec validate replace-agent-runtime-and-integrations --strict
openspec validate add-session-continuity-and-services --strict
openspec validate present-upstream-runtime-by-pet --strict
openspec validate --specs --strict
git diff --check
```

Expected: build succeeds; complete suite has zero failures; every active change and main spec validates; diff check is clean.

- [ ] **Step 2: Run boundary audits**

```bash
rg -n 'import (AppKit|SwiftUI|Sparkle|MarkdownUI)' VibePetCore VibePetHooks VibePetSetup
rg -n 'NotchShape|V6NotchContent|IslandChromeMetrics|OpenedIslandSurfaceShape' VibePetCore VibePetApp
git ls-files | rg '^open-vibe-island/'
```

Expected: no Core/executable UI imports, no notch source, and no tracked nested clone.

- [ ] **Step 3: Perform manual macOS verification**

Verify pet launch, drag, transparent click-through, cross-Space behavior, dashboard anchoring, all decision/question actions, session switching, exact terminal jump, notification sound/suppression, settings/onboarding, update UI, Watch relay controls, and at least one fixture or isolated install flow for every agent. Do not install into real user config during automation.

- [ ] **Step 4: Reconcile evidence and commit Gate C**

Mark task checkboxes only where evidence exists; record intentional differences as presentation/branding/notch exclusions.

```bash
git add docs openspec
git commit -m "Prove full upstream parity around the pet surface" \
  -m "Constraint: Gate C covers M5 and M6 together as requested." \
  -m "Confidence: high" \
  -m "Scope-risk: broad" \
  -m "Directive: Future upstream syncs must update the pinned source ledger before code import." \
  -m "Tested: swift build; full swift test; strict OpenSpec; boundary, parity, and manual UI audits"
```

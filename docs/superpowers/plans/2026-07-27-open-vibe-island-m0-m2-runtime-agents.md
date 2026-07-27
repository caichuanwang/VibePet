# Open Vibe Island M0-M2 Runtime and Agents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace VibePet's agent runtime with the pinned Open Vibe Island model and support every approved coding-agent integration while preserving the pet subsystem.

**Architecture:** Import the upstream session model, reducer, bridge protocol, adapters, installers, Hook CLI, and Setup CLI into VibePet-owned targets. Keep product-facing names and paths as VibePet, keep Core UI-independent, and connect the new AppModel to the existing pet presentation through one state projection boundary.

**Tech Stack:** Swift 6.2, SwiftPM, Foundation Unix sockets, AppKit/SwiftUI in `VibePetApp`, XCTest, OpenSpec, GPL-3.0.

**Spec:** `docs/superpowers/specs/2026-07-27-open-vibe-island-full-parity-design.md`

---

## File Structure

**Create or replace in Core**

| Path | Responsibility |
|---|---|
| `VibePetCore/Session/AgentSession.swift` | Upstream-normalized `AgentTool`, session phases, metadata, decisions, and jump targets. |
| `VibePetCore/Session/AgentEvent.swift` | Normalized event vocabulary and Codable event payloads. |
| `VibePetCore/Session/SessionState.swift` | Single pure reducer and derived session counts. |
| `VibePetCore/Bridge/BridgeTransport.swift` | Commands, responses, request correlation, and bounded transport models. |
| `VibePetCore/Bridge/BridgeCommandClient.swift` | Local command client used by hooks and services. |
| `VibePetCore/Integration/*.swift` | Agent intent, configuration roots, installers, managers, health, and usage support. |
| `VibePetCore/Adapters/*.swift` | Claude, Codex, Cursor, Gemini, OpenCode, Kimi, and compatible-hook decoders. |
| `VibePetApp/AppModel.swift` | Canonical observable session owner and bridge command router. |
| `VibePetApp/AppModelTypes.swift` | App-facing service protocols and immutable projections. |
| `VibePetApp/Resources/vibepet-opencode.js` | Renamed and attributed OpenCode plugin resource. |
| `docs/upstream/open-vibe-island.md` | Upstream commit, license, imported file map, exclusions, and VibePet deviations. |

**Replace executable entry points**

| Path | Responsibility |
|---|---|
| `VibePetHooks/main.swift` | Multi-agent Hook CLI with fail-open output behavior. |
| `VibePetSetup/main.swift` | Multi-agent install, uninstall, repair, status, and diagnostics CLI. |

**Port or rewrite tests**

| Destination | Upstream source |
|---|---|
| `Tests/VibePetCoreTests/AgentIntentStoreTests.swift` | `open-vibe-island/Tests/OpenIslandCoreTests/AgentIntentStoreTests.swift` |
| `Tests/VibePetCoreTests/SessionStateTests.swift` | `open-vibe-island/Tests/OpenIslandCoreTests/SessionStateTests.swift` plus retained VibePet reducer regressions |
| `Tests/VibePetCoreTests/BridgeServerJumpTargetMergeTests.swift` | matching upstream test |
| `Tests/VibePetCoreTests/BridgeServerPendingContextCleanupTests.swift` | matching upstream test |
| `Tests/VibePetCoreTests/*HooksTests.swift` | Claude, Codex, Cursor, Gemini, and Kimi upstream suites |
| `Tests/VibePetCoreTests/OpenCodeHooksTests.swift` | OpenCode payload/plugin contract tests |
| `Tests/VibePetSetupTests/*InstallationTests.swift` | every imported installer/manager contract |
| `Tests/E2E/MultiAgentHookCLITests.swift` | real executable selection and fail-open paths |

### Task 1: Record the upstream baseline and protected VibePet surface

**Files:**
- Create: `docs/upstream/open-vibe-island.md`
- Create: `openspec/changes/replace-agent-runtime-and-integrations/`
- Verify: existing pet, geometry, import, and window tests

- [ ] **Step 1: Record the source contract**

Create `docs/upstream/open-vibe-island.md` with this initial contract, then append the exact imported-file table as tasks land:

```markdown
# Open Vibe Island Source Attribution

- Upstream: https://github.com/Octane0411/open-vibe-island
- Baseline commit: 1e26dfc8d42bec0da7627986d49c2320b2593610
- License: GPL-3.0
- VibePet license: GPL-3.0

## Product Adaptation

VibePet uses the upstream agent-session runtime and services with a pet-centered
presentation. Notch geometry, notch windows, and notch-only views are excluded.

## Imported Files

| Upstream path | VibePet path | Adaptation |
|---|---|---|
```

- [ ] **Step 2: Create the OpenSpec change**

Run:

```bash
openspec new change replace-agent-runtime-and-integrations
```

Write proposal/design/specs/tasks for M0-M2 using Sections 3, 5-9, and M0-M2 of the approved design. Validate with:

```bash
openspec validate replace-agent-runtime-and-integrations --strict
```

Expected: `Change 'replace-agent-runtime-and-integrations' is valid`.

- [ ] **Step 3: Record the protected baseline**

Run only the retained pet surface tests:

```bash
swift test --filter 'PetAsset|PetPackage|Sprite|PetSelection|PetWindow|OverlayWindow|BubbleAnchor|ScreenSnap'
```

Expected: every selected test passes. Record the command and count under `## Protected VibePet Baseline` in the attribution document.

- [ ] **Step 4: Commit M0 metadata**

```bash
git add docs/upstream/open-vibe-island.md openspec/changes/replace-agent-runtime-and-integrations
git commit -m "Pin the upstream runtime used for VibePet parity" \
  -m "Constraint: Keep the pet presentation and exclude notch-only source." \
  -m "Confidence: high" \
  -m "Scope-risk: narrow" \
  -m "Tested: protected pet surface test filter; strict OpenSpec validation"
```

### Task 2: Upgrade the package contract without leaking dependencies into Core

**Files:**
- Modify: `Package.swift`
- Create: `VibePetApp/Resources/en.lproj/Localizable.strings`
- Test: package graph and compile smoke

- [ ] **Step 1: Add a package-graph assertion**

Create a shell-verifiable expectation before editing:

```bash
swift package describe --type json > /tmp/vibepet-package-before.json
rg '"name" : "VibePetCore"' /tmp/vibepet-package-before.json
```

Expected: Core exists and has no product dependencies.

- [ ] **Step 2: Update the package manifest**

Apply these manifest-level changes:

```swift
// swift-tools-version: 6.2

dependencies: [
    .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
]
```

Set `defaultLocalization: "en"`. Keep `VibePetCore`, `VibePetHooks`, and `VibePetSetup` dependency-free. Add `MarkdownUI` and `Sparkle` only to `VibePetApp`; add `.process("Resources")` only to `VibePetApp`.

Create the initial resource file so the package graph remains valid before later localization work:

```text
"app.name" = "VibePet";
```

- [ ] **Step 3: Verify dependency boundaries**

Run:

```bash
swift package describe --type json > /tmp/vibepet-package-after.json
swift build
```

Expected: package description resolves; all four products compile; Core has no MarkdownUI or Sparkle dependency.

- [ ] **Step 4: Commit the package boundary**

```bash
git add Package.swift Package.resolved VibePetApp/Resources
git commit -m "Prepare the app target for upstream runtime services" \
  -m "Constraint: Markdown and updater dependencies remain App-only." \
  -m "Confidence: high" \
  -m "Scope-risk: moderate" \
  -m "Tested: swift package describe; swift build"
```

### Task 3: Replace the session vocabulary and reducer

**Files:**
- Create: `VibePetCore/Session/AgentSession.swift`
- Replace: `VibePetCore/Session/AgentEvent.swift`
- Replace: `VibePetCore/Session/SessionState.swift`
- Delete after consumers move: `VibePetCore/Session/SessionModels.swift`
- Test: `Tests/VibePetCoreTests/SessionStateTests.swift`

- [ ] **Step 1: Port the upstream reducer tests first**

Copy the upstream tests, change module imports, and retain VibePet tests covering fail-open decisions, duplicate events, liveness misses, discovered idle sessions, and pet visual-state priority:

```bash
cp open-vibe-island/Tests/OpenIslandCoreTests/SessionStateTests.swift /tmp/UpstreamSessionStateTests.swift
```

Use `apply_patch` to merge those cases into `Tests/VibePetCoreTests/SessionStateTests.swift` with `import VibePetCore`.

- [ ] **Step 2: Run the merged suite red**

```bash
swift test --filter SessionStateTests
```

Expected: compile failures for upstream `AgentTool`, metadata, phase, and event cases that are not yet present.

- [ ] **Step 3: Import and brand the runtime model**

Mechanically copy these pinned files, then use `apply_patch` for VibePet-specific differences:

```bash
cp open-vibe-island/Sources/OpenIslandCore/AgentSession.swift VibePetCore/Session/AgentSession.swift
cp open-vibe-island/Sources/OpenIslandCore/AgentEvent.swift VibePetCore/Session/AgentEvent.swift
cp open-vibe-island/Sources/OpenIslandCore/SessionState.swift VibePetCore/Session/SessionState.swift
perl -pi -e 's/OpenIslandCore/VibePetCore/g; s/Open Island/VibePet/g' \
  VibePetCore/Session/AgentSession.swift \
  VibePetCore/Session/AgentEvent.swift \
  VibePetCore/Session/SessionState.swift
```

Preserve the exact `AgentTool` cases: `claudeCode`, `codex`, `geminiCLI`, `openCode`, `qoder`, `qwenCode`, `factory`, `codebuddy`, `cursor`, and `kimiCLI`. Adapt pet visual-state derivation as an extension, not a second session store.

- [ ] **Step 4: Run the focused reducer suite green**

```bash
swift test --filter SessionStateTests
```

Expected: all reducer tests pass with zero failures.

- [ ] **Step 5: Commit the canonical model**

```bash
git add VibePetCore/Session Tests/VibePetCoreTests/SessionStateTests.swift
git commit -m "Use one upstream-compatible session reducer" \
  -m "Constraint: Pet state is derived from sessions and never becomes a second writer." \
  -m "Confidence: high" \
  -m "Scope-risk: broad" \
  -m "Tested: SessionStateTests"
```

### Task 4: Replace bridge models and transport behavior

**Files:**
- Replace: `VibePetCore/Bridge/BridgeServer.swift`
- Create: `VibePetCore/Bridge/BridgeTransport.swift`
- Create: `VibePetCore/Bridge/BridgeCommandClient.swift`
- Modify or remove after migration: `BridgeClient.swift`, `BridgeEnvelope.swift`, `BridgeResponse.swift`, `BridgeSocketIO.swift`, `HookRuntime.swift`
- Test: bridge hardening, merge, cancellation, and E2E decision suites

- [ ] **Step 1: Port missing bridge tests**

Copy and rename:

```bash
cp open-vibe-island/Tests/OpenIslandCoreTests/BridgeServerJumpTargetMergeTests.swift Tests/VibePetCoreTests/BridgeServerJumpTargetMergeTests.swift
cp open-vibe-island/Tests/OpenIslandCoreTests/BridgeServerPendingContextCleanupTests.swift Tests/VibePetCoreTests/BridgeServerPendingContextCleanupTests.swift
perl -pi -e 's/OpenIslandCore/VibePetCore/g' Tests/VibePetCoreTests/BridgeServer*Tests.swift
```

Retain existing `M1BridgeHardeningTests`, `BridgeRoundTripTests`, and E2E approval/question fail-open cases.

- [ ] **Step 2: Run bridge tests red**

```bash
swift test --filter 'Bridge|HookRuntime|ApprovalFlow|QuestionFlow'
```

Expected: new upstream command/response types fail to compile before import.

- [ ] **Step 3: Import the bridge runtime**

```bash
cp open-vibe-island/Sources/OpenIslandCore/BridgeServer.swift VibePetCore/Bridge/BridgeServer.swift
cp open-vibe-island/Sources/OpenIslandCore/BridgeTransport.swift VibePetCore/Bridge/BridgeTransport.swift
cp open-vibe-island/Sources/OpenIslandCore/BridgeCommandClient.swift VibePetCore/Bridge/BridgeCommandClient.swift
cp open-vibe-island/Sources/OpenIslandCore/LocalBridgeClient.swift VibePetCore/Bridge/LocalBridgeClient.swift
perl -pi -e 's/OpenIslandCore/VibePetCore/g; s/Open Island/VibePet/g; s/open-island/vibepet/g' VibePetCore/Bridge/*.swift
```

Use `apply_patch` to preserve VibePet's bounded frames, request-ID matching, SIGPIPE handling, restrictive support-directory permissions, and tool-specific decision budgets wherever they are stricter than upstream.

- [ ] **Step 4: Run bridge tests green**

```bash
swift test --filter 'Bridge|HookRuntime|ApprovalFlow|QuestionFlow'
```

Expected: all selected tests pass and missing-app cases return within existing deadlines.

- [ ] **Step 5: Commit bridge replacement**

```bash
git add VibePetCore/Bridge Tests/VibePetCoreTests Tests/E2E
git commit -m "Align bridge commands with the upstream agent runtime" \
  -m "Constraint: Every transport failure must preserve native tool flow." \
  -m "Confidence: high" \
  -m "Scope-risk: broad" \
  -m "Tested: bridge, hook runtime, approval, and question suites"
```

### Task 5: Introduce the canonical AppModel without replacing pet windows

**Files:**
- Create: `VibePetApp/AppModel.swift`
- Create: `VibePetApp/AppModelTypes.swift`
- Modify: `VibePetApp/main.swift`
- Modify: `VibePetApp/Bridge/BridgeServerHost.swift`
- Modify: `VibePetApp/Pet/PetController.swift`
- Test: `Tests/VibePetAppTests/AppModelSessionListTests.swift`, existing flow tests

- [ ] **Step 1: Port AppModel ownership tests**

```bash
cp open-vibe-island/Tests/OpenIslandAppTests/AppModelSessionListTests.swift Tests/VibePetAppTests/AppModelSessionListTests.swift
perl -pi -e 's/OpenIslandApp/VibePetApp/g; s/OpenIslandCore/VibePetCore/g; s/Open Island/VibePet/g' Tests/VibePetAppTests/AppModelSessionListTests.swift
```

Add assertions that `PetController` receives projections but does not own a second mutable session dictionary.

- [ ] **Step 2: Run AppModel tests red**

```bash
swift test --filter 'AppModelSessionList|NotificationBubbleFlow|M3SessionOwnership'
```

Expected: compile failures because the upstream-shaped AppModel is absent.

- [ ] **Step 3: Import AppModel and isolate presentation effects**

```bash
cp open-vibe-island/Sources/OpenIslandApp/AppModel.swift VibePetApp/AppModel.swift
cp open-vibe-island/Sources/OpenIslandApp/AppModelTypes.swift VibePetApp/AppModelTypes.swift
perl -pi -e 's/OpenIslandCore/VibePetCore/g; s/Open Island/VibePet/g; s/OpenIsland/VibePet/g' VibePetApp/AppModel*.swift
```

Use `apply_patch` to remove notch/overlay fields and expose callbacks or immutable projections consumed by the existing `PetController`, Dashboard, and bubble surfaces. Route `BridgeServerHost` through AppModel rather than maintaining its own session owner. M3/M4 services that are not imported yet use explicit no-op protocols defined in `AppModelTypes.swift`, for example:

```swift
protocol SessionDiscoveryCoordinating: Sendable {
    func start() async
    func stop() async
}

struct DisabledSessionDiscoveryCoordinator: SessionDiscoveryCoordinating {
    func start() async {}
    func stop() async {}
}
```

Replace these no-op dependencies when the corresponding M3/M4 tasks land; do not leave undefined references to upstream services.

- [ ] **Step 4: Run ownership tests green**

```bash
swift test --filter 'AppModelSessionList|NotificationBubbleFlow|M3SessionOwnership'
```

Expected: all selected tests pass; one canonical session collection is observable.

- [ ] **Step 5: Commit AppModel ownership**

```bash
git add VibePetApp/AppModel* VibePetApp/main.swift VibePetApp/Bridge/BridgeServerHost.swift VibePetApp/Pet/PetController.swift Tests/VibePetAppTests
git commit -m "Make AppModel the single session-state owner" \
  -m "Constraint: PetController renders state but cannot mutate a parallel session collection." \
  -m "Confidence: high" \
  -m "Scope-risk: broad" \
  -m "Tested: AppModel ownership and notification flow suites"
```

### Task 6: Port shared integration intent, health, and configuration roots

**Files:**
- Create: `VibePetCore/Integration/AgentHookIntent.swift`
- Create: `VibePetCore/Integration/AgentIntentStore.swift`
- Create: `VibePetCore/Integration/ClaudeConfigDirectory.swift`
- Replace or adapt: `VibePetCore/Install/HookHealthCheck.swift`, `HooksBinaryLocator.swift`, `HookSkipConfiguration.swift`
- Test: corresponding upstream tests plus retained installer hardening

- [ ] **Step 1: Port intent and shared utility tests**

```bash
cp open-vibe-island/Tests/OpenIslandCoreTests/AgentIntentStoreTests.swift Tests/VibePetCoreTests/AgentIntentStoreTests.swift
cp open-vibe-island/Tests/OpenIslandCoreTests/HookSkipConfigurationTests.swift Tests/VibePetCoreTests/HookSkipConfigurationTests.swift
cp open-vibe-island/Tests/OpenIslandCoreTests/HooksBinaryLocatorTests.swift Tests/VibePetCoreTests/HooksBinaryLocatorTests.swift
perl -pi -e 's/OpenIslandCore/VibePetCore/g; s/Open Island/VibePet/g' Tests/VibePetCoreTests/{AgentIntentStore,HookSkipConfiguration,HooksBinaryLocator}Tests.swift
```

- [ ] **Step 2: Run focused tests red**

```bash
swift test --filter 'AgentIntentStore|HookSkipConfiguration|HooksBinaryLocator|HookHealthCheck'
```

Expected: upstream intent/configuration types are absent.

- [ ] **Step 3: Import shared integration files**

Copy `AgentHookIntent.swift`, `AgentIntentStore.swift`, `ClaudeConfigDirectory.swift`, `HookHealthCheck.swift`, `HookSkipConfiguration.swift`, and `HooksBinaryLocator.swift` from `open-vibe-island/Sources/OpenIslandCore/` into `VibePetCore/Integration/`, then mechanically rename modules and managed binary paths to VibePet. Use `apply_patch` to keep all filesystem and environment inputs injectable.

- [ ] **Step 4: Run focused tests green and commit**

```bash
swift test --filter 'AgentIntentStore|HookSkipConfiguration|HooksBinaryLocator|HookHealthCheck|M5InstallerHardening'
git add VibePetCore/Integration Tests/VibePetCoreTests Tests/VibePetSetupTests
git commit -m "Unify integration intent and health across agents" \
  -m "Constraint: Health reads are side-effect free and tests use temporary roots." \
  -m "Confidence: high" \
  -m "Scope-risk: moderate" \
  -m "Tested: intent, health, locator, skip, and installer hardening suites"
```

### Task 7: Port Claude Code and Claude-compatible agents

**Files:**
- Create/adapt: Claude hooks, installer, installation manager, status-line manager, usage files
- Modify: `VibePetHooks/main.swift`, `VibePetSetup/main.swift`
- Test: Claude, Qoder, Qwen, Factory/Droid, CodeBuddy fixtures

- [ ] **Step 1: Port Claude tests and add compatibility-source table cases**

Copy upstream `ClaudeHooksTests.swift` and `ClaudeUsageTests.swift`. Add table-driven Hook CLI cases for sources `claude`, `qoder`, `qwen`, `factory`, `droid`, and `codebuddy`, asserting they decode through the Claude format while retaining their distinct `AgentTool`.

- [ ] **Step 2: Run Claude-family tests red**

```bash
swift test --filter 'Claude|Qoder|Qwen|Factory|Droid|CodeBuddy'
```

Expected: missing upstream payload, usage, and installer types.

- [ ] **Step 3: Import the Claude boundary**

Copy these upstream Core files into `VibePetCore/Adapters/` or `VibePetCore/Integration/` according to responsibility: `ClaudeHooks.swift`, `ClaudeHookInstaller.swift`, `ClaudeHookInstallationManager.swift`, `ClaudeStatusLineInstallationManager.swift`, and `ClaudeUsage.swift`. Rename executable commands and managed markers to VibePet. Configure each compatible agent with its upstream directory and source flag; do not duplicate payload parsing.

- [ ] **Step 4: Run Claude-family tests green and commit**

```bash
swift test --filter 'Claude|Qoder|Qwen|Factory|Droid|CodeBuddy'
git add VibePetCore VibePetHooks VibePetSetup Tests
git commit -m "Support Claude and its compatible coding agents" \
  -m "Constraint: Compatible tools share decoding but retain tool identity and config roots." \
  -m "Confidence: high" \
  -m "Scope-risk: broad" \
  -m "Tested: Claude-family adapters, usage, installers, and Hook CLI fixtures"
```

### Task 8: Port Codex hooks, usage, and app-server metadata

**Files:**
- Create/adapt: `CodexHooks.swift`, `CodexHookInstaller.swift`, `CodexHookInstallationManager.swift`, `CodexUsage.swift`, `CodexAppServer.swift`, `CodexSessionTracking.swift`
- Test: matching upstream Core tests and retained Codex E2E tests

- [ ] **Step 1: Port Codex upstream tests**

Copy `CodexHooksTests.swift`, `CodexUsageTests.swift`, `CodexAppServerBufferTests.swift`, `CodexAppServerTimeoutTests.swift`, and `CodexSessionTrackingTests.swift` into `Tests/VibePetCoreTests/` with module renames.

- [ ] **Step 2: Run Codex tests red**

```bash
swift test --filter 'Codex'
```

Expected: upstream app-server and tracking types are missing.

- [ ] **Step 3: Import the Codex boundary**

Copy the six pinned upstream source files into the matching Adapter/Integration/Session directories. Preserve VibePet's stable helper path, request correlation, trust state, and config preservation tests while replacing legacy VibePet-only payload models.

- [ ] **Step 4: Run Codex tests green and commit**

```bash
swift test --filter 'Codex'
git add VibePetCore VibePetHooks VibePetSetup Tests
git commit -m "Adopt the complete Codex integration boundary" \
  -m "Constraint: Codex hooks, app-server metadata, and usage converge on one session identity." \
  -m "Confidence: high" \
  -m "Scope-risk: broad" \
  -m "Tested: all Codex unit, installer, bridge, and E2E suites"
```

### Task 9: Port Cursor, Gemini CLI, and Kimi CLI

**Files:**
- Create/adapt: `CursorHooks.swift`, `CursorHookInstaller.swift`, `CursorHookInstallationManager.swift`, `GeminiHooks.swift`, `GeminiHookInstaller.swift`, `GeminiHookInstallationManager.swift`, `KimiHookInstaller.swift`, `KimiHookInstallationManager.swift`
- Test: Cursor, Gemini, Kimi upstream suites plus temporary-directory installer tests

- [ ] **Step 1: Port upstream hook tests and write installer-preservation cases**

Copy `CursorHooksTests.swift`, `GeminiHooksTests.swift`, and `KimiHooksTests.swift`. Add a temporary-root install/uninstall round trip for each manager, asserting unrelated JSON/TOML fields are byte-equivalent after uninstall.

- [ ] **Step 2: Run the new suites red**

```bash
swift test --filter 'Cursor|Gemini|Kimi'
```

Expected: missing hook and installation-manager types.

- [ ] **Step 3: Import and brand the three integrations**

Copy the pinned upstream Cursor, Gemini, and Kimi source files into Adapter/Integration directories. Replace Open Island product names, commands, support paths, and manifest names with VibePet; retain native event names and native config formats unchanged.

- [ ] **Step 4: Run suites green and commit**

```bash
swift test --filter 'Cursor|Gemini|Kimi'
git add VibePetCore VibePetHooks VibePetSetup Tests
git commit -m "Add Cursor Gemini and Kimi integrations" \
  -m "Constraint: Native config formats remain tool-specific and preserve user-authored entries." \
  -m "Confidence: high" \
  -m "Scope-risk: broad" \
  -m "Tested: Cursor, Gemini, and Kimi hooks and temporary-root installers"
```

### Task 10: Port the OpenCode plugin integration

**Files:**
- Create: `VibePetCore/Adapters/OpenCodeHooks.swift`
- Create: `VibePetCore/Integration/OpenCodePluginInstallationManager.swift`
- Create: `VibePetApp/Resources/vibepet-opencode.js`
- Test: `Tests/VibePetCoreTests/OpenCodeHooksTests.swift`, plugin installer tests, E2E bridge cases

- [ ] **Step 1: Write plugin contract tests**

Test that the bundled plugin resource exists, contains the VibePet socket/command marker, maps session start/end, permission, and question events, and exits safely when the socket is absent.

- [ ] **Step 2: Run OpenCode tests red**

```bash
swift test --filter OpenCode
```

Expected: plugin resource and OpenCode payload types are missing.

- [ ] **Step 3: Import the plugin boundary**

```bash
cp open-vibe-island/Sources/OpenIslandCore/OpenCodeHooks.swift VibePetCore/Adapters/OpenCodeHooks.swift
cp open-vibe-island/Sources/OpenIslandCore/OpenCodePluginInstallationManager.swift VibePetCore/Integration/OpenCodePluginInstallationManager.swift
cp open-vibe-island/Sources/OpenIslandApp/Resources/open-island-opencode.js VibePetApp/Resources/vibepet-opencode.js
perl -pi -e 's/OpenIslandCore/VibePetCore/g; s/Open Island/VibePet/g; s/open-island/vibepet/g' VibePetCore/Adapters/OpenCodeHooks.swift VibePetCore/Integration/OpenCodePluginInstallationManager.swift VibePetApp/Resources/vibepet-opencode.js
```

Use `apply_patch` to resolve VibePet socket paths and package resources explicitly.

- [ ] **Step 4: Run OpenCode tests green and commit**

```bash
swift test --filter OpenCode
git add VibePetCore VibePetApp/Resources Tests
git commit -m "Integrate OpenCode through the bundled local plugin" \
  -m "Constraint: The plugin communicates only with the local VibePet bridge and fails open." \
  -m "Confidence: high" \
  -m "Scope-risk: broad" \
  -m "Tested: OpenCode payload, plugin resource, installer, and bridge tests"
```

### Task 11: Complete the multi-agent Hook and Setup CLIs

**Files:**
- Replace: `VibePetHooks/main.swift`
- Replace: `VibePetSetup/main.swift`
- Test: `Tests/E2E/MultiAgentHookCLITests.swift`, Setup command parser tests

- [ ] **Step 1: Write CLI table tests**

Cover every source selector and Setup verb:

```swift
let hookSources = ["codex", "claude", "qoder", "qwen", "factory", "droid", "codebuddy", "cursor", "gemini", "kimi"]
let setupVerbs = ["install", "uninstall", "repair", "status"]
```

For every source, assert missing input, malformed input, and missing app exit promptly without blocking. For every Setup verb and agent, construct only temporary config roots.

- [ ] **Step 2: Run CLI tests red**

```bash
swift test --filter 'MultiAgentHookCLI|SetupCLI'
```

Expected: current entry points do not recognize all selectors and verbs.

- [ ] **Step 3: Import and adapt both entry points**

Copy `OpenIslandHooksCLI.swift` and `OpenIslandSetupCLI.swift` into the VibePet executable targets, rename the `@main` types, module imports, executable names, support paths, socket names, messages, and resource lookup. Keep the upstream source-selection table and VibePet's stricter fail-open decision budgets.

- [ ] **Step 4: Run CLI tests green and commit**

```bash
swift test --filter 'MultiAgentHookCLI|SetupCLI|M1HookCLIFailOpen'
git add VibePetHooks VibePetSetup Tests/E2E Tests/VibePetSetupTests
git commit -m "Expose every supported agent through VibePet CLI tools" \
  -m "Constraint: Hook failures never block the native agent; Setup tests never touch real config." \
  -m "Confidence: high" \
  -m "Scope-risk: broad" \
  -m "Tested: multi-agent Hook CLI, Setup CLI, and fail-open E2E suites"
```

### Task 12: Run Gate A after M1 and M2

**Files:**
- Update: `openspec/changes/replace-agent-runtime-and-integrations/tasks.md`
- Update: `docs/upstream/open-vibe-island.md`

- [ ] **Step 1: Run the complete paired gate**

```bash
swift build
swift test
openspec validate replace-agent-runtime-and-integrations --strict
git diff --check
rg -n 'import (AppKit|SwiftUI|Sparkle|MarkdownUI)' VibePetCore VibePetHooks VibePetSetup
```

Expected: build succeeds; complete suite has zero failures; OpenSpec is valid; diff check is clean; the import audit returns no matches.

- [ ] **Step 2: Audit the agent matrix**

Confirm the ten `AgentTool` cases each have adapter behavior, install/status behavior, fixture coverage, and Hook CLI routing. Confirm Claude usage bridge is represented as an integration capability.

- [ ] **Step 3: Mark M0-M2 evidence and commit**

```bash
git add openspec/changes/replace-agent-runtime-and-integrations/tasks.md docs/upstream/open-vibe-island.md
git commit -m "Close the runtime and agent integration gate" \
  -m "Constraint: Gate A covers M1 and M2 together as requested." \
  -m "Confidence: high" \
  -m "Scope-risk: broad" \
  -m "Tested: swift build; full swift test; strict OpenSpec; import and diff audits"
```

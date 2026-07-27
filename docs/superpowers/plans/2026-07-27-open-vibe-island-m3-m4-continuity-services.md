# Open Vibe Island M3-M4 Continuity and Services Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add upstream-equivalent session recovery, liveness, terminal integration, notifications, updates, Watch relay, and user-triggered Accessibility services to the M0-M2 runtime.

**Architecture:** Safe Core registries and bounded readers provide startup candidates; App-owned coordinators merge and publish them through the single reducer. Terminal, notification, updater, Watch, and Accessibility services remain injected effects outside canonical session state.

**Tech Stack:** Swift 6.2, SwiftPM, Foundation, AppKit, SQLite3, CoreGraphics/ApplicationServices, Sparkle, XCTest, OpenSpec.

**Spec:** `docs/superpowers/specs/2026-07-27-open-vibe-island-full-parity-design.md`

---

## File Structure

| Area | Create/adapt in VibePet | Pinned upstream source |
|---|---|---|
| Registries | `VibePetCore/Session/*SessionRegistry.swift` | Claude, Cursor, OpenCode registries |
| Discovery | `VibePetCore/Discovery/*.swift` | Claude transcript, Cursor transcript, workspace resolver, Codex tracking |
| Coordination | `VibePetApp/SessionDiscoveryCoordinator.swift`, `ProcessMonitoringCoordinator.swift` | matching App files |
| Terminal | `VibePetCore/Terminal/Warp*.swift`, `VibePetApp/Terminal/*.swift` | Warp reader/resolver and App terminal services |
| Notification | `VibePetApp/NotificationSoundService.swift`, foreground probe | matching App files |
| System services | `LaunchAtLoginService.swift`, `UpdateChecker.swift`, `KeystrokeInjector.swift` | matching App files |
| Watch | `VibePetCore/Watch/*.swift` | Watch endpoint and relay |

### Task 1: Specify safe persisted session projections

**Files:**
- Create: `openspec/changes/add-session-continuity-and-services/`
- Create: `VibePetCore/Session/ClaudeSessionRegistry.swift`
- Create: `VibePetCore/Session/CursorSessionRegistry.swift`
- Create: `VibePetCore/Session/OpenCodeSessionRegistry.swift`
- Test: matching upstream registry tests plus privacy exclusions

- [ ] **Step 1: Create and validate the OpenSpec change**

```bash
openspec new change add-session-continuity-and-services
openspec validate add-session-continuity-and-services --strict
```

Expected: strict validation succeeds after writing requirements for safe projections, discovery, liveness, services, and paired Gate B.

- [ ] **Step 2: Port registry tests before source**

Copy upstream `ClaudeSessionRegistryTests.swift` and `OpenCodeSessionRegistryTests.swift`; add Cursor parity and tests proving approval bodies, questions, request IDs, continuations, queues, timeouts, and UI state never serialize.

- [ ] **Step 3: Run registry tests red**

```bash
swift test --filter 'SessionRegistry'
```

Expected: missing registry record/store types.

- [ ] **Step 4: Import registries with VibePet storage paths**

Copy `ClaudeSessionRegistry.swift`, `CursorSessionRegistry.swift`, and `OpenCodeSessionRegistry.swift` from upstream into `VibePetCore/Session/`. Rename modules and support paths; keep versioned Codable records, atomic replacement, trimming, and corruption handling. Use one shared VibePet support root but separate explicit files.

- [ ] **Step 5: Run tests green and commit**

```bash
swift test --filter 'SessionRegistry'
git add VibePetCore/Session Tests/VibePetCoreTests openspec/changes/add-session-continuity-and-services
git commit -m "Persist only safe recent session projections" \
  -m "Constraint: Actionable payloads and continuations never reach disk." \
  -m "Confidence: high" \
  -m "Scope-risk: moderate" \
  -m "Tested: registry round-trip, trimming, corruption, and privacy suites"
```

### Task 2: Port bounded local discovery and workspace resolution

**Files:**
- Create: `VibePetCore/Discovery/ClaudeTranscriptDiscovery.swift`
- Create: `VibePetCore/Discovery/CursorTranscriptReader.swift`
- Create: `VibePetCore/Discovery/WorkspaceNameResolver.swift`
- Create: `VibePetCore/Discovery/TimedCache.swift`
- Test: fixture, symlink, size, age, and read-budget cases

- [ ] **Step 1: Write bounded-reader tests**

Create temp fixtures for a recent valid transcript, expired transcript, subagent transcript, symlink, oversized line, corrupt tail, and candidate count beyond the upstream cap. Inject filesystem reads and clock.

- [ ] **Step 2: Run discovery tests red**

```bash
swift test --filter 'Transcript|WorkspaceName|TimedCache|Discovery'
```

Expected: missing discovery readers and budget behavior.

- [ ] **Step 3: Import discovery sources**

Copy the four pinned upstream files into `VibePetCore/Discovery/`. Rename module/product strings only. Preserve bounded tail reads, symlink rejection, file-count/age limits, injectable clock/readers, and normalized workspace output.

- [ ] **Step 4: Run tests green and commit**

```bash
swift test --filter 'Transcript|WorkspaceName|TimedCache|Discovery'
git add VibePetCore/Discovery Tests/VibePetCoreTests
git commit -m "Discover recent local sessions within fixed budgets" \
  -m "Constraint: Discovery is local-only, bounded, symlink-safe, and fail-soft." \
  -m "Confidence: high" \
  -m "Scope-risk: moderate" \
  -m "Tested: transcript, cache, workspace, and discovery-boundary suites"
```

### Task 3: Port Codex tracking and app-server recovery

**Files:**
- Adapt from M2: `VibePetCore/Integration/CodexAppServer.swift`, `CodexSessionTracking.swift`, `CodexUsage.swift`
- Test: upstream buffer, timeout, tracking, and usage suites

- [ ] **Step 1: Add recovery-specific Codex cases**

Test bounded app-server buffering, absolute timeouts, metadata-only recovery, usage-field isolation, and exact-ID merge with hook-created sessions.

- [ ] **Step 2: Run Codex recovery tests red**

```bash
swift test --filter 'CodexAppServer|CodexSessionTracking|CodexUsage'
```

Expected: recovery and merge cases fail against the M2-only path.

- [ ] **Step 3: Adapt the imported Codex services**

Use `apply_patch` to feed app-server and local-history candidates into normalized discovery records rather than mutating AppModel directly. Keep response buffers bounded and isolate usage updates from lifecycle state.

- [ ] **Step 4: Run tests green and commit**

```bash
swift test --filter 'CodexAppServer|CodexSessionTracking|CodexUsage'
git add VibePetCore Tests/VibePetCoreTests
git commit -m "Recover Codex metadata without duplicating sessions" \
  -m "Constraint: Usage and app-server inputs cannot become competing lifecycle writers." \
  -m "Confidence: high" \
  -m "Scope-risk: moderate" \
  -m "Tested: Codex app-server, tracking, merge, timeout, and usage suites"
```

### Task 4: Introduce startup discovery and conservative merging

**Files:**
- Create: `VibePetApp/SessionDiscoveryCoordinator.swift`
- Modify: `VibePetApp/AppModel.swift`
- Test: `Tests/VibePetAppTests/SessionDiscoveryCoordinatorTests.swift`, AppModel session tests

- [ ] **Step 1: Write coordinator tests**

Cover missing/corrupt stores, exact-ID merge, precise terminal merge, unique normalized-cwd merge, ambiguous cwd separation, waiting-state downgrade, stale generation rejection, and rapid persistence coalescing.

- [ ] **Step 2: Run coordinator tests red**

```bash
swift test --filter 'SessionDiscoveryCoordinator|AppModelSessionList'
```

Expected: coordinator type and startup merge behavior are absent.

- [ ] **Step 3: Import and adapt the coordinator**

Copy upstream `SessionDiscoveryCoordinator.swift` into `VibePetApp/`. Rename product/module strings and inject registry/discovery/process readers. Publish accepted candidates only through AppModel and the single reducer. Preserve generation gates on startup and asynchronous persistence.

- [ ] **Step 4: Run tests green and commit**

```bash
swift test --filter 'SessionDiscoveryCoordinator|AppModelSessionList'
git add VibePetApp/SessionDiscoveryCoordinator.swift VibePetApp/AppModel.swift Tests/VibePetAppTests
git commit -m "Restore sessions through one conservative coordinator" \
  -m "Constraint: Ambiguous identity never merges and stale generations never publish." \
  -m "Confidence: high" \
  -m "Scope-risk: broad" \
  -m "Tested: discovery coordinator and AppModel session suites"
```

### Task 5: Port process monitoring and liveness reconciliation

**Files:**
- Replace: `VibePetApp/Bridge/ActiveAgentProcessDiscovery.swift`
- Create: `VibePetApp/ProcessMonitoringCoordinator.swift`
- Modify: `VibePetApp/AppModel.swift`
- Test: active process and liveness race suites

- [ ] **Step 1: Port upstream process tests and retain VibePet regressions**

Merge upstream `ActiveAgentProcessDiscoveryTests.swift` with VibePet cases for async `ps` reading, discovered-idle state, exact TTY matching, short gaps, hook placeholder replacement, and duplicate prevention.

- [ ] **Step 2: Run process tests red**

```bash
swift test --filter 'ActiveAgentProcessDiscovery|ProcessMonitoring|Liveness'
```

Expected: upstream process coordinator behavior is missing.

- [ ] **Step 3: Import both process services**

Copy upstream `ActiveAgentProcessDiscovery.swift` and `ProcessMonitoringCoordinator.swift`. Keep process execution injected and off-main-thread. Use process presence only for visibility/liveness; only real activity events mark a session running.

- [ ] **Step 4: Run tests green and commit**

```bash
swift test --filter 'ActiveAgentProcessDiscovery|ProcessMonitoring|Liveness'
git add VibePetApp Tests/VibePetAppTests
git commit -m "Reconcile process liveness without inventing activity" \
  -m "Constraint: Discovered process presence is visible but not running state." \
  -m "Confidence: high" \
  -m "Scope-risk: broad" \
  -m "Tested: process discovery, monitoring, liveness, and placeholder suites"
```

### Task 6: Port terminal metadata, Warp resolution, and attachment probes

**Files:**
- Create: `VibePetCore/Terminal/WarpProcessResolver.swift`, `WarpSQLiteReader.swift`
- Create: `VibePetApp/Terminal/TerminalSessionAttachmentProbe.swift`
- Adapt: `VibePetCore/Adapters/TerminalJumpCapture.swift`
- Test: upstream Warp and attachment suites

- [ ] **Step 1: Port terminal metadata tests**

Copy `WarpProcessResolverTests.swift`, `WarpSQLiteReaderTests.swift`, and `TerminalSessionAttachmentProbeTests.swift`; retain VibePet normalized-working-directory and exact-TTY tests.

- [ ] **Step 2: Run terminal metadata tests red**

```bash
swift test --filter 'Warp|TerminalSessionAttachment|TerminalJumpCapture'
```

Expected: Warp and attachment types are absent.

- [ ] **Step 3: Import the readers and probe**

Copy pinned upstream sources into the listed paths. Keep SQLite read-only, injectable file/database paths, bounded queries, and fail-soft returns. Feed precise metadata into fill-only `JumpTarget` merging.

- [ ] **Step 4: Run tests green and commit**

```bash
swift test --filter 'Warp|TerminalSessionAttachment|TerminalJumpCapture'
git add VibePetCore/Terminal VibePetCore/Adapters VibePetApp/Terminal Tests
git commit -m "Capture precise terminal attachment metadata" \
  -m "Constraint: Terminal enrichment is fill-only and all probes fail soft." \
  -m "Confidence: high" \
  -m "Scope-risk: moderate" \
  -m "Tested: Warp, attachment, and terminal capture suites"
```

### Task 7: Replace terminal jumping, foreground probes, and text sending

**Files:**
- Create/adapt: `VibePetApp/Terminal/TerminalJumpService.swift`, `TerminalJumpTargetResolver.swift`, `ForegroundTerminalSessionProbe.swift`, `TerminalTextSender.swift`
- Remove after migration: old `VibePetApp/Bridge/TerminalJump*.swift`
- Test: upstream and VibePet terminal suites

- [ ] **Step 1: Port and merge terminal behavior tests**

Copy upstream `TerminalJumpServiceTests.swift` and `ForegroundTerminalSessionProbeTests.swift`; retain Ghostty/Terminal/iTerm exact-tab tests, cmux, VS Code family, timeout, cwd fallback, and double-click action tests.

- [ ] **Step 2: Run terminal service tests red**

```bash
swift test --filter 'TerminalJump|ForegroundTerminal|BubbleJump'
```

Expected: missing upstream protocol shapes and terminal families.

- [ ] **Step 3: Import terminal services**

Copy the four pinned App sources. Rename product identifiers, move implementations out of `Bridge/`, inject AppleScript/process/clock/text-send effects, and preserve the exact-identifier-before-heuristic order.

- [ ] **Step 4: Run tests green and commit**

```bash
swift test --filter 'TerminalJump|ForegroundTerminal|BubbleJump'
git add VibePetApp/Terminal VibePetApp/Bridge Tests/VibePetAppTests
git commit -m "Match upstream terminal navigation and foreground identity" \
  -m "Constraint: Precise IDs and TTYs win; heuristic mismatch fails open." \
  -m "Confidence: high" \
  -m "Scope-risk: broad" \
  -m "Tested: terminal jump, resolver, foreground, and bubble action suites"
```

### Task 8: Port notification sound and suppression services

**Files:**
- Create: `VibePetApp/NotificationSoundService.swift`
- Modify: `VibePetApp/AppModel.swift`, `VibePetApp/Pet/PetController.swift`
- Test: notification sound, suppression, and existing notification E2E tests

- [ ] **Step 1: Write isolated service tests**

Cover system sound enumeration, configured default, mute, preview, missing player, transition deduplication, exact foreground match, stale probe result, critical bypass, and playback failure isolation.

- [ ] **Step 2: Run notification tests red**

```bash
swift test --filter 'NotificationSound|ForegroundTerminal|NotificationBubble|NotificationFlow'
```

Expected: sound service and exact suppression routing are absent.

- [ ] **Step 3: Import and route the service**

Copy upstream `NotificationSoundService.swift`; inject filesystem/player closures. Route accepted AppModel transitions once. Suppress only exact foreground completion/non-actionable status; approval, question, error, install, and health bypass suppression.

- [ ] **Step 4: Run tests green and commit**

```bash
swift test --filter 'NotificationSound|ForegroundTerminal|NotificationBubble|NotificationFlow'
git add VibePetApp Tests/VibePetAppTests Tests/E2E
git commit -m "Route local notification sounds without weakening attention" \
  -m "Constraint: Critical and actionable events always bypass foreground suppression." \
  -m "Confidence: high" \
  -m "Scope-risk: moderate" \
  -m "Tested: sound, suppression, bubble, and notification E2E suites"
```

### Task 9: Port launch, updater, Watch, and user-triggered Accessibility services

**Files:**
- Create: `VibePetApp/LaunchAtLoginService.swift`, `UpdateChecker.swift`, `KeystrokeInjector.swift`
- Create: `VibePetCore/Watch/WatchHTTPEndpoint.swift`, `WatchNotificationRelay.swift`
- Modify: `VibePetApp/AppModel.swift`, `VibePetApp/main.swift`
- Test: upstream Watch and keystroke suites plus new updater/launch lifecycle tests

- [ ] **Step 1: Port upstream tests and add effect-isolation cases**

Copy `WatchNotificationRelayTests.swift` and `KeystrokeInjectorTests.swift`. Add tests that update/network, Watch relay, launch-at-login, and accessibility failures do not mutate session state or block bridge replies.

- [ ] **Step 2: Run system-service tests red**

```bash
swift test --filter 'Watch|Keystroke|UpdateChecker|LaunchAtLogin'
```

Expected: service types and lifecycle wiring are absent.

- [ ] **Step 3: Import services with explicit activation boundaries**

Copy `WatchHTTPEndpoint.swift`, `WatchNotificationRelay.swift`, `LaunchAtLoginService.swift`, `UpdateChecker.swift`, and `KeystrokeInjector.swift`. Rename product/bundle/feed identifiers. Keep Sparkle App-only, Watch payloads bounded and documented, and keystroke injection callable only from explicit user actions.

- [ ] **Step 4: Run tests green and commit**

```bash
swift test --filter 'Watch|Keystroke|UpdateChecker|LaunchAtLogin'
git add VibePetCore/Watch VibePetApp Tests
git commit -m "Add optional companion and system services" \
  -m "Constraint: Network and Accessibility effects are explicit and isolated from session state." \
  -m "Confidence: medium" \
  -m "Scope-risk: broad" \
  -m "Tested: Watch relay, keystroke, updater, launch, and failure-isolation suites"
```

### Task 10: Run Gate B after M3 and M4

**Files:**
- Update: `openspec/changes/add-session-continuity-and-services/tasks.md`
- Update: `docs/upstream/open-vibe-island.md`

- [ ] **Step 1: Run the complete paired gate**

```bash
swift build
swift test
openspec validate add-session-continuity-and-services --strict
git diff --check
rg -n 'URLSession|NWListener|CGEventPost|AXIsProcessTrusted|SPUStandardUpdaterController' VibePetCore VibePetApp
```

Expected: build and all tests pass; OpenSpec and diff are clean; every high-privilege call is confined to the documented service files.

- [ ] **Step 2: Run data-safety audits**

Inspect encoded registry fixtures and prove no approval/question payload or continuation appears. Confirm real agent config paths were not modified during tests.

- [ ] **Step 3: Record Gate B and commit**

```bash
git add openspec/changes/add-session-continuity-and-services/tasks.md docs/upstream/open-vibe-island.md
git commit -m "Close the continuity and application-service gate" \
  -m "Constraint: Gate B covers M3 and M4 together as requested." \
  -m "Confidence: high" \
  -m "Scope-risk: broad" \
  -m "Tested: swift build; full swift test; strict OpenSpec; data and privilege audits"
```

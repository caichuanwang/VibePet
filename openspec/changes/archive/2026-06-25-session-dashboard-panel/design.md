## Context

Agent activity currently surfaces only as transient bubbles anchored to the pet (`PetController` + `PetWindowSurface` driving a borderless bubble window). `SessionState` already aggregates all hook-connected Claude Code / Codex sessions with derived counts (`runningCount`, `attentionCount`, `visibleSessions`) and per-session phase/jump-target metadata; `BridgeServerHost` owns the authoritative snapshot and publishes on every change via `onSessionStateChange`. The menu bar already switches the active pet through `ConfigStore`, and the pet window already disambiguates the opaque body from transparent passthrough.

This change adds a dashboard panel as a second presentation surface for that existing state, plus a right-click pet-cycle gesture. open-vibe-island's `IslandPanelView` / `AppModel` are the architecture reference for the panel + session list; we reimplement with VibePet's own models and naming.

Constraints: `VibePetCore` must stay free of AppKit/SwiftUI; fail-open and local-first red lines hold; no hooks/installer/bridge/adapter changes here.

## Goals / Non-Goals

**Goals:**
- A borderless dark frosted-glass dashboard panel that opens on a pet left-click and dismisses on outside-click, with a fixed position once open.
- A home session list driven by `SessionState` (summary header + per-session rows with status dot, tags, elapsed time, Enter button) and per-session tabs that reuse the existing cards as content.
- Right-click cycles the active pet with a fade + name tooltip.
- Clean three-way pointer routing on the pet window (click / drag / right-click).

**Non-Goals:**
- Process discovery or `ToolKind` expansion; only hook-connected sessions appear.
- Changing hook coverage, the installer, bridge serialization, adapters, or the decision-timeout behavior (separate 0.3 items).
- Replacing the existing anchored bubble path wholesale — the dashboard is an added surface; the anchored path may remain for the no-panel case.

## Decisions

**1. Panel as a borderless non-activating `NSPanel`, not `NSPopover`.**
`NSPopover` is visually rigid and tied to a positioning view. A custom borderless non-activating panel (same family as the pet window) gives us the dark frosted-glass look (`NSVisualEffectView` behind SwiftUI), all-Spaces stationary collection behavior, and full control of anchored placement. Outside-click dismissal is handled with a global mouse monitor (mirroring `PetWindowController`'s existing monitor pattern) that closes the panel when a click lands outside its frame. Alternative considered: `NSPopover` — rejected for styling/positioning limits.

**2. Fixed anchor at open time.** Placement is computed once from the pet frame + screen `visibleFrame` (reuse/extend the `BubbleAnchor` geometry helper) and not updated when the pet moves. This avoids a moving panel and keeps the implementation a one-shot placement. The panel does not follow `petFrame` changes.

**3. Dashboard owns its own view state; data flows one-way from `SessionState`.** A `@MainActor` SwiftUI `SessionDashboardView` renders from a snapshot of `SessionState` plus a `selectedTab` (home | sessionID). `BridgeServerHost.onSessionStateChange` already fires on every state change; `AppDelegate` forwards the latest snapshot to the open dashboard so tabs update live. No new source of truth — the dashboard is a pure projection. Elapsed time is derived from `AgentSession.firstSeenAt`; the status dot maps from `phase` (running → green, `requiresAttention` → amber, completed+`isError` → red).

**4. Tab content reuses existing cards.** `ApprovalCard` / `QuestionCard` / `SpeechBubble` are extracted to render inside the tab content area (uniform padding) instead of only inside the anchored bubble window. The decision round-trip (`requestDecision` continuation pairing in `PetController`) is unchanged — the tab's card invokes the same `onDecision` / `onAnswer` callbacks. This keeps fail-open intact: whether a card is shown anchored or in a tab, resolving/dismissing it routes through the same continuation.

**5. Pointer routing stays in the AppKit window layer.** `PetWindowController` / `PetDragController` already own `mouseDown`/`mouseDragged`/`mouseUp` on the opaque body. We add: a small movement threshold so a left press-release below it is a click (emit `onOpenDashboard`) rather than a drag; `rightMouseDown`/`rightMouseUp` to emit `onCyclePet`. These are exposed as injected closures so `AppDelegate` wires them to dashboard-open and pet-cycle, keeping window code free of app policy. Drag/snap logic (`ScreenSnap`) is untouched.

**6. Pet cycle lives in `AppDelegate`, reusing the existing switch path.** `AppDelegate` already lists assets (`assetStore.list()`) and persists the active pet (`switchPet(to:)`). The cycle action computes the next slug in the stable list order (wrap-around) and calls the same persist + `refreshPet()` path, then triggers the fade + name tooltip on the pet surface. Reduce-motion swaps immediately but still shows the tooltip.

## Risks / Trade-offs

- **Two presentation surfaces (anchored bubble + dashboard tab) for the same content** → Risk of double-presenting or split state. Mitigation: keep `PetController` the single owner of the decision queue/continuations; the tab card and anchored card are alternate renderers of the same pending item, never two independent instances. Decide at most one visible card path per pending decision.
- **Outside-click dismissal via global monitor can misfire across Spaces / multi-monitor** → Mitigation: reuse the proven monitor pattern from `PetWindowController`; only dismiss when the click is outside the panel frame, and tear the monitor down on close.
- **Fixed anchor can leave the panel far from a pet the user then drags away** → Accepted: panel is a transient view dismissed on outside-click; not following the pet is the intended behavior and avoids a moving target.
- **Live tab updates while a card awaits a decision** → Mitigation: a state refresh updates surrounding metadata but must not recreate the in-flight card or reset its continuation; the tab observes the pending decision identity and only rebuilds the card when the pending item changes.
- **`NSVisualEffectView` + transparent all-Spaces panel interaction with the stationary pet overlays** → Mitigation: reuse the same collection behavior already specified for pet-adjacent overlays.

## Migration Plan

Additive UI change; no persisted-schema or protocol migration. The anchored bubble path remains as a fallback (e.g., pet hidden / panel closed), so behavior degrades gracefully if the dashboard is not open. Rollback is removing the panel wiring in `AppDelegate` and the pointer-action closures; `SessionState` and the model layer are untouched.

## Open Questions

- Whether, once the dashboard exists, the anchored decision bubble should be suppressed while the panel is open (single surface) or both remain — leaning toward suppressing the anchored card when its session's tab is visible, to avoid duplication. Final call during apply.
- Exact frosted-glass material/token values and tab-strip styling — to be pinned against the reference image during implementation (UI polish, not a spec contract).

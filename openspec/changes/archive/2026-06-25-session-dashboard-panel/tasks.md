## 1. Pointer routing on the pet window (desktop-pet-window)

- [x] 1.1 Add a drag-threshold so a left press-release with movement below the threshold is a click, not a drag, in `PetDragController` (track press origin + accumulated movement).
- [x] 1.2 Add injected `onOpenDashboard` and `onCyclePet` closures to `PetWindowController` / `PetDragController`; emit `onOpenDashboard` on a left click, keep drag/snap on a left drag.
- [x] 1.3 Handle `rightMouseDown` / `rightMouseUp` on the opaque body to emit `onCyclePet` without moving the pet; ensure transparent-pixel passthrough is unaffected.
- [x] 1.4 Unit-test the click-vs-drag threshold decision as UI-agnostic value logic where feasible (extend `ScreenSnap`/a small helper), keeping AppKit out of the tested unit.

## 2. Pet quick-switch (pet-quick-switch)

- [x] 2.1 In `AppDelegate`, add a `cyclePet()` action computing the next slug in the stable `assetStore.list()` order with wrap-around; no-op for <2 pets; persist via the existing switch path and `refreshPet()`.
- [x] 2.2 Add a fade transition between old/new sprite on the pet surface; immediate swap under reduce-motion.
- [x] 2.3 Add a transient name tooltip above the pet on switch (auto-dismiss), shown in both motion and reduce-motion modes.
- [x] 2.4 Wire `PetWindowController.onCyclePet` to `AppDelegate.cyclePet()`.

## 3. Dashboard panel window (session-dashboard)

- [x] 3.1 Add a `SessionDashboardWindowController` hosting a borderless non-activating panel with an `NSVisualEffectView` dark frosted-glass background and the stationary all-Spaces collection behavior used by pet overlays.
- [x] 3.2 Compute a fixed open-time anchor from the pet frame + screen `visibleFrame` (reuse/extend `BubbleAnchor`); do not re-anchor when the pet moves.
- [x] 3.3 Add outside-click dismissal via a global mouse monitor (mirroring `PetWindowController`), closing the panel on clicks outside its frame and tearing the monitor down on close.
- [x] 3.4 Wire `PetWindowController.onOpenDashboard` → `AppDelegate` opens/toggles the dashboard; forward the latest `SessionState` snapshot from `BridgeServerHost.onSessionStateChange` to the open dashboard.

## 4. Dashboard home + tabs UI (session-dashboard)

- [x] 4.1 Build `SessionDashboardView` with `selectedTab` state (home | sessionID), rendering from a `SessionState` snapshot + active pet info.
- [x] 4.2 Home view: summary header (total / running / attention) + one row per `visibleSessions` (status dot, project name, tool tag, terminal-app tag, elapsed time from `firstSeenAt`, Enter button) in `SessionState` order.
- [x] 4.3 Status-dot mapping helper (running→green, requiresAttention→amber, completed+isError→red) and elapsed-time formatting.
- [x] 4.4 Tab strip (rounded pills, active highlighted) + top bar (tool identity, brand status dot, global actions) + Back-to-home control.
- [x] 4.5 Tab content area: render the session's current `ApprovalCard` / `QuestionCard` / `SpeechBubble` with uniform padding; live-update on snapshot changes without recreating an in-flight card.
- [x] 4.6 Empty state: pet name + status dot + "no running sessions" message (no enlarged illustration).

## 5. Wire tab cards to the decision round-trip (pet-controller)

- [x] 5.1 Extract the existing cards so they render both anchored and inside a tab, invoking the same `onDecision` / `onAnswer` callbacks owned by `PetController` (single decision queue/continuation, fail-open preserved).
- [x] 5.2 Ensure a pending decision is presented through at most one visible path (suppress the anchored card when its session tab is shown) so a decision is never double-presented.
- [x] 5.3 Add a left-click-open action path through `PetController`/surface consistent with the spec (left click opens the dashboard).

## 6. Theme + verification

- [x] 6.1 Extend `BubbleTheme` with the dashboard's dark frosted-glass tokens (panel background, card layer, brand status colors, pill/tab styling) and apply consistently.
- [x] 6.2 Add `VibePetAppTests` for the dashboard home projection (counts, ordering, status-dot mapping, empty state) and pet-cycle ordering/wrap-around; keep tests off the real system via injected closures.
- [x] 6.3 Run `swift build` and `swift test`; confirm no regression in pet drag/snap, passthrough, or the decision round-trip.

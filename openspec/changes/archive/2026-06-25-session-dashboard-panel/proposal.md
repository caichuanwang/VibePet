## Why

Today VibePet surfaces agent activity only as transient bubbles anchored to the pet: there is no way to see all live Claude Code / Codex sessions at once, and a notification/approval is lost once dismissed. Users running several coding sessions cannot tell what is running, what needs attention, or jump between them. VibePet 0.3 introduces a lightweight session dashboard with per-session tabs, and makes the pet itself the entry point — left-click to open the panel, right-click to cycle the active pet.

## What Changes

- Add a **session dashboard panel**: a borderless, dark frosted-glass popover-style window anchored near the pet that opens on a left **click** (distinct from a drag) and dismisses when the user clicks outside. Its position is fixed once opened and does not follow the pet.
- The panel has a **home view** (aggregate session list) and **per-session tab views**:
  - Home: a header summary (`N total · M running · K need attention`) and one row per visible session = status dot (green running / amber needs-attention / red error) + project name + tool tag (`claude` / `codex`) + terminal-app tag + elapsed time + an **Enter** button that switches to that session's tab.
  - Tab: a top bar (tool + brand-colored status dot + global actions), a rounded-pill tab strip with the active tab highlighted, a uniformly padded content area, and a **Back to home** button.
  - Empty state (no visible sessions): the panel still shows the active pet's name + status dot + "no running sessions", without an enlarged illustration.
- **Auto-surface tabs**: when a hook event arrives for a session, its tab content updates (and becomes presentable) — this is an upgrade of the current desktop-bubble mechanism, reusing the existing `ApprovalCard` / `QuestionCard` / `SpeechBubble` rendering inside the tab content area rather than as standalone anchored windows.
- **Right-click to cycle pet**: right-clicking the pet silently switches to the next imported pet (no menu), with a fade transition and a brief name tooltip above the pet.
- **Three-way mouse interaction** on the pet window: left click (no drag) opens the dashboard, left drag moves the pet (unchanged), right click cycles the pet.

Data is driven solely by the existing `SessionState` (hook-connected Claude Code / Codex sessions). No process discovery and no `ToolKind` expansion. `VibePetCore` stays UI-independent; all panel/window/animation code lives in `VibePetApp`. Fail-open and local-first red lines are preserved.

## Capabilities

### New Capabilities
- `session-dashboard`: the dashboard panel window, its home session list, per-session tab navigation, status indicators, elapsed-time display, empty state, and reuse of existing cards as tab content.
- `pet-quick-switch`: right-click cycling through imported pets with a fade transition and a transient name tooltip.

### Modified Capabilities
- `desktop-pet-window`: the pet window SHALL distinguish three mouse interactions — left click (no drag) opens the dashboard, left drag moves/snaps the pet (existing behavior), and right click cycles the active pet — without regressing transparent-pixel passthrough or drag-snap.
- `pet-controller`: actionable and notification content SHALL be routable to the dashboard's per-session tabs as the presentation surface, and a left click on the pet SHALL open the dashboard panel; the controller continues to own state derivation from `SessionState`.

## Impact

- New UI (VibePetApp): a `SessionDashboard` window controller + SwiftUI views (home list, tab strip, tab content), a fixed-anchor placement helper, outside-click dismissal, pet status-dot overlay, and pet-switch fade/tooltip animation.
- Modified (VibePetApp): `PetWindowController` / `PetDragController` mouse handling to split click vs drag vs right-click; `PetController` / `PetWindowSurface` to drive dashboard tab content and a left-click-open action; `AppDelegate` wiring (pet cycle action, dashboard lifecycle).
- Reused unchanged at the model layer: `SessionState`, `AgentSession`, `BridgeServerHost` session snapshot. `VibePetCore` stays free of AppKit/SwiftUI; any system side effects remain injected closures.
- No changes to hooks, installer, bridge serialization, or adapters in this change.

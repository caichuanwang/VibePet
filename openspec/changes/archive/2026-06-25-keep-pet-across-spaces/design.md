## Context

`PetWindow` and `BubbleWindow` were borderless transparent AppKit windows with `.canJoinAllSpaces` and `.fullScreenAuxiliary`. That is necessary but not sufficient for the product expectation: the pet should feel fixed to the user's screen as they move between macOS desktops and full-screen Spaces.

The first implementation strengthened collection behavior with `.stationary` and `.ignoresCycle`, matching the all-Spaces surface shape used by `open-vibe-island`, but manual testing still left the pet behind on the old desktop. The useful reference is Codex App's avatar overlay: its Electron window is `type: "panel"`, `focusable: false`, visible on all workspaces including full-screen Spaces, and always on top at the floating level. Electron maps that macOS `panel` window type to an AppKit panel rather than a regular key-capable document window.

## Goals / Non-Goals

**Goals:**

- Keep the pet visible at the same screen-coordinate position when switching between macOS desktops.
- Keep pet-adjacent overlay windows aligned with that behavior: notification bubbles, approval/question bubbles, and pending-count badges.
- Preserve existing transparency, mouse passthrough, drag, snap, and `visibleFrame` clamp behavior.
- Make the AppKit window configuration testable where possible, and document manual Spaces verification where automation is not reliable.

**Non-Goals:**

- Do not add user-facing preferences for Space behavior.
- Do not implement separate per-Space pet instances.
- Do not implement multi-display placement or per-display position memory.
- Do not change bridge, hook, installer, pet asset, or persistence formats.

## Decisions

### D1. Host the pet as a nonactivating stationary all-Spaces panel

`PetWindow` should be an `NSPanel` using `.borderless` and `.nonactivatingPanel`, with `isFloatingPanel = true`, `hidesOnDeactivate = false`, `canBecomeKey = false`, and `canBecomeMain = false`. It should keep `.canJoinAllSpaces` and `.fullScreenAuxiliary`, and also include `.stationary` and `.ignoresCycle`.

Rationale:

- Codex App's working overlay follows this shape: panel-style, non-focusable, all-workspaces, full-screen-visible, floating.
- A regular key-capable `NSWindow` can still behave like it belongs to the Space where it was created, even with stronger collection behavior.
- `.canJoinAllSpaces` expresses the core "show on every desktop" behavior.
- `.fullScreenAuxiliary` allows the window to accompany full-screen Spaces.
- `.stationary` expresses that the overlay should stay pinned during desktop/Mission Control/Show Desktop transitions rather than visually sliding away with a Space.
- `.ignoresCycle` keeps the companion overlay out of normal window cycling, matching its non-document nature.

Rejected alternative: only add `.stationary` and `.ignoresCycle` to the existing regular `NSWindow`. Manual testing showed this was insufficient: the pet still stayed behind on the old desktop.

Rejected alternative: observe Space changes and call `orderFront`/`setFrame` after each switch. That is more fragile, can flicker, and creates more edge cases around full-screen Spaces and Mission Control.

### D2. Apply the same overlay contract to bubbles and badges

`BubbleWindow` should use the same collection behavior as `PetWindow` because bubbles and badges are anchored to the pet. If the pet appears on the active Space but an approval card or badge remains on the old Space, the user still experiences the flow as broken.

The bubble remains allowed to become key only when interactive, as today. This change should not alter approval/question keyboard behavior.

### D3. Keep the floating window level unless manual verification proves it insufficient

The implementation should keep `level = .floating` for both pet and bubble windows. If manual verification shows that a floating nonactivating panel is still hidden during specific Spaces or full-screen cases, then evaluate raising only the pet overlay surfaces to `.statusBar`.

Rationale: Codex App uses floating-level overlay windows. `.statusBar` is stronger and can solve stubborn overlay visibility cases, but it has a higher risk of appearing above system UI or feeling too intrusive.

### D4. Verification is split between unit-testable configuration and manual macOS behavior

Unit tests can assert the intended panel/window contract by creating the window classes and inspecting `NSPanel` type, style mask, focus behavior, level, and `collectionBehavior`. They cannot reliably automate Mission Control, Show Desktop, and full-screen Space transitions in SwiftPM tests.

Manual verification should cover:

- two normal desktops;
- at least one full-screen app Space;
- Mission Control;
- Show Desktop / click wallpaper to reveal desktop where available;
- pet window plus at least one bubble/badge state.

## Risks / Trade-offs

- AppKit Space behavior differs across macOS versions -> mitigate by using the standard collection behavior flags and keeping a manual verification checklist.
- `.nonactivatingPanel` removes pet-window key behavior -> acceptable because the pet body uses mouse interaction and does not need keyboard focus; approval/question bubbles keep their existing interactive key-window behavior.
- `.stationary` may change transition animation feel -> acceptable because the desired behavior is screen-pinned, not Space-pinned.
- `.floating` may still be insufficient above some full-screen apps -> mitigate by documenting `.statusBar` as a follow-up escalation only if verification fails.
- Interactive bubbles becoming key could affect ordering in full-screen Spaces -> mitigate by keeping existing `canBecomeKey` behavior unchanged and testing approval/question flows manually.

## Migration Plan

No data migration is needed. The change is runtime-only window configuration.

Rollback is straightforward: return `PetWindow` to a regular borderless `NSWindow` and remove the new collection behavior flags if they cause unacceptable macOS behavior.

## Open Questions

- Does a floating nonactivating panel plus stationary all-Spaces behavior satisfy full-screen Space behavior on the target macOS versions, or is `.statusBar` required?
- Should the final product support independent pet positions per display later? This change intentionally does not answer that.

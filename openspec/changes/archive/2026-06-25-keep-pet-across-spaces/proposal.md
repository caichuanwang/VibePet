## Why

The pet is meant to feel like a desktop companion, but the current window contract can still leave it behind when the user switches macOS desktops or enters full-screen Spaces. This breaks the core expectation that the pet stays with the user rather than belonging to one old Space.

## What Changes

- Strengthen the desktop pet window behavior so the pet remains visible on the active Space when the user switches desktops, uses full-screen Spaces, Mission Control, or Show Desktop.
- Apply the same cross-Space behavior to pet-adjacent overlay windows: notification bubbles, approval/question bubbles, and the pending-count badge.
- Keep existing positioning semantics: the pet stays at the same screen-coordinate position, remains clamped to `NSScreen.main.visibleFrame`, and does not introduce multi-display placement.
- Add verification coverage for the window configuration that can be asserted in tests, plus a manual verification checklist for macOS Spaces behavior.

## Capabilities

### New Capabilities

### Modified Capabilities

- `desktop-pet-window`: Pet and pet-adjacent overlay windows must behave as stationary all-Spaces overlays instead of being tied to the desktop where they were created.

## Impact

- Affected code: `VibePetApp/Window/PetWindow.swift`, `VibePetApp/Pet/PetWindowSurface.swift`, and any tests that assert AppKit window configuration.
- Affected behavior: desktop switching, full-screen Space visibility, Mission Control/Show Desktop behavior, and bubble/badge visibility while the pet is visible.
- No changes to `VibePetCore`, bridge protocol, hook behavior, installer behavior, pet assets, or persisted configuration format.
- No new dependencies.

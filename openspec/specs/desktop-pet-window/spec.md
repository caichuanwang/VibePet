# desktop-pet-window Specification

## Purpose
TBD - created by archiving change implement-m2-desktop-pet-window. Update Purpose after archive.
## Requirements
### Requirement: Transparent floating pet window

`VibePetApp` SHALL host the pet in a borderless `NSWindow` configured with `isOpaque == false`, `backgroundColor == .clear`, `level == .floating`, and `collectionBehavior` containing both `.canJoinAllSpaces` and `.fullScreenAuxiliary` (technical design §5.1). The window content SHALL be SwiftUI. Mouse events over transparent regions SHALL pass through to the application beneath, while only the pet body hit area responds (region-controlled `ignoresMouseEvents`). The default sprite frame SHALL be 120×120pt.

#### Scenario: Window is transparent, borderless, and floats across spaces

- **WHEN** the pet window is created
- **THEN** it is borderless, `isOpaque` is false, `backgroundColor` is `.clear`, `level` is `.floating`, and `collectionBehavior` includes `.canJoinAllSpaces` and `.fullScreenAuxiliary`

#### Scenario: Transparent regions pass clicks through

- **WHEN** the user clicks a transparent area of the window outside the pet body
- **THEN** the click is delivered to whatever is beneath the window and the pet does not consume it

#### Scenario: Pet body hit area responds

- **WHEN** the user clicks on the opaque pet body
- **THEN** the window receives the event (the pet is interactive there)

### Requirement: visibleFrame-based default placement

The pet position SHALL be computed relative to `NSScreen.main.visibleFrame` (excluding menu bar and Dock) so that "sitting on the bottom" means resting above the Dock. On first launch the pet SHALL be placed inset 24pt from the right edge of the main screen `visibleFrame` and flush with the bottom edge (technical design §5.1.1).

#### Scenario: First launch default position

- **WHEN** the pet is shown for the first time with no persisted position
- **THEN** its frame is inset 24pt from the right edge of `NSScreen.main.visibleFrame` and aligned to the bottom edge

### Requirement: Free drag with soft edge snapping

The pet SHALL be draggable to any location on screen. On `mouseUp`, the distance from the pet's bounding box to each of the four `visibleFrame` edges SHALL be measured; if the nearest edge distance is less than 40pt the pet SHALL animate-snap to that edge (inset 8pt) while preserving its coordinate along that edge (edge sliding), naturally settling into a corner when near two edges (technical design §5.1.1). This snapping geometry SHALL be implemented as UI-agnostic, unit-testable logic (`ScreenSnap`) that does not require AppKit/SwiftUI types.

#### Scenario: Release near an edge snaps to it

- **WHEN** the pet is released with its nearest edge distance below 40pt
- **THEN** it animates to that edge inset 8pt and keeps its position along the edge unchanged

#### Scenario: Release away from all edges does not snap

- **WHEN** the pet is released with all edge distances at or above 40pt
- **THEN** it stays at the released location without snapping

#### Scenario: Snap math is testable without UI

- **WHEN** the snap/clamp computation is exercised in a unit test with a given frame and screen rect
- **THEN** it returns the expected snapped position using only value types (no AppKit/SwiftUI dependency)

### Requirement: Position clamped to main screen and persisted

The pet position SHALL always be clamped within `NSScreen.main.visibleFrame` (multi-screen placement is deferred). The position SHALL be persisted to `config.json` via `ConfigStore`. On startup, if `visibleFrame` has changed (resolution/scale change) the persisted position SHALL be clamped back into the available area before display.

#### Scenario: Position is clamped into visibleFrame

- **WHEN** a computed or persisted position would fall partly outside `NSScreen.main.visibleFrame`
- **THEN** it is clamped so the pet's bounding box stays fully within `visibleFrame`

#### Scenario: Position persists across launches

- **WHEN** the pet is moved and the app later restarts
- **THEN** the pet reappears at the persisted position (clamped if `visibleFrame` changed)


## MODIFIED Requirements

### Requirement: Free drag with soft edge snapping

The pet SHALL be draggable to any location on screen. The pet window SHALL distinguish three pointer interactions on the pet body: a left press-and-release with pointer movement below a small drag threshold SHALL be treated as a **click** and SHALL emit an open-dashboard action; a left press with movement at or above the threshold SHALL be treated as a **drag** and SHALL move the pet; a right-click SHALL emit a cycle-pet action (see `pet-quick-switch`) and SHALL NOT move the pet. On `mouseUp` after a drag, the distance from the pet's bounding box to each of the four `visibleFrame` edges SHALL be measured; if the nearest edge distance is less than 40pt the pet SHALL animate-snap to that edge (inset 8pt) while preserving its coordinate along that edge (edge sliding), naturally settling into a corner when near two edges (technical design §5.1.1). This snapping geometry SHALL be implemented as UI-agnostic, unit-testable logic (`ScreenSnap`) that does not require AppKit/SwiftUI types. The click-versus-drag disambiguation SHALL NOT regress transparent-pixel passthrough.

#### Scenario: Left click without drag opens the dashboard

- **WHEN** the user presses and releases the left button on the pet body with movement below the drag threshold
- **THEN** no drag/snap occurs and an open-dashboard action is emitted

#### Scenario: Left drag moves the pet

- **WHEN** the user presses the left button on the pet body and moves at or beyond the drag threshold before releasing
- **THEN** the pet moves with the pointer and is treated as a drag, not a click

#### Scenario: Right click cycles the pet without moving it

- **WHEN** the user right-clicks the pet body
- **THEN** a cycle-pet action is emitted and the pet position does not change

#### Scenario: Release near an edge snaps to it

- **WHEN** the pet is released after a drag with its nearest edge distance below 40pt
- **THEN** it animates to that edge inset 8pt and keeps its position along the edge unchanged

#### Scenario: Release away from all edges does not snap

- **WHEN** the pet is released after a drag with all edge distances at or above 40pt
- **THEN** it stays at the released location without snapping

#### Scenario: Snap math is testable without UI

- **WHEN** the snap/clamp computation is exercised in a unit test with a given frame and screen rect
- **THEN** it returns the expected snapped position using only value types (no AppKit/SwiftUI dependency)

## MODIFIED Requirements

### Requirement: Transparent floating pet window

`VibePetApp` SHALL host the pet in a borderless nonactivating `NSPanel` configured with `isOpaque == false`, `backgroundColor == .clear`, `level == .floating`, `isFloatingPanel == true`, `hidesOnDeactivate == false`, `canBecomeKey == false`, `canBecomeMain == false`, and `collectionBehavior` containing `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.stationary`, and `.ignoresCycle` (technical design §5.1). The window SHALL behave as a stationary all-Spaces overlay: switching macOS desktops, entering or leaving a full-screen Space, Mission Control, or Show Desktop MUST NOT leave the pet behind on the previous Space. The window content SHALL be SwiftUI. Mouse events over transparent regions SHALL pass through to the application beneath, while only the pet body hit area responds (region-controlled `ignoresMouseEvents`). The default sprite frame SHALL be 120×120pt.

Pet-adjacent overlay windows anchored to the pet, including notification bubbles, approval/question bubbles, and pending-count badges, SHALL use the same stationary all-Spaces collection behavior so they remain visible with the pet on the active Space.

#### Scenario: Window is transparent, borderless, and floats across spaces

- **WHEN** the pet window is created
- **THEN** it is a borderless nonactivating `NSPanel`, `isOpaque` is false, `backgroundColor` is `.clear`, `level` is `.floating`, `isFloatingPanel` is true, `hidesOnDeactivate` is false, it cannot become key or main, and `collectionBehavior` includes `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.stationary`, and `.ignoresCycle`

#### Scenario: Pet remains visible after switching desktops

- **WHEN** the pet is visible and the user switches from one macOS desktop Space to another
- **THEN** the pet remains visible on the newly active Space at the same screen-coordinate position

#### Scenario: Pet remains visible in a full-screen Space

- **WHEN** the pet is visible and the user switches to a full-screen app Space
- **THEN** the pet remains visible as an auxiliary overlay without being left on the previous Space

#### Scenario: Pet remains pinned during Mission Control or Show Desktop

- **WHEN** the user invokes Mission Control or Show Desktop while the pet is visible
- **THEN** the pet remains screen-pinned instead of sliding away with application windows

#### Scenario: Pet overlays follow the pet across Spaces

- **WHEN** a notification bubble, approval/question bubble, or pending-count badge is visible and the user switches Spaces
- **THEN** the overlay remains visible with the pet on the active Space and keeps its pet-relative placement

#### Scenario: Transparent regions pass clicks through

- **WHEN** the user clicks a transparent area of the window outside the pet body
- **THEN** the click is delivered to whatever is beneath the window and the pet does not consume it

#### Scenario: Pet body hit area responds

- **WHEN** the user clicks on the opaque pet body
- **THEN** the window receives the event (the pet is interactive there)

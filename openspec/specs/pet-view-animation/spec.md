# pet-view-animation Specification

## Purpose
TBD - created by archiving change implement-m2-desktop-pet-window. Update Purpose after archive.
## Requirements
### Requirement: Pet view renders the active PetAsset sprite

`VibePetApp` SHALL provide a SwiftUI `PetView` that loads and displays the active `PetAsset`'s primary sprite image (technical design §2.1 / §5.2). The view SHALL render the sprite's transparent (alpha) regions without an opaque background.

#### Scenario: Active sprite is displayed

- **WHEN** `PetView` is given a `PetAsset` with a valid `primaryImageURL`
- **THEN** it displays that sprite with its transparency preserved (no opaque box around the pet)

### Requirement: Idle standby animation

While in the idle state the pet SHALL play a continuous, AI-free standby animation: a squash/stretch "breathing" plus a slight periodic sway, driven by Core Animation on the single sprite (technical design §2.1 末 / §5.2).

#### Scenario: Idle plays breathing and sway

- **WHEN** the pet is in the idle state
- **THEN** `PetView` continuously applies a squash/stretch breathing and a slight sway to the sprite

### Requirement: Optional blink layer overlay

When the active `PetAsset` provides `layers` containing a blink layer, `PetView` SHALL overlay periodic blinking; when `layers` is empty it SHALL skip blinking and still render correctly (technical design §2.1 末).

#### Scenario: Blink overlay when layers provided

- **WHEN** the `PetAsset.layers` includes a blink layer
- **THEN** `PetView` periodically overlays the blink on top of the base sprite

#### Scenario: No layers skips blinking

- **WHEN** the `PetAsset.layers` is empty
- **THEN** `PetView` renders the base sprite with no blink and without error

### Requirement: Greeting animation

The pet SHALL play a distinct greeting animation when entering the greet state (e.g. on launch / first-of-day), visibly different from the idle standby motion (technical design §5.2).

#### Scenario: Greet animation on greet state

- **WHEN** the pet enters the greet state
- **THEN** `PetView` plays a greeting animation distinct from the idle breathing/sway

### Requirement: Reduce Motion fallback

When the system "Reduce Motion" accessibility setting is enabled, `PetView` SHALL replace bouncing/spring motion with cross-fade (fade in/out) transitions (technical design §5.3 通用).

#### Scenario: Reduce Motion uses fades

- **WHEN** Reduce Motion is enabled and the pet would animate
- **THEN** `PetView` uses fade-based transitions instead of bouncing/spring animations


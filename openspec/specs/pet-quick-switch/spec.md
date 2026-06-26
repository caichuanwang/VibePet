# pet-quick-switch Specification

## Purpose

Define right-click pet cycling, including persistence and lightweight visual feedback for the active pet switch.

## Requirements

### Requirement: Right-click cycles the active pet

`VibePetApp` SHALL, when the pet receives a right-click "cycle" action (see `desktop-pet-window`), switch the active pet to the next imported pet in a stable order without presenting a menu. The order SHALL be the same stable ordering used for the imported pet list, and cycling SHALL wrap from the last pet back to the first. The newly selected pet SHALL be persisted as the active pet via `ConfigStore`, consistent with switching the pet from the menu bar. When fewer than two pets are available, a right-click SHALL be a no-op other than any feedback.

#### Scenario: Right-click advances to the next pet

- **WHEN** the user right-clicks the pet and more than one pet is imported
- **THEN** the active pet changes to the next pet in order and the new selection is persisted

#### Scenario: Cycling wraps around

- **WHEN** the active pet is the last in order and the user right-clicks the pet
- **THEN** the active pet changes to the first pet in order

#### Scenario: Single pet is a no-op

- **WHEN** the user right-clicks the pet and only one (or zero) pet is available
- **THEN** the active pet does not change

### Requirement: Pet switch transition and name tooltip

When the active pet changes via right-click cycling, `VibePetApp` SHALL play a fade transition between the previous and new sprite and SHALL briefly show a tooltip with the new pet's name above the pet, which auto-dismisses. The transition and tooltip SHALL respect reduce-motion: when reduce-motion is enabled the sprite swap SHALL be immediate while the name tooltip SHALL still appear briefly.

#### Scenario: Fade and name tooltip on switch

- **WHEN** the active pet changes by right-click cycling
- **THEN** the sprite fades from the old pet to the new pet and a tooltip showing the new pet's name appears briefly above the pet and then auto-dismisses

#### Scenario: Reduce-motion uses an immediate swap

- **WHEN** reduce-motion is enabled and the active pet changes by right-click cycling
- **THEN** the sprite swaps immediately without a fade while the name tooltip still appears briefly


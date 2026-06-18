## ADDED Requirements

### Requirement: Single compact import-to-generate panel with a state machine

`VibePetApp` SHALL provide a single compact `PetImportPanel` that carries the whole "photo → pet" flow by transforming in place (no multi-step wizard pages). Its view model SHALL implement the state machine `idle → generating → result → placed`, with any failure transitioning to `error` (technical design §5.5). The state machine logic SHALL be unit-testable independently of SwiftUI.

#### Scenario: Happy-path state progression

- **WHEN** a photo is imported, cutout succeeds, and the user confirms placement
- **THEN** the panel transitions `idle → generating → result → placed` in order

#### Scenario: Failure transitions to error

- **WHEN** generation fails (e.g. throws `GenError`) from `generating`
- **THEN** the state machine transitions to `error` (not to `result`)

#### Scenario: State machine is testable without UI

- **WHEN** the view model's transitions are driven in a unit test
- **THEN** they can be asserted using only the view model state (no SwiftUI dependency)

### Requirement: Import auto-starts cutout

In `idle` the panel SHALL accept JPG/PNG/HEIC via drag-and-drop or file selection, and importing a file SHALL immediately transition to `generating` and start cutout — there SHALL be no separate "generate" button (technical design §5.5). Generation SHALL go through `GenerationService` from `VibePetCore`.

#### Scenario: Dropping a supported image starts generation

- **WHEN** the user drops or selects a JPG, PNG, or HEIC file in `idle`
- **THEN** the panel transitions to `generating` and invokes `GenerationService.generate(from:)` without requiring an extra button press

### Requirement: Generation progress is shown

In `generating` the panel SHALL display progress driven by the `PetGenerator.generate` `progress` callback (technical design §5.5).

#### Scenario: Progress reflects the callback

- **WHEN** the generator reports progress through its `progress` closure
- **THEN** the panel's displayed progress updates accordingly

### Requirement: Result preview with optional naming

In `result` the panel SHALL preview the transparent sprite over a checkerboard background and offer an optional name input (a placeholder name is prefilled and may be left blank to skip), with actions to swap the photo or place the pet (technical design §5.5).

#### Scenario: Result previews the transparent sprite

- **WHEN** cutout succeeds
- **THEN** the panel shows the sprite over a checkerboard, a prefilled-but-optional name field, and "swap photo" / "place on desktop" actions

### Requirement: Confirmation persists the asset and activates it

On confirmation (`result → placed`) the panel SHALL write the asset via `PetAssetStore` and set `config.activePetID`, then close so the pet lands at the default bottom-right desktop position and enters idle standby (technical design §5.5).

#### Scenario: Placing writes the asset and sets active pet

- **WHEN** the user confirms placement in `result`
- **THEN** the sprite is persisted via `PetAssetStore`, `config.activePetID` is set to the new asset, the panel closes, and the pet appears at the default position in idle

### Requirement: Errors are readable and leave no partial asset

In `error` (e.g. `GenError.noSubject`) the panel SHALL show a readable in-panel message with "swap photo" / "retry" actions and SHALL NOT produce any half-finished asset on disk (technical design §5.5 / §7).

#### Scenario: noSubject shows a recoverable error

- **WHEN** generation throws `GenError.noSubject`
- **THEN** the panel shows a readable message with swap/retry actions and no sprite or asset directory is left behind for the failed attempt

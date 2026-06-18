## ADDED Requirements

### Requirement: Pluggable generator protocol and asset model

`VibePetCore` SHALL define a `PetGenerator` protocol exposing a stable `identifier: String` and `func generate(from image: CGImage, progress: @escaping (Double) -> Void) async throws -> PetAsset`. It SHALL define `PetAsset` (`id`, `kind`, `primaryImageURL`, `layers`, `boundingInset`, `metadata`), `PetKind` (`sprite2D`, `stylized2D`, `model3D`), `PetLayer`, and `GenError` (including a `noSubject` case) per technical design §2. `PetAsset` SHALL be `Codable` and `Sendable`, and `PetGenerator` SHALL be `Sendable`.

#### Scenario: PetAsset round-trips through Codable

- **WHEN** a `PetAsset` is encoded to JSON and decoded back
- **THEN** the decoded value equals the original, including `id`, `kind`, `primaryImageURL`, `layers`, `boundingInset`, and `metadata`

#### Scenario: PetKind cases are stable

- **WHEN** each `PetKind` case (`sprite2D`, `stylized2D`, `model3D`) is encoded
- **THEN** it encodes to its documented raw value and decodes back to the same case

#### Scenario: noSubject is representable

- **WHEN** code throws or matches `GenError.noSubject`
- **THEN** the case is distinguishable from other error cases for UI mapping

### Requirement: Local Vision cutout generator

`VibePetCore` SHALL provide `LocalCutoutGenerator` conforming to `PetGenerator` with `identifier == "local-cutout"`. It SHALL run entirely on-device using `VNGenerateForegroundInstanceMaskRequest` (no network). When multiple foreground instances are returned it SHALL select the largest by mask area (`largestInstance`). It SHALL produce a masked image cropped to the subject extent (`croppedToInstancesExtent`) and write a PNG that preserves the alpha channel. When no significant subject is detected it SHALL throw `GenError.noSubject`. It SHALL invoke the `progress` callback during generation.

#### Scenario: Single-subject photo yields a transparent sprite

- **WHEN** `generate(from:progress:)` is called with a fixture image containing one clear subject
- **THEN** it returns a `PetAsset` of kind `sprite2D` whose `primaryImageURL` points to a non-empty PNG that contains an alpha channel

#### Scenario: No subject throws noSubject

- **WHEN** `generate(from:progress:)` is called with an image that has no detectable foreground subject
- **THEN** it throws `GenError.noSubject` and writes no partial sprite asset

#### Scenario: Largest instance is chosen for multiple subjects

- **WHEN** Vision returns more than one foreground instance for the input image
- **THEN** only the instance with the largest mask area is used to build the sprite

#### Scenario: Progress callback is invoked

- **WHEN** `generate(from:progress:)` runs to completion
- **THEN** the `progress` closure is called at least once with a value in the range 0.0…1.0

### Requirement: UI-agnostic subject framing via bounding inset

`PetAsset.boundingInset` SHALL describe the subject's placement within the sprite canvas (for downstream cropping/alignment per technical design §2) using a UI-agnostic, `Codable` value type — NOT the SwiftUI `EdgeInsets` type — so that `VibePetCore` stays free of AppKit/SwiftUI imports. `LocalCutoutGenerator` SHALL populate `boundingInset` consistently with the subject extent it cropped to.

#### Scenario: boundingInset round-trips without SwiftUI

- **WHEN** a `PetAsset` carrying a `boundingInset` is encoded and decoded
- **THEN** the inset values are preserved and the defining module imports neither AppKit nor SwiftUI

#### Scenario: boundingInset reflects the cropped subject

- **WHEN** `LocalCutoutGenerator` produces a sprite cropped to the subject extent
- **THEN** the returned `PetAsset.boundingInset` is consistent with that subject extent for alignment by callers

### Requirement: MVP sprite layer contract

For the MVP, `LocalCutoutGenerator` SHALL produce a `PetAsset` of kind `sprite2D` with an empty `layers` array; optional animation layers (e.g. eyes for blinking) are deferred. Downstream consumers SHALL treat an empty `layers` array as "no optional overlays" and skip layer-dependent animation rather than fail.

#### Scenario: MVP cutout yields no animation layers

- **WHEN** `LocalCutoutGenerator` generates a sprite from a single-subject photo
- **THEN** the resulting `PetAsset.kind` is `sprite2D` and `layers` is empty

### Requirement: Configuration-driven generator selection

`VibePetCore` SHALL provide a `GenerationService` that holds a registry of `PetGenerator` instances keyed by `identifier`, selects the active generator using `config.activeGeneratorID` from `app-configuration`, and exposes a single public entry point `generate(from:)` to callers. The MVP registry SHALL include `LocalCutoutGenerator`. Adding a new generator SHALL require only registering an implementation, with no change to callers. An unknown or missing `activeGeneratorID` SHALL resolve to a defined fallback or surface a clear, typed error rather than crashing.

#### Scenario: Active generator id routes to its implementation

- **WHEN** `config.activeGeneratorID` is `"local-cutout"` and `generate(from:)` is called
- **THEN** the call is dispatched to the registered `LocalCutoutGenerator`

#### Scenario: Unknown generator id is handled deterministically

- **WHEN** `config.activeGeneratorID` names a generator that is not registered
- **THEN** `GenerationService` either falls back to the documented default generator or throws a clear typed error, and never crashes

#### Scenario: New generator is added without changing callers

- **WHEN** an additional `PetGenerator` is registered and selected via configuration
- **THEN** existing callers of `generate(from:)` invoke it unchanged

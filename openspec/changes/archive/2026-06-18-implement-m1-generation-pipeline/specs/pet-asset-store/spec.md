## ADDED Requirements

### Requirement: Pet asset persistence layout

`VibePetCore` SHALL provide a `PetAssetStore` that persists a generated sprite to `~/Library/Application Support/VibePet/pets/<uuid>/sprite.png` alongside a `meta.json` describing the asset, per technical design §6. The PNG SHALL preserve the alpha channel produced by generation, and `meta.json` SHALL be sufficient to reconstruct the corresponding `PetAsset`.

#### Scenario: Writing a sprite creates the per-pet directory and files

- **WHEN** `PetAssetStore` writes a sprite for a new pet id
- **THEN** `pets/<uuid>/sprite.png` and `pets/<uuid>/meta.json` exist under the VibePet support directory

#### Scenario: Write then read round-trips the asset

- **WHEN** an asset is written and later read by the same id
- **THEN** the loaded `PetAsset` equals the stored one and its sprite file is readable with its alpha channel intact

### Requirement: Asset read, list, and delete by id

`PetAssetStore` SHALL support reading an asset by id, listing all stored pet ids, and deleting an asset by id. Deleting or writing one pet SHALL NOT affect the assets of any other pet.

#### Scenario: List reflects stored pets

- **WHEN** two distinct pets are written and the store is listed
- **THEN** both pet ids appear in the listing

#### Scenario: Delete removes only the targeted pet

- **WHEN** one pet is deleted by id while another pet exists
- **THEN** the deleted pet's directory is gone and the other pet's `sprite.png` and `meta.json` remain intact

#### Scenario: Reading a missing id fails clearly

- **WHEN** an asset is requested for an id that was never written
- **THEN** the store surfaces a clear typed error or nil result rather than crashing

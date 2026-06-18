## Purpose

Define the UI-independent application configuration model and its on-disk store.

## Requirements

### Requirement: AppConfig model

`VibePetCore` SHALL define an `AppConfig` `Codable` type holding at least: `activePetID`, enabled tools, decision timeout, active generator ID, and pet position (within the main screen `visibleFrame`).

#### Scenario: AppConfig round-trips through Codable

- **WHEN** an `AppConfig` is encoded to JSON and decoded back
- **THEN** all fields decode to their original values

### Requirement: ConfigStore read/write with defaults

`ConfigStore` SHALL read and write `config.json` under `~/Library/Application Support/VibePet/`, and SHALL return a well-defined default configuration when the file does not exist.

#### Scenario: Missing file yields default config

- **WHEN** `ConfigStore` reads with no `config.json` present
- **THEN** it returns the default `AppConfig` without throwing

#### Scenario: Write then read round-trips

- **WHEN** a config is written via `ConfigStore` and then read back
- **THEN** the read value equals the written value

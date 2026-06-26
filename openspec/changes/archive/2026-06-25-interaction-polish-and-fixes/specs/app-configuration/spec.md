## MODIFIED Requirements

### Requirement: AppConfig model

`VibePetCore` SHALL define an `AppConfig` `Codable` type holding at least: `activePetID`, enabled tools, active generator ID, pet position (within the main screen `visibleFrame`), and an onboarding-completed marker indicating whether first-launch onboarding has finished. The onboarding-completed marker SHALL default to "not completed" so that an existing `config.json` written before this field existed decodes successfully and is treated as not-yet-onboarded. `AppConfig` SHALL NOT carry a consumed decision-timeout: 0.3 removes the App-side decision timeout, so no code path reads a `decisionTimeoutSeconds` value to bound a decision. Decoding a legacy `config.json` that still contains a `decisionTimeoutSeconds` field SHALL succeed (the field is ignored, not required), so older configs remain loadable.

#### Scenario: AppConfig round-trips through Codable

- **WHEN** an `AppConfig` is encoded to JSON and decoded back
- **THEN** all fields decode to their original values, including the onboarding-completed marker

#### Scenario: Missing onboarding marker decodes as not completed

- **WHEN** a legacy `config.json` without the onboarding-completed field is decoded
- **THEN** decoding succeeds and the onboarding-completed marker is `false` (not yet onboarded)

#### Scenario: Legacy decision-timeout field is ignored on decode

- **WHEN** a legacy `config.json` containing a `decisionTimeoutSeconds` field is decoded
- **THEN** decoding succeeds and no decision is bounded by that value (the field has no runtime effect)

## 1. Configuration Model

- [x] 1.1 Add failing `VibePetCoreTests` coverage for `AppConfig` language default, Codable round-trip, and legacy JSON missing `language`.
- [x] 1.2 Add an `AppLanguage` enum in `VibePetCore` with stable persisted identifiers for Simplified Chinese and English.
- [x] 1.3 Add `language` to `AppConfig`, `CodingKeys`, custom decode, encode, default config, initializer, and `with(...)` mutation helper.
- [x] 1.4 Run the focused AppConfig/ConfigStore tests and confirm legacy `decisionTimeoutSeconds` decode behavior still passes.

## 2. Localization Infrastructure

- [x] 2.1 Add failing tests for the localization table: exactly two supported languages, every used key has both translations, and technical identifiers remain exact in localized guidance.
- [x] 2.2 Add a dependency-free `VibePetApp` localization surface, such as `AppLocalizer` plus typed keys grouped by screen or domain.
- [x] 2.3 Populate Simplified Chinese and English translations for all current app-owned UI strings.
- [x] 2.4 Add development/test validation that reports any missing Simplified Chinese or English translation.

## 3. Settings and Config Propagation

- [x] 3.1 Add settings tests or view-model coverage proving the language selector reflects `AppConfig.language`.
- [x] 3.2 Add a language picker to `SettingsView` with Simplified Chinese and English choices.
- [x] 3.3 Persist language changes through `ConfigStore` and ensure the current settings window updates its visible text after a change.
- [x] 3.4 Update app-level config ownership so menu/window surfaces can rebuild localized labels after language changes.

## 4. Localize UI Surfaces

- [x] 4.1 Replace inline app-owned visible strings in settings and hook install UI with localized lookups.
- [x] 4.2 Replace inline app-owned visible strings in onboarding with localized lookups.
- [x] 4.3 Replace inline app-owned visible strings in menu bar entries and window titles with localized lookups.
- [x] 4.4 Replace inline app-owned visible strings in approval cards, question cards, speech bubbles, dashboard, import panel, and error presentation with localized lookups.
- [x] 4.5 Verify tool names, command names, file paths, `/hooks`, raw external output, pet metadata, and bridge/hook protocol values remain unlocalized exact values.

## 5. Verification

- [x] 5.1 Run `swift test` and fix any regressions.
- [x] 5.2 Manually launch the app in the default Simplified Chinese state and confirm visible UI text is Simplified Chinese.
- [x] 5.3 Switch the language to English in settings and confirm menu, settings, onboarding-reachable surfaces, cards/bubbles, dashboard, and error guidance render English without restarting where practical.
- [x] 5.4 Re-open the app after selecting English and confirm the persisted language is applied on launch.
- [x] 5.5 Review `VibePetApp` for remaining hard-coded app-owned user-facing strings and either localize them or document why they are technical/user-supplied values.

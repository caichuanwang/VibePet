## Why

VibePet currently presents user-facing UI text as fixed Simplified Chinese strings, which blocks English users and makes future copy changes hard to manage consistently. Supporting a small, explicit language set now keeps the MVP local-first while making the full app surface usable in both Simplified Chinese and English.

## What Changes

- Add an application language preference with supported values for Simplified Chinese and English.
- Default the app language to Simplified Chinese for new and legacy configurations.
- Add a language selector in settings and persist changes through app configuration.
- Localize all visible app UI text through the configured language, including menu bar entries, settings, onboarding, hook install guidance, approval/question cards, session/dashboard text, bubbles, and error presentation.
- Keep hook CLI, bridge payload schemas, installer file formats, and external tool configuration semantics unchanged.

## Capabilities

### New Capabilities
- `localization`: Defines supported app languages and the requirement that visible UI text renders from the configured language.

### Modified Capabilities
- `app-configuration`: Add the persisted language preference with Simplified Chinese as the default for new and legacy configs.
- `settings-page`: Add the settings control that lets the user choose Simplified Chinese or English.

## Impact

- Affected app code: SwiftUI/AppKit UI under `VibePetApp/`, especially settings, onboarding, menu bar, cards, bubbles, dashboard, and error views.
- Affected core code: `VibePetCore/Persistence/AppConfig.swift` and config-store tests for the new language preference.
- Affected tests: AppConfig round-trip/default/legacy decoding tests plus focused UI/view-model tests for language selection and localized text lookup.
- No new network behavior, telemetry, external services, or runtime dependencies are introduced.

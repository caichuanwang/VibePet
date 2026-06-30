## Context

VibePet is a local-first macOS Swift package with UI in `VibePetApp` and UI-independent persistence in `VibePetCore`. Today the app exposes most visible copy as inline Simplified Chinese strings across SwiftUI views, AppKit menu items, onboarding, hook install guidance, bubbles, cards, dashboard text, and error presentation. `AppConfig` has no language field, so the app cannot persist or apply a user language choice.

This change introduces a small, explicit localization layer for two supported app languages: Simplified Chinese and English. The chosen language is user configuration, not a system-locale heuristic, and legacy configs must continue to decode with Simplified Chinese as the default.

## Goals / Non-Goals

**Goals:**
- Persist a language preference in `AppConfig` with `zh-Hans` as the default.
- Let users switch between Simplified Chinese and English from settings.
- Route all app-owned visible UI copy through the configured language.
- Keep Core free of SwiftUI/AppKit imports and keep hook/bridge external contracts unchanged.
- Make missing translations visible in tests or development rather than silently falling back in user-facing screens.

**Non-Goals:**
- No dynamic language downloads, network translation, telemetry, accounts, or pet gallery integration.
- No new app-supported languages beyond Simplified Chinese and English.
- No change to bridge schemas, hook payload values, installer config formats, or tool names such as `Claude Code` and `Codex`.
- No localization of user-authored content, file paths, pet package metadata supplied by users, or raw external command output.
- No reliance on the macOS preferred language to override the stored VibePet setting in this change.

## Decisions

1. Store language as a stable app enum in `VibePetCore`.

   Add an `AppLanguage` `Codable`, `Equatable`, `Sendable`, `CaseIterable` enum with stable raw values such as `zh-Hans` and `en`. `AppConfig.default` uses `.simplifiedChinese`, and custom decoding treats a missing language as `.simplifiedChinese`.

   Rationale: the language setting belongs to persisted configuration and must remain UI-independent. Stable raw values keep `config.json` readable and migration-friendly.

   Rejected alternative: storing `Locale` directly in `AppConfig`. `Locale` is broader than the supported product surface and makes it easier for unsupported identifiers to leak into persisted config.

2. Use an app-owned localized string lookup in `VibePetApp`.

   Introduce a small localizer surface, for example `AppLocalizer` plus typed keys, that maps each app-owned UI string to Simplified Chinese and English. SwiftUI views and AppKit menu builders receive or derive the current localizer from the current `AppConfig`, then render strings through that surface.

   Rationale: the project is a SwiftPM app without an existing `.strings` catalog pipeline, and the supported language set is intentionally tiny. A typed table keeps implementation local, testable, and dependency-free while avoiding scattered ad hoc dictionaries.

   Rejected alternative: using `NSLocalizedString` immediately. That can work later, but adopting it now requires resource/catalog setup across package targets and makes it easier to miss AppKit-constructed strings without strong test coverage.

3. Treat configured language as the source of truth.

   The app reads the persisted language at launch, uses it to build menu/window/UI copy, and updates relevant UI when settings changes the preference. New launches and missing/legacy config default to Simplified Chinese. The system locale does not override an existing or default VibePet config.

   Rationale: the user explicitly requested settings-based configuration and a Simplified Chinese default. This avoids surprising behavior on multilingual systems.

4. Localize app-owned visible text, not protocol or external identifiers.

   Localized text includes section titles, labels, buttons, hints, empty states, status descriptions, error messages, approval/question card copy, onboarding copy, dashboard labels, menu entries, window titles, and install guidance. Non-localized values include `Claude Code`, `Codex`, `/hooks`, `~/.codex/pets/`, pet display names, session IDs, command names, raw tool payload fields, and persisted enum raw values.

   Rationale: user-facing UI should follow the selected language, while technical identifiers must stay exact so users can follow external-tool instructions and configs remain stable.

## Risks / Trade-offs

- Missed inline strings → Add tests or static checks that fail on known user-facing string keys missing either language, and include a manual review task over `VibePetApp`.
- UI does not refresh after changing language → Centralize config observation/update flow so settings writes propagate to menu/window surfaces; at minimum, require current windows and the menu to rebuild labels after the setting changes.
- Over-localizing technical values → Keep explicit non-goals and specs for tool names, paths, hook commands, and protocol values.
- Typed table grows noisy → Keep keys grouped by screen/domain and prefer deletion/reuse of keys over speculative abstractions.

## Migration Plan

1. Add `AppLanguage` and `AppConfig.language`, with decoding defaulting missing values to Simplified Chinese.
2. Add focused config tests for default, round-trip, and legacy decode behavior.
3. Add the app localizer and translate existing app-owned UI text to Simplified Chinese and English.
4. Wire settings to show and persist the language selector.
5. Thread the current language/localizer through existing app surfaces, including the menu bar and windows.
6. Verify with `swift test` and targeted manual launch checks in both languages.

Rollback is straightforward because the field is additive. A rollback build that does not know `language` should continue to ignore the extra JSON key during decoding, as current config decoding already tolerates unknown fields.

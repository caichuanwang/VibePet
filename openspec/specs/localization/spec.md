## Purpose

Define VibePet's app-owned UI localization behavior and supported language set.

## Requirements

### Requirement: Supported app languages
VibePet SHALL support exactly two app UI languages for this change: Simplified Chinese and English. The app SHALL identify these languages with stable persisted identifiers and SHALL present language choices in the settings language selector using fixed self-names: Simplified Chinese as `简体中文` and English as `English`, regardless of the currently configured UI language.

#### Scenario: Supported language set is available
- **WHEN** the app builds the language selector
- **THEN** it offers Simplified Chinese and English, and no other language choices

#### Scenario: Language option names are stable
- **WHEN** the app builds the language selector in either supported UI language
- **THEN** the Simplified Chinese option is displayed as `简体中文` and the English option is displayed as `English`

#### Scenario: Language identifiers are stable
- **WHEN** the language preference is encoded for persistence
- **THEN** Simplified Chinese and English are represented by stable identifiers that do not depend on localized display names

### Requirement: Visible UI text follows configured language
VibePetApp SHALL render all app-owned visible UI text using the language configured in `app-configuration`. This includes menu bar entries, window titles, settings labels, onboarding text, hook install guidance, approval cards, question cards, session dashboard text, speech bubbles, empty states, status messages, and error presentation. Tool names, command names, file paths, `/hooks`, raw external output, user-authored content, pet metadata, and bridge or hook protocol values SHALL remain unchanged unless they are app-owned explanatory text around those values.

#### Scenario: Simplified Chinese UI renders from default language
- **WHEN** the configured language is Simplified Chinese
- **THEN** app-owned visible UI text is rendered in Simplified Chinese

#### Scenario: English UI renders from selected language
- **WHEN** the configured language is English
- **THEN** app-owned visible UI text is rendered in English

#### Scenario: Technical identifiers remain exact
- **WHEN** localized UI displays instructions that mention external identifiers such as `Claude Code`, `Codex`, `/hooks`, or `~/.codex/pets/`
- **THEN** those identifiers remain exact while surrounding explanatory text follows the configured language

### Requirement: Translation coverage is complete for supported languages
Every app-owned localization key used by VibePetApp SHALL have Simplified Chinese and English text before the app presents that key to the user. Missing translations SHALL be detectable by tests or development-time validation.

#### Scenario: Used key has both translations
- **WHEN** a VibePetApp view or menu requests a localized UI string
- **THEN** both Simplified Chinese and English values exist for that key

#### Scenario: Missing translation is detected
- **WHEN** a localization key lacks either the Simplified Chinese or English value
- **THEN** automated verification or development-time validation reports the missing translation before release

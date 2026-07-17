## ADDED Requirements

### Requirement: Claude transcript fallback is locally bounded

When inline Stop summary text is absent, `ClaudeCodeAdapter` SHALL inspect only a local regular transcript file no larger than 4 MiB and at most the final 2,000 NDJSON lines. It SHALL perform no network access and SHALL return the readable fallback on unreadable, oversized, non-regular, or malformed input.

#### Scenario: Oversized transcript uses the fallback

- **WHEN** `transcript_path` refers to a regular file larger than 4 MiB
- **THEN** the adapter does not load it and uses the normal completion fallback

#### Scenario: Malformed tail does not escape the scan bound

- **WHEN** the final transcript region contains malformed lines
- **THEN** the adapter skips malformed lines only within the bounded final 2,000-line window

### Requirement: Synthetic question choices never enter native output

The adapter MAY add a UI-only free-form choice to normalized question content, but encoded `updatedInput.questions` MUST exclude that synthetic option and preserve only the native question definition.

#### Scenario: Free-form UI option is stripped on encode

- **WHEN** a normalized question containing the synthetic free-form option is answered
- **THEN** the native response contains the answer but not the synthetic option in `updatedInput.questions`

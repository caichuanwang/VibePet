## MODIFIED Requirements

### Requirement: Status bubble rendering

`SpeechBubble` SHALL render `.status` content as a compact live/update bubble with a source header and a single icon plus `text`, auto-dismissing after 6–8s, and SHALL pause the auto-dismiss timer while the pointer hovers the bubble. A `.status` bubble SHALL NOT render a bottom button/action bar; it remains a lightweight notification rather than an interactive panel. When the bubble's source carries a jump target, double-clicking the non-control bubble body SHALL invoke the injected terminal jump action once and SHALL NOT alter the auto-dismiss or hover-pause behavior.

#### Scenario: Status shows compact content and auto-dismisses

- **WHEN** a `.status` envelope is presented
- **THEN** the bubble shows the source header plus a single icon+text line, shows no footer/action bar, and auto-dismisses after 6–8s

#### Scenario: Hover pauses dismissal

- **WHEN** the pointer hovers the status bubble before it dismisses
- **THEN** the auto-dismiss timer is paused until the pointer leaves

#### Scenario: Double-click status jumps back

- **WHEN** a `.status` bubble with a source jump target is double-clicked on its body
- **THEN** the injected terminal jump action is invoked once with that jump target

### Requirement: Adaptive width and source header

`SpeechBubble` SHALL use an adaptive width with a minimum of 240pt and a maximum of 380pt, scrolling internally rather than growing unbounded. It SHALL show a source header derived from `SourceInfo` as `tool · projectName · sessionShortId`, follow the system light/dark theme, and provide VoiceOver labels for text elements. Compact live/status bubbles SHALL keep their height bounded by content and SHALL NOT reserve space for action controls.

#### Scenario: Width stays within bounds

- **WHEN** content is shorter than 240pt or longer than 380pt wide
- **THEN** the bubble clamps to the 240–380pt range and overflow scrolls internally

#### Scenario: Header shows the source

- **WHEN** a bubble is presented for an envelope with `SourceInfo`
- **THEN** the header shows the tool, project name, and session short id, and text elements expose VoiceOver labels

#### Scenario: Live bubble does not reserve footer space

- **WHEN** a status/live bubble is presented with short content
- **THEN** its height is determined by the header and body content only, with no empty footer or action-row spacing

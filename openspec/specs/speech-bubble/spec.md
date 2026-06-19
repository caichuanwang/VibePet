## Purpose

Define how `SpeechBubble` renders status and completion content, anchors relative to the pet, and adapts its width and source header.

## Requirements

### Requirement: Status bubble rendering

`SpeechBubble` SHALL render `.status` content as a single line of icon plus `text`, auto-dismissing after 6–8s, and SHALL pause the auto-dismiss timer while the pointer hovers the bubble.

#### Scenario: Status shows one line and auto-dismisses

- **WHEN** a `.status` envelope is presented
- **THEN** the bubble shows a single icon+text line and auto-dismisses after 6–8s

#### Scenario: Hover pauses dismissal

- **WHEN** the pointer hovers the status bubble before it dismisses
- **THEN** the auto-dismiss timer is paused until the pointer leaves

### Requirement: Completion bubble rendering

`SpeechBubble` SHALL render `.completion` content as an icon plus `markdownSummary` rendered as Markdown, showing roughly 6 lines before scrolling internally, auto-dismissing after 8–10s with hover-to-pause. When `isError` is `true` it SHALL use a warning icon and alert coloring.

#### Scenario: Completion renders markdown and auto-dismisses

- **WHEN** a `.completion` envelope with a multi-line `markdownSummary` is presented
- **THEN** the bubble renders the Markdown, scrolls internally past ~6 lines, and auto-dismisses after 8–10s

#### Scenario: Error completion uses alert styling

- **WHEN** a `.completion` envelope has `isError == true`
- **THEN** the bubble uses a warning icon and alert coloring instead of the success styling

### Requirement: Quadrant-aware anchoring with tail tracking and boundary avoidance

`SpeechBubble` SHALL anchor relative to the pet using quadrant-aware opening direction based on the pet center within the main screen `visibleFrame` (lower half opens up, upper half opens down; right half opens left, left half opens right). A tail SHALL track the pet center, and the bubble SHALL be clamped within `visibleFrame` (12pt from edges), flipping side only when there is no room.

#### Scenario: Opening direction follows quadrant

- **WHEN** the pet center is in the lower-right quadrant of `visibleFrame`
- **THEN** the bubble opens toward the upper-left and its tail points at the pet center

#### Scenario: Bubble stays within the visible frame

- **WHEN** anchoring would place the bubble past a screen edge
- **THEN** the bubble is clamped to within 12pt of the edge while the tail still points at the pet

### Requirement: Adaptive width and source header

`SpeechBubble` SHALL use an adaptive width with a minimum of 240pt and a maximum of 380pt, scrolling internally rather than growing unbounded. It SHALL show a source header derived from `SourceInfo` as `tool · projectName · sessionShortId`, follow the system light/dark theme, and provide VoiceOver labels for text elements.

#### Scenario: Width stays within bounds

- **WHEN** content is shorter than 240pt or longer than 380pt wide
- **THEN** the bubble clamps to the 240–380pt range and overflow scrolls internally

#### Scenario: Header shows the source

- **WHEN** a bubble is presented for an envelope with `SourceInfo`
- **THEN** the header shows the tool, project name, and session short id, and text elements expose VoiceOver labels

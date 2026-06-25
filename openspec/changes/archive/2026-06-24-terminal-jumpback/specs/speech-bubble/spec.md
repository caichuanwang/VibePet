## MODIFIED Requirements

### Requirement: Status bubble rendering

`SpeechBubble` SHALL render `.status` content as a single line of icon plus `text`, auto-dismissing after 6–8s, and SHALL pause the auto-dismiss timer while the pointer hovers the bubble. When the bubble's source carries a jump target, double-clicking the non-control bubble body SHALL invoke the injected terminal jump action once and SHALL NOT alter the auto-dismiss or hover-pause behavior.

#### Scenario: Status shows one line and auto-dismisses

- **WHEN** a `.status` envelope is presented
- **THEN** the bubble shows a single icon+text line and auto-dismisses after 6–8s

#### Scenario: Hover pauses dismissal

- **WHEN** the pointer hovers the status bubble before it dismisses
- **THEN** the auto-dismiss timer is paused until the pointer leaves

#### Scenario: Double-click status jumps back

- **WHEN** a `.status` bubble with a source jump target is double-clicked on its body
- **THEN** the injected terminal jump action is invoked once with that jump target

### Requirement: Completion bubble rendering

`SpeechBubble` SHALL render `.completion` content as an icon plus `markdownSummary` rendered as Markdown, showing roughly 6 lines before scrolling internally, auto-dismissing after 8–10s with hover-to-pause. When `isError` is `true` it SHALL use a warning icon and alert coloring. When the bubble's source carries a jump target, double-clicking the non-control bubble body SHALL invoke the injected terminal jump action once and SHALL NOT alter scrolling, auto-dismiss, hover-pause, or error styling behavior.

#### Scenario: Completion renders markdown and auto-dismisses

- **WHEN** a `.completion` envelope with a multi-line `markdownSummary` is presented
- **THEN** the bubble renders the Markdown, scrolls internally past ~6 lines, and auto-dismisses after 8–10s

#### Scenario: Error completion uses alert styling

- **WHEN** a `.completion` envelope has `isError == true`
- **THEN** the bubble uses a warning icon and alert coloring instead of the success styling

#### Scenario: Double-click completion jumps back

- **WHEN** a `.completion` bubble with a source jump target is double-clicked on its body
- **THEN** the injected terminal jump action is invoked once with that jump target

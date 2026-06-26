## ADDED Requirements

### Requirement: Dashboard panel window

`VibePetApp` SHALL provide a session dashboard presented in a borderless, non-activating window with a dark frosted-glass background, styled as a popover anchored near the pet. The panel SHALL open when the pet receives a left-click "open" action (see `desktop-pet-window`) and SHALL dismiss when the user clicks outside the panel. Once opened, the panel's screen position SHALL be fixed and SHALL NOT follow the pet if the pet subsequently moves. The panel SHALL reuse the same stationary all-Spaces collection behavior as other pet-adjacent overlays so it stays on the active Space. The panel window SHALL NOT take focus away in a way that hides the pet.

#### Scenario: Left-click opens the panel near the pet

- **WHEN** the pet emits an open-dashboard action from a left click
- **THEN** the dashboard panel appears anchored near the pet within the screen `visibleFrame` with a dark frosted-glass background

#### Scenario: Clicking outside dismisses the panel

- **WHEN** the dashboard panel is open and the user clicks anywhere outside it
- **THEN** the panel closes

#### Scenario: Panel position is fixed after opening

- **WHEN** the dashboard panel is open and the pet is moved
- **THEN** the panel stays at its opened position and does not re-anchor to the pet

### Requirement: Dashboard home session list

The dashboard home view SHALL render an aggregate summary header showing total visible sessions, running count, and attention count, derived from the App's `SessionState`. Below it the home view SHALL render one row per visible session containing: a status dot (green for running, amber for needs-attention, red for an error completion), the session project name, a tool tag (`claude` or `codex`), a terminal-app tag when a jump target is known, the elapsed time since the session first started, and an **Enter** button. The rows SHALL be ordered by the same visible-session ordering as `SessionState`. Activating a row's Enter button SHALL switch the panel to that session's tab.

#### Scenario: Home lists each visible session with status and metadata

- **WHEN** the dashboard home is shown with one or more visible sessions
- **THEN** each session appears as a row with a status dot, project name, tool tag, terminal-app tag when available, elapsed time, and an Enter button

#### Scenario: Summary header reflects counts

- **WHEN** the dashboard home is shown
- **THEN** the header shows the total visible session count, the running count, and the attention count from `SessionState`

#### Scenario: Enter button opens the session tab

- **WHEN** the user activates a session row's Enter button
- **THEN** the panel switches to that session's tab content

### Requirement: Per-session tab navigation

The dashboard SHALL present per-session tabs in addition to the home view. The panel SHALL show a rounded-pill tab strip in which the active tab is visually highlighted, a top bar carrying the tool identity plus a brand-colored status dot and global actions, a content area with uniform padding, and a **Back to home** control that returns to the home view. A session tab's content area SHALL render that session's current actionable or notification content by reusing the existing `ApprovalCard`, `QuestionCard`, or `SpeechBubble` rendering rather than a standalone anchored bubble window. When a hook event arrives for a session, that session's tab content SHALL update to reflect the new state.

#### Scenario: Tab strip highlights the active tab

- **WHEN** a session tab is active
- **THEN** the tab strip renders that tab as highlighted and the others as inactive pills

#### Scenario: Back to home returns to the list

- **WHEN** a session tab is shown and the user activates Back to home
- **THEN** the panel returns to the home session list

#### Scenario: Tab content reuses existing cards

- **WHEN** a session is waiting for approval or a question, or carries completion/status content
- **THEN** its tab content area renders the corresponding `ApprovalCard` / `QuestionCard` / `SpeechBubble` inside the tab

#### Scenario: Incoming event updates the session tab

- **WHEN** a new hook event for a session is applied to `SessionState` while the dashboard is open
- **THEN** that session's tab content updates to reflect the new phase and summary

### Requirement: Dashboard empty state

When `SessionState` has no visible sessions, the dashboard SHALL still present the panel showing the active pet's name, a status dot, and a "no running sessions" message, without enlarging an illustration to fill the panel.

#### Scenario: Empty state shows pet identity, not an enlarged illustration

- **WHEN** the dashboard panel opens with no visible sessions
- **THEN** it shows the active pet's name, a status dot, and a "no running sessions" message

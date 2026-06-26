## MODIFIED Requirements

### Requirement: Pet state machine for idle, greet, and notify

`VibePetApp` SHALL define a `PetController` driving a state machine over `idle`, `greet`, `notify`, and `decide` states per the technical design §5.2. The controller's current activity SHALL be derived from the App's `SessionState` (the single source of truth) rather than from a single envelope: any attention-requiring session drives `decide`; a freshly started session drives `greet` once; completion/status envelopes drive `notify`; otherwise `idle`. `idle` plays breathing/idle animation; `greet` plays the greeting; `notify` shows a non-interactive bubble carrying `completion` / `status`; `decide` highlights the pet for attention and shows an interactive bubble for response-requiring content (`approval` / `question`). When presenting any bubble/card, the controller SHALL preserve the envelope `SourceInfo` including its optional jump target and SHALL provide the surface with a terminal jump action.

The controller's presentation surface SHALL be able to route actionable and notification content into the session dashboard's per-session tabs (see `session-dashboard`) as an alternative to standalone anchored bubble windows, while the underlying state derivation from `SessionState` is unchanged. A left-click "open" action from the pet (see `desktop-pet-window`) SHALL open the dashboard panel.

#### Scenario: Notification content enters notify state

- **WHEN** a `.completion` or `.status` envelope is applied to `SessionState` and the session needs no attention
- **THEN** it transitions to `notify` and surfaces the corresponding bubble

#### Scenario: Returns to idle after the bubble dismisses

- **WHEN** the notify bubble auto-dismisses or is dismissed and no session needs attention
- **THEN** `PetController` returns to `idle`

#### Scenario: Attention-requiring session enters decide state

- **WHEN** `SessionState` holds a session whose phase `requiresAttention` (a pending `.approval` or `.question`)
- **THEN** `PetController` transitions to `decide`, highlights the pet, and presents the interactive bubble

#### Scenario: Presentation preserves source jump target

- **WHEN** `PetController` presents status, completion, approval, or question content from an envelope whose source has a jump target
- **THEN** the surface receives that source and a jump action capable of invoking terminal jump-back for the same target

#### Scenario: Left-click opens the dashboard

- **WHEN** the pet emits an open-dashboard action from a left click
- **THEN** `PetController` opens the session dashboard panel

#### Scenario: Actionable content is available in the session tab

- **WHEN** a session is in `decide` (a pending `.approval` or `.question`) and the dashboard is open
- **THEN** that session's tab content presents the same interactive card the controller would otherwise anchor to the pet

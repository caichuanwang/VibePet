## ADDED Requirements

### Requirement: Persistent session status indicator

The pet window SHALL render a small, always-visible status indicator dot anchored to a corner of the pet sprite, whose color reflects the aggregate session state derived by `PetController` / `SessionState`: green when one or more sessions are running, orange when any session requires attention (`waitingForApproval` / `waitingForAnswer`), and a muted/gray tone when idle (no live sessions). The indicator SHALL update reactively as session state changes and SHALL NOT intercept pointer events (it never alters the sprite hit mask or click routing).

#### Scenario: Running sessions show a green dot

- **WHEN** at least one visible session is in the `running` phase and none requires attention
- **THEN** the status indicator renders in the running (green) color

#### Scenario: Attention-needing session shows an orange dot

- **WHEN** any session is `waitingForApproval` or `waitingForAnswer`
- **THEN** the status indicator renders in the attention (orange) color regardless of other running sessions

#### Scenario: Idle shows a muted dot

- **WHEN** there are no live sessions
- **THEN** the status indicator renders in the idle (muted/gray) tone

#### Scenario: Indicator does not capture clicks

- **WHEN** the user clicks on or near the status indicator over a transparent sprite pixel
- **THEN** the click is routed exactly as it would be without the indicator (passthrough/hit behavior unchanged)

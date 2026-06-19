## ADDED Requirements

### Requirement: Risk classification by tool and command pattern

`VibePetCore` SHALL provide a `RiskClassifier` that maps an approval action — the tool name plus its command/argument pattern — to a `RiskLevel`. Dangerous patterns SHALL classify as `.high`, including at minimum `rm -rf`, `sudo`, piping a network download into a shell (`curl … | sh`), and `git push --force` / `git push -f`. The rule set SHALL be data-driven (configurable) and unit-testable, and classification SHALL NOT require network access.

#### Scenario: Recursive force remove is high risk

- **WHEN** `RiskClassifier` classifies a `Bash` action whose command contains `rm -rf`
- **THEN** it returns `.high`

#### Scenario: Privilege escalation is high risk

- **WHEN** `RiskClassifier` classifies a `Bash` action whose command invokes `sudo`
- **THEN** it returns `.high`

#### Scenario: Pipe-to-shell download is high risk

- **WHEN** `RiskClassifier` classifies a `Bash` action that pipes a `curl`/`wget` download into a shell (`curl … | sh`)
- **THEN** it returns `.high`

#### Scenario: Force push is high risk

- **WHEN** `RiskClassifier` classifies a `Bash` action whose command is `git push --force` (or `-f`)
- **THEN** it returns `.high`

#### Scenario: Benign command is not high risk

- **WHEN** `RiskClassifier` classifies an ordinary non-destructive action (e.g., a plain `Read` or a benign `ls`)
- **THEN** it returns a level below `.high`

#### Scenario: Rules are configurable and testable

- **WHEN** the dangerous-pattern rule set is provided as data to `RiskClassifier`
- **THEN** classification is driven by that rule set so individual rules can be asserted in unit tests

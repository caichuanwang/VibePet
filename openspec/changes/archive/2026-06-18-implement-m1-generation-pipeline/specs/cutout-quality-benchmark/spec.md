## ADDED Requirements

### Requirement: Offline cutout benchmark over a labeled photo set

The project SHALL provide an offline benchmark that runs `LocalCutoutGenerator` over the fixed test photo set declared by `manifest.json`, each tagged with one or more benchmark labels such as `clearSubject`, `edgeHard`, `lowContrast`, and `multiSubject`, per technical design §8.2. The benchmark SHALL record per-photo generation time, aggregate P50 and P95 latency, and emit results in a form that supports manual edge-quality scoring. It SHALL run without network access and without the App UI.

#### Scenario: Benchmark runs over the full labeled set

- **WHEN** the benchmark is executed against the manifest-declared fixture set
- **THEN** it processes every photo, records each photo's elapsed time, and reports aggregate P50 and P95 latency

#### Scenario: Results are grouped by label

- **WHEN** the benchmark completes
- **THEN** its output lists each label group (`clearSubject`, `edgeHard`, `lowContrast`, `multiSubject`) with its denominator and a per-group usable-rate figure for manual review

### Requirement: KPI thresholds are evaluable from benchmark output

The benchmark output SHALL be sufficient to judge the cutout KPIs: P50 ≤ 3s, P95 ≤ 8s, usable rate ≥ 90% on the `clearSubject` subset, and ≥ 80% across the full set.

#### Scenario: Latency KPI is decidable

- **WHEN** the aggregate P50 and P95 are read from the benchmark output
- **THEN** a reviewer can determine pass/fail against P50 ≤ 3s and P95 ≤ 8s

#### Scenario: Usability KPI is decidable per subset

- **WHEN** the per-label usable rates and denominators are read
- **THEN** a reviewer can determine whether the `clearSubject` subset meets ≥ 90% and the full set meets ≥ 80%

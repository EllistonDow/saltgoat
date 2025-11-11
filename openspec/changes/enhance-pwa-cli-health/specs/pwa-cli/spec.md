## ADDED Requirements
### Requirement: PWA CLI exposes structured health information
SaltGoat MUST let operators and automation query PWA deployment health via `saltgoat pwa status` and `saltgoat pwa doctor`.

#### Scenario: JSON status for automation
- **WHEN** `saltgoat pwa status <site> --json` runs
- **THEN** it emits a JSON document containing site paths, env file presence, Pillar flags, systemd service state, port info, GraphQL/React check results, and actionable hints
- **AND** `--check` causes the command to exit non-zero if any critical check fails (service inactive, GraphQL ping failure, missing workspace, etc.).

#### Scenario: Doctor command aggregates health checks
- **WHEN** `saltgoat pwa doctor <site>` runs
- **THEN** it prints a multi-section report (service summary, GraphQL ping, React single-instance validation, recent logs, suggested next steps)
- **AND** it reuses the same health data as `status`, so automation can consume JSON via `status --json` while humans read the doctor report.

#### Scenario: Optional checks
- **WHEN** operators pass `--no-graphql` or `--no-react`
- **THEN** the status/doctor command skips those probes and marks the JSON fields as `skipped`, avoiding false negatives when backend access is blocked.

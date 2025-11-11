## Implementation Tasks
- [x] Enhance `status_site` to collect a structured data map (directories, env file, service, frontend flag, GraphQL/React results, suggestions).
- [x] Add CLI flags `--json`, `--check`, `--no-graphql`, `--no-react` to `saltgoat pwa status` and ensure exit codes reflect health when `--check` is used.
- [x] Introduce a `doctor_site` (exposed via `saltgoat pwa doctor <site>`) that prints a multi-section report (service, GraphQL, React, port, logs) and reuses the structured data.
- [x] Add a helper (`modules/lib/pwa_health.py`) to format JSON/status payloads and accompany it with unit tests.
- [x] Update `docs/pwa-project-guide.md`, `README.md`, and `todo/pwa.md` to document the new status/doctor behaviors and mark TODO 条目完成。
- [x] Add regression tests covering the helper/JSON formatting（`tests/test_pwa_health.py`）并在 CLI 层面保持兼容。

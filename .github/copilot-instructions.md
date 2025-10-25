## SaltGoat — Copilot Instructions for AI coding agents

This file gives actionable, repository-specific guidance so an AI coding agent can be productive immediately.

Key places to read first
- `README.md` — high-level project goals, supported components, and quick-start commands (install flows, `saltgoat install all`).
- `AGENTS.md` — repository guidelines and conventions (testing, formatting, packaging, security).
- `saltgoat` — the main CLI entrypoint. New CLI commands typically require adding a module script (under `modules/` or `services/`) and wiring it into the `case` dispatch in this file.
- `lib/` — shared shell helpers (`logger.sh`, `utils.sh`, `config.sh`) used across scripts — prefer这些 helper 避免重复逻辑。
- `salt/` — Salt orchestration: `salt/top.sls`, `salt/states/` and `salt/pillar/` contain the declarative state logic and pillar data.
- `scripts/code-review.sh` — canonical lint/format checks (uses `shellcheck` and `shfmt`). Run before PRs or when editing shell files.

Quick orientation (big picture)
- This repo is a Bash-first Salt-based automation toolkit that wires a large set of features through a single entrypoint (`saltgoat`).
- The codebase pattern: small, focused shell modules (under `core/`, `modules/`, `services/`) that are sourced by `saltgoat`. Salt states live under `salt/states/*` and configuration data in `salt/pillar/*`.
- Typical flow for changes that affect system configuration:
  1. Update or add a Salt state in `salt/states/` and (optionally) pillar data under `salt/pillar/`.
  2. Add or update shell helper(s) under `lib/` if re-used by multiple modules.
  3. Add/shallow-wrap the user-facing command in a module (e.g., `modules/magetools/*`) or in `services/*`.
  4. Wire the CLI handler into `saltgoat` (the main `case` dispatch) and add help/log messages.
  5. Run `bash scripts/code-review.sh -a` then test with `salt-call --local state.apply <state>` or the `saltgoat` command.

Developer workflows & commands
- Run full install locally (requires sudo): `sudo ./saltgoat system install` then `saltgoat install all --mysql-password '...'`.
- Apply Salt state locally for quick iteration: `salt-call --local state.apply optional.my-state` (the scripts often call `salt-call` with `pillar=` payloads).
- Lint and format shell code: `bash scripts/code-review.sh -a` (installs/depends on `shellcheck` and `shfmt`).
- Run repository tests: `bash tests/consistency-test.sh`、`bash tests/test_rabbitmq_check.sh`、`bash tests/test_magento_optimization.sh`。
- Check services without Salt when debugging: `systemctl is-active <service>` or `pgrep` patterns — the `saltgoat` entrypoint shows examples (it avoids `salt` for some quick checks).

Project-specific conventions & patterns
- Shell style: POSIX-friendly scripts with `#!/bin/bash`、`set -euo pipefail`（必要时说明为何放宽），4-space indentation for blocks, snake_case for function names. Follow `scripts/code-review.sh` rules.
- Module layout: feature modules live under `modules/` and `services/`; keep CLI handlers minimal and delegate logic to module scripts.
- Salt patterns: use `salt/pillar/` for per-site configuration. State IDs are lowercase with hyphens. Salt top includes `common.*`, `core.*`, `optional.*` groups (see `salt/top.sls`).
- Secrets: 默认通过 Pillar（`salt/pillar/*.sls`）管理，命令行参数可作一次性覆盖。优先级：CLI args > Pillar 值 > 默认值。不要在版本库中提交真实凭据，使用 `pillar.get(...)`/命令行传值。

Integration points & external dependencies
- Salt: many modules call `salt-call --local state.apply ...` — Salt minion is expected on the host for these workflows. Tests and scripts assume `systemctl` access to start/stop services.
- System services referenced: nginx, php-fpm (php8.3-fpm), mysql, valkey (Redis replacement), opensearch, rabbitmq, varnish, webmin. Use `systemctl` for status checks in dev/debug flows.
- Tools used in CI/dev: `shellcheck`, `shfmt`. The repo contains a GitHub workflow under `.github/workflows/`.

Concrete examples to follow
- Add a new CLI command `saltgoat foobar`:
  1. Create `modules/foobar/foobar.sh` with functions and a lightweight handler (follow `modules/magetools/magetools.sh` style).
  2. Source your module in `saltgoat` (near other `source` lines) and add a `case` branch calling your handler.
  3. Add Salt states if changes affect the system in `salt/states/optional/foobar.sls` and pillar defaults if necessary.
  4. Run `bash scripts/code-review.sh -f modules/foobar/foobar.sh` and then `sudo ./saltgoat foobar ...` to test.

Common pitfalls & how to debug them
- "Salt minion 服务未运行": tests and the `valkey-setup` script perform a `systemctl is-active salt-minion` check. If Salt is not running, either install/start the minion or run states with `salt-call --local` if appropriate.
- Mismatched configuration values: 检查 `salt/pillar/saltgoat.sls`（或运行 `saltgoat pillar show`）确认生成的凭据；若服务密码不同步，执行 `saltgoat passwords --refresh`。
- Shell syntax errors after edits: run `bash -n <file>` for syntax check and `bash scripts/code-review.sh -a` to catch style and common issues.

Where to update this doc
- If you change lint rules or main workflows (e.g., replace `shellcheck` with a different tool), update this file and `AGENTS.md`.

If anything here is incomplete or you want deeper examples (e.g., an example PR that adds a Salt state + CLI handler), tell me which area and I'll expand with a small, runnable example.

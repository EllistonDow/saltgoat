<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

# Repository Guidelines

## Project Structure & Module Organization
`./saltgoat` is the entrypoint and wires together automation hosted in `core/` (bootstrap, system install, tuning), `services/` (service orchestration), and `modules/` (feature packs such as `maintenance/`, `security/`, `monitoring/`, `optimization/`). Salt states live in `salt/states/` with matching data in `salt/pillar/`. Reusable Shell helpers stay in `lib/`, operational runbooks in `scripts/`, references in `docs/`, and validation assets in `tests/`. Initialize or update secrets by editing `salt/pillar/*.sls`（或使用 `scripts/sync-passwords.sh`）并运行 `sudo saltgoat pillar refresh` 让变更生效。

## Build, Test, and Development Commands
- `sudo ./saltgoat system install` registers the launcher system-wide for parity with production hosts。
- `sudo saltgoat install all --mysql-password 'Example123!' ...` provisions the entire stack; swap `all` for `core`, `optional`, or service verbs while iterating（命令行参数用于一次性覆盖）。
- 编辑 `salt/pillar/saltgoat.sls` 或运行 `scripts/sync-passwords.sh` 填充所需凭据，然后执行安装命令。
- `bash scripts/code-review.sh -a` runs ShellCheck, shfmt, and `scripts/check-docs.py` (doc lint)。Append `-f` to auto-format updated files。
- `bash tests/consistency-test.sh`、`bash tests/test_rabbitmq_check.sh` 与 `bash tests/test_magento_optimization.sh` 校验核心 Salt 流程和模板渲染。

## Coding Style & Naming Conventions
Write Bash in POSIX-friendly form with `#!/bin/bash` + `set -euo pipefail`（如需更宽松逻辑请注明原因），indent blocks with four spaces, and prefer snake_case for functions (`install_mysql`). Constants stay uppercase, and executable scripts必须具备可执行权限。使用 `shfmt -w` 与 `shellcheck`（调用 `scripts/code-review.sh`）保持一致风格。Salt `.sls` files use two-space YAML indentation, lowercase state IDs with hyphens, and multi-line commands as literal (`|`) blocks。

## Testing Guidelines
Scenario-specific checks reside in `tests/` under the `test_*.sh` pattern。确保脚本在失败时退出非零，并在文件头部注明先决条件。修改 Salt 状态时，补充能证明收敛的命令（如 `systemctl status` 或 `salt-call state.apply ... test=True`）并记录在 PR 描述或测试脚本中。

## Commit & Pull Request Guidelines
Follow the Conventional Commit convention (`feat:`, `fix:`, `chore:`) with concise, scoped summaries；release bumps使用 `vX.Y.Z:` 前缀。PR 应说明受影响模块、复现/验证命令，并标记 merge 后需要执行的 Salt highstate 或 `saltgoat install` 操作。

## Security & Configuration Tips
Keep secrets out of version control。Pillar 文件应提供占位符并支持 `{{ pillar.get(...) }}` 覆盖，脚本优先从 Pillar 或命令行参数获取敏感信息。必要时使用 `salt-call pillar.items` 验证现有配置。避免在仓库中引入真实证书（`.key/.pem/.p12`），CI 会阻止这类文件。

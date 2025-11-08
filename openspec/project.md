# Project Context

## Purpose
SaltGoat 提供一套可重复的自动化工具，用于在 Ubuntu 24.04 上安装、运营与维护 LEMP + Magento 环境。CLI 与 Salt 状态、事件驱动自动化（Beacon/ Reactor/ Schedule）相结合，目标是让单机或小规模集群快速完成安装、巡检、备份、降级恢复和自愈，减少人工运维成本。

## Tech Stack
- SaltStack（salt-call、state.apply、pillar 渲染、Beacon/ Reactor/ Schedule）
- Bash CLI（`./saltgoat`、`scripts/`、`modules/`）与 Python helper（`modules/lib/*.py`）
- LEMP 组件：Nginx、PHP-FPM、Percona MySQL、Valkey（Redis 兼容）、RabbitMQ、OpenSearch、Matomo
- 辅助工具：Restic、Percona XtraBackup、Telegram Bot API、S3/Minio、Systemd、Cron

## Project Conventions

### Code Style
- Bash 脚本统一 `#!/bin/bash` + `set -euo pipefail`，函数 snake_case，常量大写，使用 `shfmt -w` 与 ShellCheck (`bash scripts/code-review.sh -a`) 保持一致风格。
- Salt `.sls` 使用两空格缩进、短横线 state ID、敏感命令用 `|` literal block，pillar 允许 `pillar.get`.
- Python helpers 保持 PEP8/Black 风格（当前未强制格式化工具，但遵循 4 空格缩进和 type hints）。

### Architecture Patterns
- `./saltgoat` 是入口 CLI，按子命令 dispatch 到 `core/`、`modules/`、`services/`、`monitoring/` 中的 Bash/Python 逻辑。
- Salt states（`salt/states/*`）描述系统与应用收敛，pillar (`salt/pillar/*`) 提供配置/凭据；CLI 以本地 `salt-call` 运行，也可对接 master/minion 模式。
- 自动化分层：基础安装（core）、可选模块（modules/optional）、服务 orchestration（services/）、监控与自愈（monitoring/）。缺失 Salt 服务时降级为 Cron + CLI。
- Library 脚本和 helper（`modules/lib/*.py`、`lib/*.sh`）提供重复逻辑复用，tests 下脚本负责 dry-run 与模板校验。

### Testing Strategy
- `bash scripts/code-review.sh -a`：ShellCheck、shfmt、doc lint；必要时 `-f` 自动修复格式。
- `bash tests/consistency-test.sh`、`bash tests/test_rabbitmq_check.sh`、`bash tests/test_magento_optimization.sh` 验证核心 Salt 模板与巡检脚本。
- `saltgoat verify` 同时运行 lint + python unittest，适合作为 pre-push / CI 检查。
- 修改 Salt 状态或关键脚本时，应在 PR 描述记录复现/验证命令，例如 `salt-call state.apply ... test=True`、`systemctl status <svc>`.

### Git Workflow
- 首选 feature 分支（基于 `master`），完成后通过 PR 合并；保持 `git pull --rebase origin master` 避免分支漂移。
- Commit 遵循 Conventional Commits（`feat:`, `fix:`, `chore:`, `docs:` 等），版本发布使用 `vX.Y.Z:`.
- PR 必须说明受影响模块、复现/验证命令，以及 merge 后需要运行的 Salt highstate 或 `saltgoat install`。

## Domain Context
- 目标用户是 Magento/LEMP 运维团队，需要快速部署电商堆栈并长期维护性能、安全、备份和监控。
- 环境默认位于单机或少量节点（Ubuntu 24.04），可按需连接 salt-master，或保持独立 `salt-call --local` 模式。
- Magento 站点通常位于 `/var/www/<site>`，Pillar 记录站点域名、SSL、CSP、PWA 配置，monitoring 通过 Telegram/Salt events 报警。

## Important Constraints
- 仅支持 Ubuntu 24.04（或兼容内核），假设具备 sudo 权限与可访问的 apt 仓库。
- 禁止将真实凭据/证书提交至仓库；pillar 只存占位符，可通过 `scripts/sync-passwords.sh` 或 `saltgoat pillar refresh` 同步到本机。
- 需要在缺失 Salt 服务时自动降级到 Cron；若启用 master/minion，必须保证 Beacon/ Reactor 权限安全。
- 网络/备份依赖外部对象存储（S3/Minio）与 Telegram API，需要在受限环境下提供替代方案或降级。

## External Dependencies
- SaltStack（salt-master/salt-minion/salt-call）
- Ubuntu packaging：apt、systemd、cron
- LEMP + 周边服务：Nginx、PHP-FPM、Percona MySQL、Valkey、RabbitMQ、OpenSearch、Matomo
- 备份/存储：Restic、Percona XtraBackup、S3/Minio、rsync
- 消息与通知：Telegram Bot API、Salt event bus

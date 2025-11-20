# SaltGoat 自动化模块

SaltGoat 的自动化模块围绕自定义 Salt Execution Module 与 Runner 构建，提供脚本模板、计划任务、日志管理的统一入口。所有命令默认运行在本机 `salt-call --local` 上，并直接对 Salt Schedule 进行读写——如果 `salt-minion` 未运行，命令会立即报错，提示先恢复 Minion。

## 📦 目录布局

| 路径 | 说明 |
|------|------|
| `/srv/saltgoat/automation/scripts/` | 自动化脚本模板（`*.sh`） |
| `/srv/saltgoat/automation/jobs/` | 任务配置（JSON），记录调度后端、状态、最近执行信息 |
| `/srv/saltgoat/automation/logs/` | 任务运行日志，按名称+日期归档 |

> 目录位置可通过 Pillar (`saltgoat:automation:*`) 覆盖，自定义状态见 `salt/states/optional/automation/`。

## 🚀 命令速览

```bash
# 脚本管理
sudo saltgoat automation script create health-check
sudo saltgoat automation script list
sudo saltgoat automation script run health-check
sudo saltgoat automation script delete health-check

# 任务调度
sudo saltgoat automation job create health-check "*/10 * * * *"
sudo saltgoat automation job list
sudo saltgoat automation job enable health-check
sudo saltgoat automation job run health-check
sudo saltgoat automation job disable health-check

# 日志
sudo saltgoat automation logs list
sudo saltgoat automation logs view health-check_20241026.log
sudo saltgoat automation logs cleanup 14
```

### 模板示例

```bash
# 创建预置模板（脚本 + Salt Schedule/cron）
sudo saltgoat automation templates system-update
sudo saltgoat automation templates backup-cleanup
sudo saltgoat automation templates log-rotation
sudo saltgoat automation templates security-scan
```

## 🧠 设计要点

- **自动同步模块**：命令执行前会调用 `saltutil.sync_modules` 与 `saltutil.sync_runners`，确保 `salt/_modules/saltgoat.py` 与 `salt/runners/saltgoat.py` 立即生效。
- **Salt Schedule-only**：计划任务仅注册到 Salt Schedule；请确保 `salt-minion` 服务运行且可执行 `schedule.list`。
- **配置即状态**：任务定义持久化为 JSON，`automation_job_run` 会更新 `last_run`/`last_retcode`/`last_duration` 字段，方便外部集成读取。
- **日志聚合**：每次任务执行都会将 stdout/stderr 追加到 `logs/<job>_YYYYMMDD.log`，可配合 `automation logs cleanup` 设置保留期。

## 🔍 与 Salt 状态的衔接

- `salt/states/optional/automation/init.sls`：创建基础目录结构。
- `salt/states/optional/automation/script.sls`：渲染脚本模板（可通过 Pillar 提供自定义内容）。
- `salt/states/optional/automation/job.sls`：写入任务 JSON、注册 Salt Schedule 或 cron。

在需要批量化部署时，可在 Pillar 中定义 `automation:script`/`automation:job`，然后调用自定义 Runner `salt-run saltgoat.automation_job_create ...` 分发到多台主机。

## ⚠️ 使用提示

- 建议始终确保 `salt-minion` 运行，以便通过 Salt Schedule/Event Reactor 保持状态一致性；若服务停止，命令会直接报错，修复后重新 `enable` 即可恢复计划任务。
- 任务脚本默认加上 `set -euo pipefail` 与日志工具函数，可按需扩展。若使用自定义脚本，请确保具有可执行权限以及适当的错误处理。
- 自动化目录下不应存放敏感凭据，推荐通过 Pillar/环境变量在执行时注入。

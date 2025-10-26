# SaltGoat 自动化模块

SaltGoat 的自动化模块围绕自定义 Salt Execution Module 与 Runner 构建，提供脚本模板、计划任务、日志管理的统一入口。所有命令默认运行在本机 `salt-call --local` 上：当检测到 `salt-minion` 可用时，任务会注册为 Salt Schedule；否则自动降级至 `/etc/cron.d/saltgoat-automation-*` 确保仍能按计划执行。

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
saltgoat automation script create health-check
saltgoat automation script list
saltgoat automation script run health-check
saltgoat automation script delete health-check

# 任务调度
saltgoat automation job create health-check "*/10 * * * *"
saltgoat automation job list
saltgoat automation job enable health-check
saltgoat automation job run health-check
saltgoat automation job disable health-check

# 日志
saltgoat automation logs list
saltgoat automation logs view health-check_20241026.log
saltgoat automation logs cleanup 14
```

### 模板示例

```bash
# 创建预置模板（脚本 + Salt Schedule/cron）
saltgoat automation templates system-update
saltgoat automation templates backup-cleanup
saltgoat automation templates log-rotation
saltgoat automation templates security-scan
```

## 🧠 设计要点

- **自动同步模块**：命令执行前会调用 `saltutil.sync_modules` 与 `saltutil.sync_runners`，确保 `salt/_modules/saltgoat.py` 与 `salt/runners/saltgoat.py` 立即生效。
- **Schedule 首选，Cron 兜底**：当 `salt-minion` 服务存在且可执行 `schedule.list` 时，计划任务注册为 Salt Schedule；否则会在 `/etc/cron.d/` 下生成同名 cron 文件。
- **配置即状态**：任务定义持久化为 JSON，`automation_job_run` 会更新 `last_run`/`last_retcode`/`last_duration` 字段，方便外部集成读取。
- **日志聚合**：每次任务执行都会将 stdout/stderr 追加到 `logs/<job>_YYYYMMDD.log`，可配合 `automation logs cleanup` 设置保留期。

## 🔍 与 Salt 状态的衔接

- `salt/states/optional/automation/init.sls`：创建基础目录结构。
- `salt/states/optional/automation/script.sls`：渲染脚本模板（可通过 Pillar 提供自定义内容）。
- `salt/states/optional/automation/job.sls`：写入任务 JSON、注册 Salt Schedule 或 cron。

在需要批量化部署时，可在 Pillar 中定义 `automation:script`/`automation:job`，然后调用自定义 Runner `salt-run saltgoat.automation_job_create ...` 分发到多台主机。

## ⚠️ 使用提示

- 建议在具备 `salt-minion` 的环境下运行，享受 Salt Schedule/Event Reactor 带来的状态一致性；缺少时仍会自动降级，后续只需启用 `salt-minion` 并重新 `enable` 即可切换回 Schedule。
- 任务脚本默认加上 `set -euo pipefail` 与日志工具函数，可按需扩展。若使用自定义脚本，请确保具有可执行权限以及适当的错误处理。
- 自动化目录下不应存放敏感凭据，推荐通过 Pillar/环境变量在执行时注入。

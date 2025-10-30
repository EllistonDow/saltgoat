# SaltGoat · LEMP & Magento Automation Toolkit

SaltGoat 把 Salt 状态、事件驱动自动化与一套 CLI 工具整合在一起，用于在 **Ubuntu 24.04** 上快速部署、维护并监控 LEMP/Magento 环境。默认以单机“本地模式”运行——Salt 负责配置收敛，CLI 封装日常操作；若主机安装了 `salt-minion`/`salt-master`，同一套配置即可切换为 Beacon + Reactor + Salt Schedule 的事件驱动体系。

---

## 🌐 适用场景

- 快速构建或重装 Magento + LEMP 服务栈（Nginx / Percona MySQL / PHP-FPM / Valkey / RabbitMQ / OpenSearch / Matomo 等）。
- 需要一套可观测、可回滚、自动降级的运维脚本（安装、备份、维护、巡检、安全、性能优化）。
- 希望按需 “拔高” 到事件驱动自动化（Salt Beacon、Reactor、Salt Schedule），同时仍可在缺失 Salt 服务时保持 Cron + CLI 兜底。

---

## 📁 仓库结构

| 目录 / 组件 | 说明 |
|-------------|------|
| `saltgoat` + `modules/` | CLI 入口与模块脚本（安装、维护、备份、监控等）；会调用 Salt 或直接执行系统命令。 |
| `core/`、`salt/states/core/` | 最小可行安装：系统初始化、软件包、基础安全策略。 |
| `salt/states/optional/` | 可选功能：Restic 备份、XtraBackup、Magento 维护、Salt Beacon/Reactors 等。 |
| `services/`, `monitoring/` | 附加服务与监控任务脚本。 |
| `docs/` | 安装、维护、权限、备份、故障排查等详细文档。 |
| `tests/` | 一致性检测、模板渲染、Magento 优化 dry-run 脚本。 |

---

## ✅ 核心能力

- **一键安装 LEMP + Magento 依赖**：支持 Nginx / Percona MySQL / PHP-FPM / Valkey / RabbitMQ / OpenSearch / Matomo 等组件。
- **模块化 CLI**：`sudo saltgoat install | maintenance | magetools | monitor | automation …` 覆盖安装、巡检、备份、安全、性能调优等日常操作。
- **事件驱动自动化（可选）**：启用 `salt-minion`/`salt-master` 后，`sudo saltgoat monitor enable-beacons` 下发服务自愈、资源阈值告警、配置变更处理等 Reactor，Salt Schedule 自动替换 Cron。
- **自动降级策略**：检测到缺失 `salt-minion` 时，所有计划任务会写入 `/etc/cron.d/`；Reactor 命令也会提示降级状态，保证功能可用。
- **多层备份**：Restic + S3/Minio 快照、Percona XtraBackup 热备、单库 mysqldump（含 Salt Schedule 示例），并通过 Telegram / Salt event 写日志。
- **完善的维护体系**：`sudo saltgoat magetools maintenance` 日/周/月任务、健康检查、权限修复，全部附带 Telegram 通知和日志。

---

## 🧰 前置要求

| 类型 | 说明 |
|------|------|
| 基础系统 | Ubuntu 24.04 (x86_64)，拥有 `sudo` 权限。 |
| 基础工具 | `git`, `bash`, `systemd`（其余依赖由 SaltGoat 自动安装）。 |
| 事件驱动（可选） | `salt-minion`（本机），如需 Reactor/多机协同再安装 `salt-master`。未满足时会自动退回 Cron + CLI 流程。 |

> **安装 Salt Minion（可选）**  
> ```bash
> sudo apt update
> sudo apt install -y salt-minion
> sudo systemctl enable --now salt-minion
> ```
> 在测试或单机场景需要 Reactor 时，可加装 `salt-master`：  
> ```bash
> sudo apt install -y salt-master
> sudo systemctl enable --now salt-master
> ```

---

## 🚀 快速上手

1. **获取代码 & 安装 CLI**
   ```bash
   git clone https://github.com/EllistonDow/saltgoat.git
   cd saltgoat
   sudo ./saltgoat system install     # 把 CLI 链接到 /usr/local/bin
   ```
2. **初始化 Pillar（凭据/变量）**
   ```bash
   sudo saltgoat pillar init          # 生成 salt/pillar/saltgoat.sls（附带随机密码）
   sudo saltgoat pillar show          # 审核并按需修改
   # 参考 *.sample 文件快速复制模板
   cp salt/pillar/magento-optimize.sls.sample salt/pillar/magento-optimize.sls
   cp salt/pillar/magento-schedule.sls.sample salt/pillar/magento-schedule.sls
   cp salt/pillar/nginx.sls.sample salt/pillar/nginx.sls
   # 秘钥模板位于 salt/pillar/secret/*.sls.example，复制后填入真实密码
   # 其它 Pillar 也提供 *.sample 文件，可按需复制后修改
   ```
   > ⚠️ **权限提示**  
   > 除 `help`、`git`、`lint`、`format` 等只读命令外，SaltGoat 会访问 `/etc`、`/var/lib/saltgoat` 以及 Salt Caller 接口。请默认使用 `sudo saltgoat …`，CLI 也会在需要时自动尝试用 sudo 重新执行。

3. **执行安装**
   ```bash
   sudo saltgoat install all
   sudo saltgoat install all --optimize-magento      # 安装完立即执行 Magento 优化
   ```
4. **启用事件驱动（可选）**
   ```bash
   sudo saltgoat monitor enable-beacons
   sudo saltgoat monitor beacons-status
   sudo saltgoat magetools cron <site> install       # 下发 Salt Schedule；若缺少 salt-minion 会自动写 /etc/cron.d/
   ```

更多安装细节、Matomo 部署与 Pillar 示例请参考 [`docs/INSTALL.md`](docs/INSTALL.md)。

---

## 🔁 运维与自动化指南

### Magento & LEMP 维护
- `sudo saltgoat magetools maintenance <site> daily|weekly|monthly|health …`
- `sudo saltgoat magetools cron <site> install|status|test|logs|uninstall`
  - 默认安装 Salt Schedule；若无 `salt-minion` 则写入 `/etc/cron.d/magento-maintenance`。
  - 支持在 Pillar 中定义 `magento_schedule.mysql_dump_jobs`，以不同频率导出单个数据库：
    ```yaml
    magento_schedule:
      mysql_dump_jobs:
        - name: bankmage-dump-every-2h
          cron: '0 */2 * * *'
          database: bankmage
          backup_dir: /home/doge/Dropbox/bank/databases
          repo_owner: doge
    ```
    每次执行都会写入 `/var/log/saltgoat/alerts.log` 并推送 Telegram。
  - `magento_schedule.api_watchers` 可轮询 Magento REST API，将新订单/新用户同步到 Telegram（首次运行仅建立基线，不推送历史数据）。
- 维护流程、权限修复、故障排查详见 [`docs/MAGENTO_MAINTENANCE.md`](docs/MAGENTO_MAINTENANCE.md)。

### 监控与巡检
- `sudo saltgoat monitor system|services|resources|logs|security|performance`
- `sudo saltgoat monitor report daily` 生成日报到 `/var/log/saltgoat/monitor/`
- `sudo saltgoat monitor alert resources` 即时检查 CPU/内存/磁盘/关键服务并推送 Telegram 告警（触发 Salt 事件 `saltgoat/monitor/resources`）
- `sudo saltgoat monitor report daily --no-telegram` 可生成日报而不推送；默认会写日志并发送 Telegram 摘要
- `sudo saltgoat monitor enable-beacons`：启用 Beacon/Reactors；若缺少 `salt-minion` 会提示并降级。
- `sudo saltgoat schedule enable`：下发 SaltGoat 自身任务（内存、日志清理等），同样支持自动降级到 cron。
- Salt Beacon 触发的 systemd 自愈流程会自动执行 `systemctl restart`，并把成功/失败状态写入 `/var/log/saltgoat/alerts.log`、发送 Telegram，同时重新发布 Salt 事件（便于级联自动化）。

### 自动化脚本 (Automation)
- `sudo saltgoat automation script <create|list|edit|run|delete>`：生成并维护 `/srv/saltgoat/automation/scripts/*.sh`。
- `sudo saltgoat automation job <create|list|enable|disable|run|delete>`：首选 Salt Schedule 注册任务；未检测到 `salt-minion` 会自动写 `/etc/cron.d/saltgoat-automation-*`。
- `sudo saltgoat automation logs <list|view|tail|cleanup>`：统一管理任务日志。

### 备份策略
- Restic 快照：`sudo saltgoat magetools backup restic install --site <name> [--repo <path>]` 为单站点创建 systemd 定时器；`run/summary/logs` 子命令可手动触发与巡检。
- Percona XtraBackup：`sudo saltgoat magetools xtrabackup mysql run`；配置详见 [`docs/MYSQL_BACKUP.md`](docs/MYSQL_BACKUP.md)。
- 单库导出：`sudo saltgoat magetools xtrabackup mysql dump --database <db> --backup-dir <path>` 会输出体积、写 Salt event，并发 Telegram。
- 所有备份事件都会写入 `/var/log/saltgoat/alerts.log`，便于审计。

### Telegram 通知 & ChatOps
- `optional.salt-beacons` 会自动部署 `/opt/saltgoat-reactor` 辅助脚本以及 `/etc/saltgoat/telegram.json` 配置，所有资源告警、备份、服务自愈都会同步到 Telegram。
- 新增 `/etc/saltgoat/chatops.json`（模板：`salt/pillar/chatops.sls.sample`）。复制后按需填写 `allowed_chats`、`approvers`、命令映射，例如：
  ```yaml
  saltgoat:
    chatops:
      commands:
        - name: maintenance weekly
          match: ["maintenance", "weekly"]
          arguments:
            - name: site
              position: 0
              required: true
              choices: ["bank", "tank"]
          command:
            - saltgoat
            - magetools
            - maintenance
            - "{site}"
            - weekly
        - name: cache clean
          match: ["cache", "clean"]
          arguments:
            - name: site
              position: 0
              required: true
          command:
            - saltgoat
            - magetools
            - maintenance
            - "{site}"
            - cleanup
          requires_approval: true
          forward_args: true
  ```
- 启用后即可在授权的 Telegram 会话中发送 `/saltgoat maintenance weekly bank`、`/saltgoat cache clean tank --allow-valkey-flush` 等指令。标记 `requires_approval: true` 的命令会生成一次性 Token，需管理员发送 `/saltgoat approve <token>` 才会真正执行，执行结果与输出同样会回传到 Telegram 并写入 `chatops.log`。

---

## 📚 主要文档

- [`docs/INSTALL.md`](docs/INSTALL.md)：安装、Pillar、Matomo、Salt 依赖说明。
- [`docs/MAGENTO_MAINTENANCE.md`](docs/MAGENTO_MAINTENANCE.md)：维护流程、命令速查、Salt Schedule/Beacon/cron 降级。
- [`docs/MAGENTO_PERMISSIONS.md`](docs/MAGENTO_PERMISSIONS.md)：站点权限策略、修复脚本。
- [`docs/BACKUP_RESTIC.md`](docs/BACKUP_RESTIC.md)：Restic 仓库配置与恢复流程。
- [`docs/MYSQL_BACKUP.md`](docs/MYSQL_BACKUP.md)：Percona XtraBackup 安装、巡检与恢复。
- [`docs/SECRET_MANAGEMENT.md`](docs/SECRET_MANAGEMENT.md)：密钥模板、Pillar Secret 工作流与密码更新步骤。
- [`docs/TELEGRAM_TOPICS.md`](docs/TELEGRAM_TOPICS.md)：Telegram 话题 `chat_id`/`message_thread_id` 对照表及通知分类建议。
- [`docs/CHANGELOG.md`](docs/CHANGELOG.md)：版本更新。

---

## 🧪 测试与代码质量

```bash
bash scripts/code-review.sh -a        # shfmt + ShellCheck
bash tests/consistency-test.sh        # 基础一致性检测
bash tests/test_magento_optimization.sh   # Magento 优化 dry-run
```

提交 PR 前建议至少运行 `code-review.sh -a`，并同步更新相关文档。

---

## 🤝 贡献指南

1. Fork & Clone -> 建立分支。  
2. 修改代码 / Salt 状态 / 文档。  
3. 执行必要测试（见上一节）。  
4. 提交 PR 时附带：
   - 改动说明（功能点 / Bugfix / 文档更新）。
   - 相关命令或输出截图（安装、维护、备份、Salt 状态等）。
   - 若更改 Salt 状态，请说明测试方法（`salt-call state.apply ... test=True` 或 DRY-RUN 输出）。

欢迎就新的模块、改进建议或多机场景的最佳实践提交 Issue/PR！

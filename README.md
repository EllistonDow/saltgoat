# SaltGoat · LEMP & Magento Automation Toolkit

SaltGoat 把 Salt 状态、事件驱动自动化与一套 CLI 工具整合在一起，用于在 **Ubuntu 24.04** 上快速部署、维护并监控 LEMP/Magento 环境。默认以单机“本地模式”运行——Salt 负责配置收敛，CLI 封装日常操作；若主机安装了 `salt-minion`/`salt-master`，同一套配置即可切换为 Beacon + Reactor + Salt Schedule 的事件驱动体系。

---

## 🌐 适用场景

- 快速构建或重装 Magento + LEMP 服务栈（Nginx / Percona MySQL / PHP-FPM / Valkey / RabbitMQ / OpenSearch / Matomo 等）。
- 需要一套可观测、可回滚、自动降级的运维脚本（安装、备份、维护、巡检、安全、性能优化）。
- 希望按需 “拔高” 到事件驱动自动化（Salt Beacon、Reactor、Salt Schedule），并接受所有计划任务统一依赖 Salt Schedule（即须保持 `salt-minion` 运行）。

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
- **事件驱动自动化（可选）**：启用 `salt-minion`/`salt-master` 后，`sudo saltgoat monitor enable-beacons` 下发服务自愈、资源阈值告警、配置变更处理等 Reactor，Salt Schedule 统一管理所有计划任务。
- **Salt Schedule-only 策略**：`salt-minion` 是计划任务的唯一依赖；若服务未运行，相关任务会直接报错，避免静默降级到系统 cron。
- **多层备份**：Restic + S3 兼容对象存储快照、Percona XtraBackup 热备、单库 mysqldump（含 Salt Schedule 示例），并通过 Telegram / Salt event 写日志。`sudo saltgoat install all` 会自动安装 Restic 最新稳定版与 Percona XtraBackup 8.4，无需额外步骤。
- **Dropbox 自愈守护**：在 `salt/pillar/secret/dropbox.sls` 启用配置后，安装流程会下发自带的 systemd unit（`Restart=always`）并将 `dropbox` 加入 Beacon/ Reactor，自检失败会由 Salt 自动重启，同时推送 Telegram 告警。
- **完善的维护体系**：`sudo saltgoat magetools maintenance` 日/周/月任务、健康检查、权限修复，全部附带 Telegram 通知和日志。

### 🛠 智能自愈与巡检

- `sudo saltgoat magetools schedule auto`：扫描现有站点自动补齐 Magento cron/维护/API Watch/备份/统计任务，并清理已移除站点的残留计划任务。
- `sudo saltgoat monitor auto-sites`：由 `modules/lib/monitor_auto_sites.py` 解析 `/var/www` 与 Nginx 配置生成 `salt/pillar/monitoring.sls`，只在检测到站点/Beacon 变更时自动刷新 Pillar；Telegram 话题映射统一维护在 `salt/pillar/telegram-topics.sls`。
- `sudo saltgoat monitor quick-check`：即时执行一遍资源/站点巡检，将结果直接输出到终端（适合临时排查）。
- `modules/monitoring/resource_alert.py`：定时评估资源与站点可用性，失败后记录 `systemctl` 与 `journalctl` 摘要、触发自愈并通过 Telegram/Salt Event 通知；内置重试与冷却窗口避免频繁重启，RabbitMQ/Valkey 等核心服务若异常会自动纳入重启列表。
- **Swap 监控与自愈**：`resource_alert` 现会读取 `/proc/meminfo` 追踪 swap 占用，按 `saltgoat:monitor:thresholds:swap`（默认 5% / 20% / 40%）触发 Notice/Warning/Critical，并在达到 Critical 时依据 `saltgoat:monitor:swap:autoheal_services`（默认重启 `php8.3-fpm`）自动排程服务自愈与 Telegram 通知。
- **多站点自动扩容**：`saltgoat magetools multisite create|rollback` 会在新增/移除 store view 后调用 PHP-FPM 池 helper，更新 `magento_optimize:sites.<site>.php_pool.weight`、记录 store 列表并触发 `salt-call --local state.apply core.php` 及 `saltgoat/autoscale/<host>` 事件，避免 `magento-<site>` 池在新域名上线后仍停留在旧容量。
- `saltgoat swap status|ensure|tune`：统一管理 swap（查看设备、扩容/创建 swapfile、调整 `vm.swappiness`），并提供 `saltgoat swap ensure --min-size 8G` 供 `resource_alert` 或值班脚本一键自愈。
- `salt/states/optional/magento-schedule.sls` 默认下发每日 `saltgoat monitor report daily` 与 `saltgoat magetools schedule auto`，确保巡检与计划任务长期收敛。
- `saltgoat pillar backup` 一键将 `salt/pillar` 打包到 `/var/lib/saltgoat/pillar-backups/`，配合版本库和外部存储实现配置留痕。
- `saltgoat verify` 运行 `scripts/code-review.sh -a` 与 `python3 -m unittest`，适合作为本地 Git hook 或 CI 预检命令，确保脚本/单元测试通过后再发布。
- `saltgoat gitops-watch` 在 Git hook 或 CI 中统一执行 `saltgoat verify`、`saltgoat monitor auto-sites --dry-run` 并检测 Git 配置漂移，提前发现渲染/站点探测问题，避免把脏 Pillar 或未同步分支带入生产；输出若提示 `Behind > 0` 先 `git pull --rebase origin master`，如列出 `__pycache__/` 或 `*.pyc` 即执行 `git rm --cached <file>` 后重试。
- `python3 modules/lib/nginx_pillar.py --pillar salt/pillar/nginx.sls create --site bank --domains bank.example.com` 等子命令可直接管理站点/SSL/CSP/ModSecurity Pillar，`saltgoat nginx ...` 内部已调用同一 CLI，便于脚本化集成。
- `python3 modules/lib/pwa_helpers.py load-config --config salt/pillar/magento-pwa.sls --site bank` 输出 JSON/ENV 组合，辅助 `saltgoat pwa install` 完成自动化；同一 helper 还提供 `ensure-env-default`, `sanitize-checkout`, `patch-product-fragment` 等命令，方便单独调试 PWA Studio 覆盖。
- `saltgoat smoke-suite` 快速冒烟：依次执行 `verify`、`monitor auto-sites --dry-run`、`monitor quick-check` 与 `doctor --format markdown`，产出 `/tmp/saltgoat-doctor-*.md` 报告用于留痕。
- `saltgoat doctor --format text|json|markdown` 输出 Goat Pulse + 磁盘/进程/告警快照，可直接生成 CLI 文本、JSON 供自动化消费，或 Markdown 片段方便贴到工单。
- `scripts/goat_pulse.py --plain --metrics-file /var/lib/saltgoat/goat-pulse.prom` 既能在终端显示 ASCII 面板，也能禁用 ANSI 清屏供 `saltgoat doctor` / 日志抓取，同时导出 Prometheus 兼容指标。
- `python3 modules/lib/nginx_context.py site-metadata --site <name> --pillar salt/pillar/nginx.sls` 输出站点根目录、server_name、Varnish/HTTPS 标记与 Magento run context，供 `monitor auto-sites`、`magetools varnish` 以及外部脚本统一解析。
- `modules/lib/salt_event.py`：统一封装 Salt Event 发送逻辑（`python3 modules/lib/salt_event.py send --tag saltgoat/test key=value`），shell 脚本会自动回落到 `salt-call event.send`，便于在没有 `salt.client` 的环境里保持行为一致。

### 🗃 服务总览

- `saltgoat services [--format json]`：读取 Pillar 与当前配置，列出数据库、缓存、RabbitMQ、Webmin 等关键服务的访问地址、端口及默认凭据，便于交接或巡检（建议以 sudo 执行）。

---

## 🧰 前置要求

| 类型 | 说明 |
|------|------|
| 基础系统 | Ubuntu 24.04 (x86_64)，拥有 `sudo` 权限。 |
| 基础工具 | `git`, `bash`, `systemd`（其余依赖由 SaltGoat 自动安装）。 |
| 备份工具 | SaltGoat 会自动安装 **Percona XtraBackup 8.4** 与 **Restic 最新稳定版**，无需手动准备。 |
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
   sudo saltgoat pillar init          # 首次生成 salt/pillar/saltgoat.sls（附带随机密码，若需重置请加 --force）
   sudo saltgoat pillar show          # 审核并按需修改
   # 参考 *.sample 文件快速复制模板
   cp salt/pillar/magento-optimize.sls.sample salt/pillar/magento-optimize.sls
   cp salt/pillar/magento-schedule.sls.sample salt/pillar/magento-schedule.sls
   cp salt/pillar/nginx.sls.sample salt/pillar/nginx.sls
   # 秘钥模板位于 salt/pillar/secret/*.sls.example，复制后填入真实密码
   # 其它 Pillar 也提供 *.sample 文件，可按需复制后修改
   ```
> 💡 **无需担心遗漏**：若跳过此步骤，`sudo saltgoat install all` 会在首次运行时自动生成 `salt/pillar/secret/saltgoat.sls` 并写入随机强密码，同时刷新 Pillar 缓存；`pillar init` 仅在首次部署时需要，若已生成可通过 `saltgoat pillar init --force` 显式重置。
> ⚠️ **权限提示**  
   > 除 `help`、`git`、`lint`、`format` 等只读命令外，SaltGoat 会访问 `/etc`、`/var/lib/saltgoat` 以及 Salt Caller 接口。请默认使用 `sudo saltgoat …`，CLI 也会在需要时自动尝试用 sudo 重新执行。

3. **执行安装**
   ```bash
   sudo saltgoat install all
   sudo saltgoat install all --optimize-magento      # 安装完立即执行 Magento 优化
   ```
   > 安装流程会自动完成：
   > - 通过 Salt 官方 bootstrap 安装 `salt-master`/`salt-minion`（3007.8），并写入 `file_client: local` 与 `state_queue: True`
   > - 生成/更新 `salt/pillar/secret/*.sls`（含随机强密码）并刷新 Pillar
   > - 部署 Restic 0.16.3、Percona XtraBackup 8.4 及其 systemd timer
   > - 自动安装 `python3-pymysql` / `python3-mysqldb`，确保 `salt-call mysql.*` 与 `saltgoat magetools mysql` 可直接执行
   > - 收敛 Pillar `salt-beacons`/`salt-reactor`，启用 CSP Level 3 + ModSecurity Level 5
   > - 自动执行 `saltgoat monitor enable-beacons`、`saltgoat magetools schedule auto` 及 Telegram 话题同步
4. **启用事件驱动（可选）**
   ```bash
   sudo saltgoat monitor enable-beacons
   sudo saltgoat monitor beacons-status
sudo saltgoat magetools cron <site> install       # 下发 Salt Schedule（需 salt-minion 已运行）
   ```
   > `install all` 已在收尾阶段执行过 `saltgoat monitor enable-beacons`，此命令主要用于后续更新 Pillar 或在调试场景下手动重载。

更多安装细节、Matomo 部署与 Pillar 示例请参考 [`docs/install.md`](docs/install.md)。

---

## 🔧 Helper Scripts

| 脚本 | 作用 |
|------|------|
| `modules/lib/monitor_auto_sites.py` | 直接生成/更新 `salt/pillar/monitoring.sls`（例如 `python3 modules/lib/monitor_auto_sites.py --site-root /var/www --nginx-dir /etc/nginx/sites-enabled --monitor-file salt/pillar/monitoring.sls`）。CLI 会基于脚本输出自动刷新 Pillar 与 Telegram 话题。 |
| `modules/lib/salt_event.py` | `send` 子命令优先尝试 `salt.client.Caller`，失败时输出 JSON 供 `salt-call event.send` 使用；`format` 子命令仅做 JSON 序列化，适合 CI 或自定义脚本。 |
| `modules/lib/maintenance_pillar.py` | 把 `saltgoat magetools maintenance` 导出的环境变量整理成 Pillar JSON，既能被 CLI 使用，也方便排查：`SITE_NAME=bank SITE_PATH=/var/www/bank python3 modules/lib/maintenance_pillar.py`. |
| `modules/lib/automation_helpers.py` | 为 `saltgoat automation` 系列脚本提供 `render-basic`、`extract-field`、`parse-paths` 等 JSON 解析工具，便于在其他 shell/CI 场景复用 Salt 返回值。 |
| `scripts/goat_pulse.py --metrics-file /var/lib/node_exporter/textfile/saltgoat.prom` | 生成 Goat Pulse 面板的同时，把服务状态、HTTP 探活、Varnish 命中率等指标写入 Prometheus textfile，配合 node_exporter textfile collector 即可在 Grafana/Alertmanager 监控。 |
| `scripts/doctor.sh` (`saltgoat doctor`) | 汇总 Goat Pulse（纯文本）、磁盘/进程摘要和最近 `alerts.log`，一条命令生成健康报告，便于排障粘贴。 |

所有 helper 都是独立 CLI，可在 CI 或临时脚本中直接调用。

---

## 🔁 运维与自动化指南

### Magento & LEMP 维护
- `sudo saltgoat magetools maintenance <site> daily|weekly|monthly|health …`
- `sudo saltgoat magetools cron <site> install|status|test|logs|uninstall`
  - 仅依赖 Salt Schedule，请先确保 `salt-minion` 处于运行状态。
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
  - `magento_schedule.stats_jobs` 可定时运行 `saltgoat magetools stats --period <daily|weekly|monthly>`，自动生成业务汇总并写入 `/var/log/saltgoat/alerts.log`（可选推送 Telegram）。
- 维护流程、权限修复、故障排查详见 [`docs/magento-maintenance.md`](docs/magento-maintenance.md)。
- `sudo saltgoat pwa install <site> [--with-pwa]`：读取 `salt/pillar/magento-pwa.sls`，自动部署全新 Magento + PWA 站点并串联 Valkey / RabbitMQ / Cron，详见 [`docs/magento-pwa.md`](docs/magento-pwa.md)。支持通过 `cms.home` 配置自动创建/更新 `pwa_home` 页面。
- `sudo saltgoat pwa status <site> [--json] [--check]`：输出 PWA 目录、systemd 服务、GraphQL/React/端口健康数据；`--json` 供 automation 消费，`--check` 在异常时返回非零。
- `sudo saltgoat pwa doctor <site>`：一键生成健康报告（GraphQL/React/端口/最近日志/建议），便于排障或集成到巡检脚本。
- `sudo saltgoat pwa sync-content|remove <site>`：重新应用 overrides/构建或清理前端服务。
- React/依赖统一通过 Yarn 管理，`sync-content --rebuild` 会校验 `@saltgoat/venia-extension` workspace 并阻止 `package-lock.json` 残留，必要时请手动执行 `yarn list --pattern react` 确认仅保留一个版本。
- PWA 项目细节与更新准则请参考 [`docs/pwa-project-guide.md`](docs/pwa-project-guide.md)。
- 自定义前端组件统一封装在 `@saltgoat/venia-extension`（同步自 `modules/pwa/workspaces/saltgoat-venia-extension`），避免直接修改官方 Venia 代码。
- PHP-FPM 进程池默认按 CPU / 内存容量自动放大（可在 Pillar `saltgoat:php_fpm` 配置最小值、上限与 per_cpu 系数），`resource alert` 会在使用率逼近上限时提前预警。

### 监控与巡检
- `sudo saltgoat monitor system|services|resources|logs|security|performance`
- `sudo saltgoat monitor report daily` 生成日报到 `/var/log/saltgoat/monitor/`
- `sudo saltgoat monitor alert resources` 即时检查 CPU/内存/磁盘/关键服务并推送 Telegram 告警（触发 Salt 事件 `saltgoat/monitor/resources`）
- Pillar `notifications.telegram` 决定最小级别/禁用 tag，`notifications.webhook` 则可配置多条 HTTP Endpoint，在 `magento_api_watch`、`resource_alert`、`backup_notify`、`monitor daily` 等脚本触发时同步推送 JSON。
- 如遇 Webhook/Telegram 阻塞，可运行 `python3 scripts/notification-drain.py --verbose` 重放 `/var/log/saltgoat/notify-queue` 中积压的通知（支持 `--dest webhook|telegram`、`--dry-run`）；生产环境可通过 `optional.notification-drain` 状态部署 systemd timer 周期性清理，并在队列残留≥阈值（默认 500 条）时自动发送 `saltgoat/monitor/notification_queue` 告警。可通过 Pillar `saltgoat:notifications:drain_max`、`drain_alert_threshold`、`drain_alert_tag`/`drain_alert_site` 定制批量与告警参数。
- 本地/CI 运行通知脚本时，如无 root 权限，可提前设置 `SALTGOAT_ALERT_LOG=/tmp/saltgoat-alerts.log`（或自选路径）；配合新版 `reactor_logger.py` fallback 逻辑，可避免写 `/var/log/saltgoat/alerts.log` 失败并保持日志可读。
- 需要快速模拟 summary/订单/客户/备份等通知时，可执行 `python3 scripts/notification-test.py --scenario summary --site demo`（支持 `order`/`customer`/`backup-mysql`/`backup-restic` 等），自动生成示例 payload 与 tag；配合 `SALTGOAT_NOTIFICATIONS_FILE` 即可在无 Telegram 的环境验证过滤与派发链路。
- `sudo saltgoat monitor report daily --no-telegram` 可生成日报而不推送；默认会写日志并发送 Telegram 摘要
- `sudo saltgoat monitor enable-beacons`：启用 Beacon/Reactors；若缺少 `salt-minion` 会提示并降级。
- `sudo saltgoat schedule enable`：下发 SaltGoat 自身任务（内存、日志清理等），依赖 Salt Schedule（需确保 `salt-minion` 运行）。
- Salt Beacon 触发的 systemd 自愈流程会自动执行 `systemctl restart`，并把成功/失败状态写入 `/var/log/saltgoat/alerts.log`、发送 Telegram，同时重新发布 Salt 事件（便于级联自动化）。
- `modules/monitoring/resource_alert.py` 会在负载过高时自动调节 PHP-FPM 进程池、MySQL `max_connections`、Valkey `maxmemory`，以及 OpenSearch 的缓存占比，把结果写入 `/etc/saltgoat/runtime/*.json` 并触发 autoscale 通知。
- 监控/自愈巡检的完整 SOP 参考 [`docs/monitoring-playbook.md`](docs/monitoring-playbook.md)。

### 自动化脚本 (Automation)
- `sudo saltgoat automation script <create|list|edit|run|delete>`：生成并维护 `/srv/saltgoat/automation/scripts/*.sh`。
- `sudo saltgoat automation job <create|list|enable|disable|run|delete>`：注册 Salt Schedule 任务；若 `salt-minion` 未运行会直接报错，避免静默降级。
- `sudo saltgoat automation logs <list|view|tail|cleanup>`：统一管理任务日志。

### 备份策略
- Restic 快照：`sudo saltgoat magetools backup restic install --site <name> [--repo <path>]` 为单站点创建 systemd 定时器；`run/summary/logs` 子命令可手动触发与巡检。
- Percona XtraBackup：`sudo saltgoat magetools xtrabackup mysql run`；配置详见 [`docs/mysql-backup.md`](docs/mysql-backup.md)。
- 单库导出：`sudo saltgoat magetools xtrabackup mysql dump --database <db> --backup-dir <path>` 会输出体积、写 Salt event，并发 Telegram。
- 所有备份事件都会写入 `/var/log/saltgoat/alerts.log`，便于审计。

### Telegram 通知 & ChatOps
- `optional.salt-beacons` 会自动部署 `/opt/saltgoat-reactor` 辅助脚本，Telegram Bot / Topic 配置由 Pillar (`telegram`, `telegram_topics`) 提供，所有资源告警、备份、服务自愈都会同步到 Telegram。
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

- [`docs/install.md`](docs/install.md)：安装、Pillar、Matomo、Salt 依赖说明。
- [`docs/magento-maintenance.md`](docs/magento-maintenance.md)：维护流程、命令速查、Salt Schedule/Beacon/cron 降级。
- [`docs/magento-permissions.md`](docs/magento-permissions.md)：站点权限策略、修复脚本。
- [`docs/backup-restic.md`](docs/backup-restic.md)：Restic 仓库配置与恢复流程。
- [`docs/mysql-backup.md`](docs/mysql-backup.md)：Percona XtraBackup 安装、巡检与恢复。
- [`docs/secret-management.md`](docs/secret-management.md)：密钥模板、Pillar Secret 工作流与密码更新步骤。
- [`docs/telegram-topics.md`](docs/telegram-topics.md)：Telegram 话题 `chat_id`/`message_thread_id` 对照表及通知分类建议。
- [`docs/ops-tooling.md`](docs/ops-tooling.md)：Varnish 回归脚本、健康面板、Fail2ban Watcher、SaltGoat fun 命令等日常运维工具。
- [`docs/changelog.md`](docs/changelog.md)：版本更新。

---

## 🧪 测试与代码质量

```bash
bash scripts/code-review.sh -a        # shfmt + ShellCheck + docs lint
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

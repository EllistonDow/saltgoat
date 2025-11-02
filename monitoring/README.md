# SaltGoat 监控模块使用指南

本文介绍 `saltgoat monitor` 指令以及可选的 Salt Beacon/Reactor 配置，帮助你在日常运维中快速掌握系统状态、生成报告，并启用事件驱动的自动化处理。

## 1. 模块概览

- **即时巡检命令**：`sudo saltgoat monitor <子命令>` 通过 `salt-call --local` 读取系统、服务、安全等信息，适合临时排查或定期人工检查。
- **监控数据存放**：
  - 临时报表与历史输出：`/var/log/saltgoat/monitor/`
  - 本地配置快照：`/etc/saltgoat/monitor/`
- **事件驱动监控（可选）**：`sudo saltgoat monitor enable-beacons` 会调用自定义 Salt 模块 `saltgoat.enable_beacons`，依据 Pillar 中的 `saltgoat:beacons` 定义下发 `optional.salt-beacons` 与 `optional.salt-reactor` 状态，启用负载/内存/磁盘告警、关键服务自愈、配置变更追踪等自动化流程。

> 提示：若主机未安装 `salt-minion` 或缺少 `salt-run`，脚本会自动降级为纯输出模式，不会留下半套配置。

## 2. 常用巡检指令

```bash
sudo saltgoat monitor install        # 安装 salt-minion 并启用 Salt Beacons/Reactor
sudo saltgoat monitor system         # 显示主机信息、负载、资源与网络概览
sudo saltgoat monitor services       # 检查 Nginx/MySQL/PHP/Valkey/RabbitMQ/OpenSearch 状态与主 PID
sudo saltgoat monitor resources      # 导出 CPU / Memory / I/O 统计与 Top 进程
sudo saltgoat monitor alert resources # 对照阈值检查 CPU/内存/磁盘/服务并推送 Telegram 告警
sudo saltgoat monitor network        # 列出网卡统计、连接数与监听端口
sudo saltgoat monitor logs           # 校验关键日志是否存在并输出最近错误
sudo saltgoat monitor security       # 查看防火墙、登录记录、SSH 连接与可更新套件数量
sudo saltgoat monitor performance    # 对照默认阈值（CPU 80%、内存 85%、根分区 90%）提示异常
sudo saltgoat monitor realtime 120   # 进入 120 秒的全屏实时监控（Ctrl+C 退出）
sudo saltgoat monitor report nightly # 生成综合巡检报告 `/var/log/saltgoat/monitor/nightly.txt`
sudo saltgoat monitor report daily   # 生成每日摘要（写入日志并推 Telegram，可加 --no-telegram）
sudo saltgoat monitor cleanup 14     # 清理 14 天前的旧报告（默认保留 7 天）
sudo saltgoat monitor config         # 输出当前阈值、目录与已启用的子功能
```

所有子命令建议加上 `sudo`，避免因权限不足无法读取系统信息。

## 3. 监控报告与日志

1. 先运行一次报告：`sudo saltgoat monitor report nightly`
2. 报告生成在 `/var/log/saltgoat/monitor/nightly.txt`，可用 `less` 或 `cat` 查看。
3. 通过 `sudo saltgoat monitor cleanup <天数>` 删除旧文件，例如 `cleanup 30` 只保留近 30 天。

### 业务通知与汇总
- **实时订单/新用户告警**：`modules/magetools/magento_api_watch.py` 会读取 `salt/pillar/secret/magento_api.sls` 中的 `base_url` 与 token，监听每个站点的新订单/新注册并写入 `/var/log/saltgoat/alerts.log`、推送 Telegram（tag：`saltgoat/business/order|customer`）。如某站点缺少 token，可在 Pillar 中新增 `auth_mode: admin_login` + `username/password`，脚本会自动换取 Bearer Token。
- **周期汇总报表**：`saltgoat magetools stats --site <name> --period daily|weekly|monthly` 统计区间订单/新用户，默认由 `magento_schedule.stats_jobs` 自动生成 Salt Schedule。支持在 Pillar 中为每个 job 设置 `telegram_thread`、`no_telegram`、`extra_args` 等参数，借助新参数 `--telegram-thread` 将汇总消息导向不同的 Telegram 话题。
- **日志维护**：所有业务告警/汇总都写入 `/var/log/saltgoat/alerts.log`，建议结合 logrotate 或执行 `sudo mv /var/log/saltgoat/alerts.log /var/log/saltgoat/alerts.log.$(date +%Y%m%d).bak && sudo install -m 640 -o root -g root /dev/null /var/log/saltgoat/alerts.log` 定期归档，避免旧误报占据空间。

如需在定时任务中生成报告，可在 systemd timer 或 cron 内调用 `sudo saltgoat monitor report <name>`，并将结果发送到集中日志或备份目录。

### 自定义资源告警阈值
`sudo saltgoat monitor alert resources` 默认在以下阈值触发：
- Load：警告 1m≈1.25×CPU 核心、5m≈1.1×核心、15m≈1.0×核心；致命 1m≈1.5×核心等
- Memory：78% Notice、85% Warning、92% Critical
- Disk：80% Notice、90% Warning、95% Critical
- PHP-FPM：当工作进程使用率 ≥80% 提示 Notice，≥90% Warning，100% 视为 Critical（同时附带当前/上限详情）

可在 Pillar 中覆盖这些值（支持 `saltgoat:monitor:thresholds` 或旧版 `monitor_thresholds` 路径）：
```yaml
saltgoat:
  monitor:
    thresholds:
      load:
        warn_1m: 8
        crit_1m: 12
      memory:
        warning: 82
        critical: 90
      disk:
        warning: 88
        critical: 94
```
重新执行 `sudo saltgoat monitor alert resources` 即可生效。告警消息会包含 `Triggered: Load/Memory/Disk` 以及命中阈值的说明。

## 4. 启用事件驱动监控（Beacons + Reactor）

1. **准备 Pillar**
   - 编辑 `salt/pillar/salt-beacons.sls`（或自定义 Pillar），并确保 `salt/pillar/top.sls` 会将其应用到目标 minion。
   - 示例内容包含：
     - `beacons.service`：轮询关键 systemd 单元，异常时触发自愈。
     - `beacons.load`、`beacons.mem`、`beacons.diskusage`：处理资源告警。
     - `beacons.inotify`：监控 `/etc/nginx`、`/var/www` 等配置变更。
     - `beacons.pkg`：提示可更新的软件包。
     - `reactor.autorestart_services`、`reactor.config_watch`、`reactor.pkg_updates`：定义 reactor 的自动化动作。
2. **下发配置**
   ```bash
   sudo saltgoat monitor install        # 首次执行会自动安装 salt-minion
   # 或者已安装 salt-minion 时
   sudo saltgoat monitor enable-beacons
   sudo saltgoat monitor auto-sites      # 自动生成站点健康检查 Pillar
   ```
   - `install` 会自动安装/启动 `salt-minion`（若尚未存在），默认尝试发行版仓库，必要时回退到 Salt 官方 bootstrap 脚本（GitHub `bootstrap-salt.sh`），然后同步 `optional.salt-beacons` 与 `optional.salt-reactor`。
- 若主机已安装 salt-minion，可直接运行 `enable-beacons`。
- 如果 `install` 提示找不到 `salt-minion` 服务，脚本会尝试重新安装；仍失败时需人工检查 apt/systemd 输出。
- 某些 Salt Onedir 版本在 `salt-call --local beacons.list` 下会返回 `beacons: null`；此时请查看 `systemctl status salt-minion` 与 `/var/log/salt/minion` 确认 Beacon 是否运行。
3. **验证结果**
   ```bash
   sudo saltgoat monitor beacons-status   # 查看当前 Beacons、Schedule、Reactor
   sudo systemctl status salt-minion      # 确认 minion 服务已启动
   sudo tail -f /var/log/salt/minion      # 观察实时事件
   sudo tail -f /var/log/saltgoat/alerts.log
   ```
4. **调整阈值或行为**
   - 修改 Pillar 中的 `interval`、`max`、`services` 或 `monitored_paths` 后，再执行 `enable-beacons` 让配置生效。
   - 默认阈值遵循常用专业建议：1 分钟平均负载上限约为 CPU 核心数的 1.5 倍、5 分钟约为 1.25 倍、15 分钟约为 1.1 倍；内存利用率阈值为 78%，根分区磁盘利用率阈值为 88%。可按业务需求在 Pillar 中覆盖。
   - 若主机兼任 Salt Master，可运行 `sudo salt-run reactor.list` 确认 reactor 已注册。

## 5. Pillar 自定义示例

将以下片段加入 `salt/pillar/salt-beacons.sls` 或站点专属 Pillar：

```yaml
saltgoat:
  beacons:
    mem:
      percent:
        max: 75        # 下调内存告警阈值
      interval: 30
    diskusage:
      interval: 120
      percent:
        /: 85          # 根分区 85% 触发告警
        /var: 80
    service:
      services:
        nginx:
          interval: 20
        php8.3-fpm:
          interval: 20
    reactor:
      autorestart_services:
        services:
          - nginx
          - php8.3-fpm
          - varnish
      resource_alerts:
        log_path: /var/log/saltgoat/alerts.log

saltgoat:
  monitor:
    sites:
      - name: tank-frontend
        url: "https://tank.example.com/"
        timeout: 6
        retries: 2
        expect: 200
        tls_warn_days: 14
        tls_critical_days: 7
        timeout_services:
          - php8.3-fpm
        server_error_services:
          - php8.3-fpm
          - nginx

上述 `monitor.sites` 配置会被 `modules/monitoring/resource_alert.py` 读取：脚本会按时间间隔拉取页面并写入 `alerts.log`；若状态码异常或请求超时，将自动重启对应服务（示例中 502/503/504 会重启 PHP-FPM，系统检测到 Varnish 正在使用时也会一并拉起）。`tls_warn_days` / `tls_critical_days` 会对证书即将过期发出 WARNING/CRITICAL 并写入通知。可通过 `failure_services`/`server_error_services` 字段自定义不同错误场景下的自愈策略。
```

更新 Pillar 后，可用 `sudo salt-call --local pillar.items saltgoat` 验证数据，再执行 `sudo saltgoat monitor enable-beacons` 重新加载。

## 6. 常见问题排查

- **`beacons.list` 返回 `null`**：确认 `salt-minion` 已安装并运行，可通过 `sudo salt-call --local service.status salt-minion` 验证。
- **`salt-run reactor.list` 找不到命令**：说明当前没有 Salt Master，这属于预期行为。若未部署 Master，可忽略该提示。
- **`enable-beacons` 显示 `Permission denied`**：请以 `sudo` 运行，并保证 `/etc/salt/` 与 `/var/log/saltgoat/` 对 root 可写。
- **监控输出缺少某些服务**：不同发行版的服务名可能不同（如 `php8.3-fpm`），可根据实际情况修改 `monitoring/system.sh` 中的 `services` 数组，或在 Pillar 的 `autorestart_services` 列表追加需要跟踪的单元。

## 7. 扩展与集成

- `monitoring/schedule.sh`、`monitoring/memory.sh` 提供额外 CLI 封装，可通过 `sudo saltgoat schedule ...`、`sudo saltgoat memory ...` 使用（详见 `lib/help.sh` 对应条目）。
- 若需将监控结果整合至外部平台，可结合 Restic/S3 备份，或使用 `modules/monitoring/` 内的 `saltgoat monitoring prometheus|grafana` 方案。
- 启用 `optional.salt-beacons` 后，系统服务异常会触发自动重启脚本；脚本会记录 systemd 重启结果（成功/失败/当前状态）、写入 `/var/log/saltgoat/alerts.log`，并推送 Telegram + Salt Event，便于人工复核与二次自动化。

## 8. Telegram ChatOps（实验性）

1. **准备配置**：复制 `salt/pillar/chatops.sls.sample` 为真实 Pillar，设置允许的 `chat_id`、管理员 `approvers`、命令映射（`commands`）。
2. **刷新 Pillar**：`sudo saltgoat pillar refresh` 或 `sudo saltgoat monitor enable-beacons`，系统会在 `/etc/saltgoat/chatops.json` 写入最新配置，同时创建 `/var/lib/saltgoat/chatops/pending` 与 `/var/log/saltgoat/chatops.log`。
3. **使用方式**：
   - 指令格式 `/saltgoat <match...> [参数]`，例如 `/saltgoat maintenance weekly bank`。
   - `requires_approval: true` 的命令会返回一次性 Token，需要管理员发送 `/saltgoat approve <token>` 才会真正执行。
   - 执行结果（返回值、耗时、stdout/stderr 摘要）会 push 回原聊天，同时写入 `chatops.log` 与 Salt 事件。
4. **安全建议**：
   - `allowed_chats` 建议使用私有群组或指定用户，避免被未知账号滥用。
   - 如需允许执行带额外参数的命令，结合 `forward_args: true` 使用，但务必限制 `choices` 或在脚本内进行白名单校验。
   - `approvals.allow_self: false` 可防止提交者自行审批高危操作。

> ChatOps 仍在早期阶段，默认不会启用任何命令。复制模板并逐步扩展即可；所有逻辑均在 `/opt/saltgoat-reactor/telegram_chatops.py`，可按业务需要进一步扩展。

完成以上步骤后，即可同时具备人工巡检效率与事件驱动自动化能力，确保 SaltGoat 主机的服务稳定与告警可追溯性。

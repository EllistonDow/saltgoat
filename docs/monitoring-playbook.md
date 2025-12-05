# SaltGoat Monitoring Playbook

本手册汇总日常巡检、自愈验证与通知校验的操作步骤，建议在新增站点、部署变更或季度复盘时执行。

## 1. 站点健康检查刷新

1. 更新站点 Pillar / runtime JSON 后运行：

   ```bash
   sudo saltgoat monitor auto-sites
   ```

   - 确认输出的 `ADDED_SITES` / `REMOVED_SITES` / `UPDATED` 与预期一致。
   - 观察 `salt/pillar/monitoring.sls` 与 `/etc/saltgoat/runtime/sites.json` 是否同步。
   - 检查 `salt/pillar/telegram-topics.sls`（或对应 secret）是否同步了新增站点的线程映射，`saltgoat magetools schedule auto` / `monitor auto-sites` 不会再自动生成脚本。

2. 需要手工调整话题时，在 Pillar 中追加或修改对应 `saltgoat/<tag>` 的 `chat_id`/`title`（必要时也可直接填入 `topic_id`），然后执行 `sudo saltgoat pillar refresh`；若未提供 `topic_id`，SaltGoat 会在首次发消息时自动创建并缓存线程。

## 2. Salt Schedule 与自愈任务

1. 运行自动安装与校验：

   ```bash
   sudo saltgoat magetools schedule auto
   ```

   - 确认每个站点均显示 `Salt Schedule 任务已就绪`。
   - 同步排查 `salt-call --local schedule.list` 输出是否包含新站点。

2. 如需手工触发资源巡检/自愈，执行：

   ```bash
   sudo python3 modules/monitoring/resource_alert.py
   ```

   - 观察 `/var/log/saltgoat/alerts.log` 是否记录 `Autoscaled ...` 日志。
   - 若触发了扩容动作，按文档收敛 `sudo salt-call --local state.apply core.php`。
   - Swap 占用达到 Critical 时会在同一日志中输出 `Swap critical` 与 `AUTOHEAL` 记录，并依据 Pillar `saltgoat:monitor:swap:autoheal_services` 重启服务；设为 `[]` 可只告警不自愈。
   - 需要快速巡检或手工扩容时，执行 `sudo saltgoat swap status` 查看 si/so 与 swappiness，或运行 `sudo saltgoat swap ensure --min-size 8G --max-size 16G` 自动创建/扩容 `/swapfile`。`swap tune` 可将 `vm.swappiness` 调低至 10~20。

3. OpenSearch 缓存/堆自愈

   - `resource_alert.py` 现在会查询 `http://127.0.0.1:9200/_cluster/stats`，当 JVM heap > 85% 或 < 55% 时动态调节缓存占比，并把结果写入 `/etc/saltgoat/runtime/opensearch-autotune.json`。
   - 每次自动调节都会触发 `state.apply optional.magento-optimization`，从 runtime JSON 合并新的 `indices.memory.index_buffer_size`、`indices.queries.cache.size`、`indices.fielddata.cache.size`，随后由 Salt 负责重启 OpenSearch。
   - 可通过 `sudo cat /etc/saltgoat/runtime/opensearch-autotune.json` 或 Telegram `saltgoat/autoscale/<host>` 话题查看最近动作；命令行输出也会附带 `[AUTOSCALE] Adjusted OpenSearch caches …`。
   - `/etc/opensearch/jvm.options` 由 `optional.opensearch` 自动渲染：默认读取主机物理内存，按 25% 计算并限制在 16~32GB 且不超过总内存的一半；如需固定值，可在 Pillar 设置 `opensearch:jvm_heap_gb`（或 `saltgoat:opensearch:jvm_heap_gb`）覆盖。

4. Webhook / Mattermost 联动

   - `notifications.webhook.endpoints` 中定义的 URL（如 `https://chat.magento.../hooks/...`）会接收到与 Telegram 相同的 JSON payload。调整后请运行任意通知脚本验证，例如：
     ```bash
     sudo python3 modules/lib/backup_notify.py mysql --status success --database demo --site bank --path /tmp/demo.sql.gz --size 10M
     sudo python3 modules/magetools/magento_summary.py --site bank --period daily --no-telegram
     ```
   - 关注 Mattermost（或其它 Webhook 目标）里是否收到 `tag`、`severity`、`plain_message` 等字段；如未收到，检查 `salt/pillar/notifications.sls` 是否 `webhook.enabled: true`、Pillar 已刷新以及目标系统是否允许匿名 POST。
   - 需要发送纯粹的测试消息时，可改用 `python3 scripts/notification-test.py --tag saltgoat/test/ping --severity INFO --text "hello"`，该脚本会使用当前 Pillar/webhook 设置快速推送。
   - 通道异常导致消息被写入 `/var/log/saltgoat/notify-queue/*.json` 时，可用 `python3 scripts/notification-drain.py --verbose` 重放积压记录；`--json-status` 可输出当前队列规模与按 destination 统计的 JSON，方便接入监控。若希望无人值守排空，可启用 `optional.notification-drain` 让 systemd timer 每 2 分钟巡检，且当剩余条目 ≥ `saltgoat:notifications:drain_alert_threshold`（默认 500）时，会自动向 `saltgoat/monitor/notification_queue` 发送 WARNING/CRITICAL 告警，相关 tag/批量参数可通过 `saltgoat:notifications:*` Pillar 调整。
   - 需要在普通用户/CI 环境运行通知脚本时，可设置 `SALTGOAT_ALERT_LOG=/tmp/saltgoat-alerts.log`，并依赖 `reactor_logger.py` 内置的 fallback，避免因为 `/var/log/saltgoat/alerts.log` 权限不足而刷屏告警。`scripts/notification-test.py --scenario summary --site demo` 提供即插即用的示例 payload，便于联调 summary / 订单 / 客户 / 备份链路。

5. 多站点触发的 PHP-FPM 池扩容

   - 每次执行 `saltgoat magetools multisite create|rollback` 时，脚本会自动运行 PHP 池 helper：读取 `/var/www/<site>` store 列表、更新 `magento_optimize:sites.<site>.php_pool.weight`，并将 store code 写入 `store_codes`。
   - 脚本会追加 `[AUTOSCALE]` 记录到 `/var/log/saltgoat/alerts.log`，并发送 `saltgoat/autoscale/<host>` 事件；如需跳过，可在命令中添加 `--no-adjust-php-pool`。
   - 调整成功后会自动执行 `sudo salt-call --local state.apply core.php`，确保 `/etc/php/8.3/fpm/pool.d/` 与 `/etc/saltgoat/runtime/php-fpm-pools.json` 同步；若需要强制特定 weight，可使用 `--php-pool-weight <int>`。

### 2.1 Dropbox 常驻与自愈

1. 创建或更新 `salt/pillar/secret/dropbox.sls`：

   ```yaml
   dropbox:
     enabled: true
     manage_unit: true
     unit_name: dropbox.service
     user: doge
     working_dir: /home/doge
     exec: /usr/bin/dropbox start -i
     restart: always
     beacon_interval: 30
   ```

   - `manage_unit: true` 表示 Salt 会写入 `/etc/systemd/system/dropbox.service` 并设定 `Restart=always`；如已由官方包提供 unit，可改为 `false`。
   - 如需自定义环境变量，可追加 `environment:` 映射，例如 `PATH`、`LANG`。

2. 应用 Pillar 并收敛：

   ```bash
   sudo saltgoat pillar refresh
   sudo saltgoat install all          # 或单独运行 sudo salt-call --local state.apply optional.dropbox
   ```

3. 验证 systemd / Beacon / Reactor：

   - `systemctl status dropbox` 应显示 `active (running)`，`Restart`/`RestartSec` 与 Pillar 一致。
   - `sudo saltgoat monitor beacons-status` 会显示 `service` Beacon 中的 `dropbox`；停止服务 (`sudo systemctl stop dropbox`) 后，几秒内应看到 Reactor 触发自动重启并在 `/var/log/saltgoat/alerts.log` 记录 `[AUTOHEAL] dropbox`。
   - 同时可在 Telegram 话题 `saltgoat/monitor/resources/<host>` 中收到服务重启通知。

## 3. 通知与日志验证

1. 检查 Telegram 推送是否进入正确话题：

   - 新订单/客户：`saltgoat/business/{order,customer}/<site>`.
   - 资源告警/Autoscale：`saltgoat/monitor/resources/<host>`、`saltgoat/autoscale/<host>`.
   - 备份：`saltgoat/backup/{mysql_dump,restic}/<site>`.

2. 如果收不到通知，依次排查：

  - Pillar `telegram` / `telegram_topics` 是否包含 profile 与话题定义（可用 `sudo salt-call --local pillar.get telegram` 与 `pillar.get telegram_topics` 检查，未配置 `topic_id` 时 SaltGoat 会自动创建话题）。
   - `salt/pillar/telegram-topics.sls` 是否已 `saltgoat pillar refresh`。
   - `salt/pillar/notifications.sls` 中是否设置了过滤标签/最小 severity。
   - `modules/lib/notification.py` `should_send` 的 DEBUG 日志可在 `alerts.log` 查看（过滤 `filtered`）。

3. 复核 Salt 事件：

   ```bash
   sudo salt-call event.send 'saltgoat/debug/ping' '{ "msg": "hello" }'
   sudo salt-call event.get event_tag='saltgoat/*' count=5
   ```

   确保事件总线正常工作，避免 Telegram 推送后端无响应。

## 4. 备份作业回顾

1. MySQL：

   ```bash
   sudo saltgoat magetools xtrabackup mysql summary
   sudo journalctl -u saltgoat-mysql-backup.timer -n 20
   ```

2. Restic：

   ```bash
   sudo saltgoat magetools backup restic summary
   sudo journalctl -u saltgoat-restic-<site>.timer -n 20
   ```

   遇到失败时，配套查看 `alerts.log` 与对应 Telegram 话题。
3. Mastodon（若部署了多站点）：

   ```bash
   sudo saltgoat mastodon backup-db <site>
   sudo ls /srv/mastodon/<site>/backups
   ```

   确保 PostgreSQL 备份与媒体目录同步纳入 Restic/S3 兼容对象存储；Telegram 话题中可查到 `saltgoat/backup/mastodon_db/<site>` 的状态。

## 5. 例行巡检节奏

| 项目 | 推荐频率 | 备注 |
|------|----------|------|
| `monitor auto-sites` | 每次新增/下线站点后 | 可加入部署流程 |
| `schedule auto`      | 每次站点模板更新后   | 确保定时任务齐全 |
| `resource_alert.py`  | 周期性收敛验证（周） | 验证 autoscale 逻辑 |
| 通知抽检             | 每月                  | 确保 Telegram/日志都在 |
| 备份 summary         | 每周                  | 检查容量/快照趋势 |

## 6. 常见问题汇总

- **站点未出现在健康检查**：确认 `/var/www/<site>/app/etc/env.php` 是否存在，或 `monitor auto-sites` 是否报错。
- **Telegram 未创建话题**：检查 Bot 是否拥有管理员权限且群组启用论坛模式。
- **重复通知过多**：在 `salt/pillar/notifications.sls` 中调整 `min_severity` 或新增 `disabled_tags`，必要时在脚本层增加节流。
- **Salt Schedule 不执行**：确认 `salt-minion` 正常运行并信任本地 master（或 local 模式），查看 `salt-call schedule.list` 输出。

> 完成巡检后，可使用 `scripts/check-docs.py --fix` 与 `bash scripts/code-review.sh -a` 等工具，保证文档与脚本始终符合团队规范。

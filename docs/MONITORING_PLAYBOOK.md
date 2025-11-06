# SaltGoat Monitoring Playbook

本手册汇总日常巡检、自愈验证与通知校验的操作步骤，建议在新增站点、部署变更或季度复盘时执行。

## 1. 站点健康检查刷新

1. 更新站点 Pillar / runtime JSON 后运行：

   ```bash
   sudo saltgoat monitor auto-sites
   ```

   - 确认输出的 `ADDED_SITES` / `REMOVED_SITES` / `UPDATED` 与预期一致。
   - 观察 `salt/pillar/monitoring.sls` 与 `/etc/saltgoat/runtime/sites.json` 是否同步。
   - 命令末尾自动触发 `scripts/setup-telegram-topics.py`，确认 Telegram 话题列表已更新。

2. 需要手动回顾差异时，可使用：

   ```bash
   sudo python3 scripts/setup-telegram-topics.py --dry-run
   ```

   检查 `to_create` / `to_remove` 项目后再执行正式更新。

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

## 3. 通知与日志验证

1. 检查 Telegram 推送是否进入正确话题：

   - 新订单/客户：`saltgoat/business/{order,customer}/<site>`.
   - 资源告警/Autoscale：`saltgoat/monitor/resources/<host>`、`saltgoat/autoscale/<host>`.
   - 备份：`saltgoat/backup/{mysql_dump,restic}/<site>`.

2. 如果收不到通知，依次排查：

   - `/etc/saltgoat/telegram.json` 是否包含 profile 与话题 ID。
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

   确保 PostgreSQL 备份与媒体目录同步纳入 Restic/MinIO；Telegram 话题中可查到 `saltgoat/backup/mastodon_db/<site>` 的状态。

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

# Telegram 话题配置指南

SaltGoat 目前完全通过 **Pillar** 维护 Telegram Bot 与话题映射，不再生成 `/etc/saltgoat/telegram.json`。所有通知（Restic/XtraBackup、资源告警、Fail2ban、API Watch、`goat_pulse`、`smoke-suite` 等）都会直接读取以下 Pillar：

1. `telegram`：定义 Bot Token、目标 chat_id、可选线程 ID。
2. `telegram_topics`：为常见事件 tag（例如 `saltgoat/backup/restic/<site>`）指定话题 ID。

## 1. 配置 Telegram Bot

在 `salt/pillar/secret/telegram.sls`（或其它受保护的 Pillar）中创建 profile：

```yaml
telegram:
  profiles:
    primary:
      enabled: true
      token: "123456789:ABCDEFG-YourBotToken"
      targets:
        - chat_id: "-1003210805906"   # 超级群/频道 ID
          thread_id: 12345           # 可选：默认话题
      threads:
        saltgoat/doctor: 23456       # 可选：为单个 profile 的特定 tag 指定话题
```

多个群组可通过增加 `profiles.<name>` 或在 `targets` 列表中追加 `chat_id`。

## 2. 维护话题映射

在 `salt/pillar/telegram-topics.sls` 中（或通过 `secret/telegram-topics.sls` include）维护全局映射。结构示例：

```yaml
telegram_topics:
  saltgoat/backup/restic/ambi: 11111
  saltgoat/backup/restic/hawk: 11112
  saltgoat/backup/mysql_dump/ambi: 12221
  saltgoat/monitor/resources/ns521244: 13331
  saltgoat/autoscale/ns521244: 13332
  saltgoat/doctor/ns521244: 14441
```

规则：

- key 为完整 tag 前缀，例如 `saltgoat/backup/restic/<site>`；会匹配子路径（如 `saltgoat/backup/restic/ambi/manual`）。
- value 为 Telegram `message_thread_id`（数字）。
- 可使用通配 `saltgoat/doctor` 为所有 doctor 报告提供统一话题。

## 3. 刷新 Pillar

编辑完成后执行：

```bash
sudo saltgoat pillar refresh
```

通知脚本会在下一次运行时自动读取新配置，无需重启任何服务。

## 4. 验证

- 运行一次 Restic/备份/doctor 命令，确认 Telegram 话题收到消息。
- 查看 `/var/log/saltgoat/alerts.log` 是否包含 `TELEGRAM send_ok`；若出现 `config_missing/config_error`，说明 Pillar 尚未配置或格式有误。

如需完全停用 Telegram，只需在 Pillar 将 `telegram.profiles.*.enabled` 设为 `false` 或移除 profile。其他通知（Webhook、日志）仍会照常运行。

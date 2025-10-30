# SaltGoat Telegram 话题索引

记录 `SaltGoat Notification` 超级群及其话题对应的 `chat_id` / `message_thread_id`，便于通知脚本或 ChatOps 精准推送。

## 群组信息

| 字段 | 数值 | 说明 |
|------|------|------|
| 群组名称 | `SaltGoat Notification` | 已开启论坛模式 |
| 群组 `chat_id` | `-1003210805906` | 所有话题共享同一个 `chat_id` |

## 话题列表

| 话题名称 | `message_thread_id` | 用途建议 |
|-----------|--------------------|-----------|
| General (默认) | _(无)_ | 临时公告 / 未分类通知（未带 `message_thread_id` 即落在 General） |
| New Orders | `2` | Magento 新订单事件 (`saltgoat/business/order`) |
| New Customers | `3` | Magento 新客户事件 (`saltgoat/business/customer`) |
| Xtrabackups | `4` | XtraBackup 安装 / 任务状态、备份完成/失败通知 |
| Restic Backups | `5` | Restic 备份结果、仓库检查、告警 |

> 获取方式：
> ```bash
> curl -s "https://api.telegram.org/bot<token>/getUpdates" | jq
> ```
> 其中 `message_thread_id` 字段即为话题 ID。

## 事件分类建议

| SaltGoat 事件 | 推送话题 | 说明 |
|---------------|----------|------|
| `saltgoat/business/order` | New Orders (`thread_id=2`) | 只关注新增订单，避免刷屏时可在 watcher 中调整阈值/合并消息 |
| `saltgoat/business/customer` | New Customers (`thread_id=3`) | 新会员注册、激活状态变化 |
| `saltgoat/backup/xtrabackup/*` | Xtrabackups (`thread_id=4`) | XtraBackup 运行成功/失败、定时器状态 |
| `saltgoat/backup/restic/*` | Restic Backups (`thread_id=5`) | Restic 任务结果、仓库健康、锁文件告警 |
| `saltgoat/monitor/resources`、`saltgoat/monitor/daily` | General | 资源告警、每日摘要，供全员快速查看 |
| 其它（密码同步、部署流程） | General 或按需新建话题 | 可继续扩展如 `Deployments`、`Security Alerts` 等 |

## Pillar 配置示例

在 `salt/pillar/salt-beacons.sls` 中的 `telegram_bot_msg` 段落追加 `topics` 映射，Salt 会自动生成包含话题信息的 `/etc/saltgoat/telegram.json`：

```yaml
saltgoat:
  beacons:
    telegram_bot_msg:
      - token: "{{ token }}"
      - chat_id: -1003210805906
      - name: primary
      - topics:
          saltgoat/business/order: 2
          saltgoat/business/customer: 3
          saltgoat/backup/xtrabackup: 4
          saltgoat/backup/restic: 5
```

应用 Pillar (`saltgoat pillar refresh`) 后，通知脚本会根据事件标签自动选择对应话题，无需额外参数。

## 后续工作

1. **模板扩展**：更新 `telegram_config.json.jinja` 与 `reactor_common.broadcast_telegram`，使每个 profile 的 target 支持 `message_thread_id`（如 `{"chat_id": -100..., "thread_id": 2}`）。
2. **脚本适配**：
   - `modules/magetools/magento_api_watch.py` 发送订单/客户事件时携带对应 `thread_id`。
   - 备份 / 资源告警脚本根据事件类型选用适当话题。
3. **Pillar 配置**：在 `salt/pillar/chatops.sls` 或新的通知配置中维护话题映射，方便环境迁移时统一管理。

完成以上改造后，所有通知即可根据事件类型自动路由到指定话题，实现 Telegram 群内的可视化分类。

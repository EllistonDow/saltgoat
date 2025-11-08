# Restic 备份模块使用手册

SaltGoat 使用 [Restic](https://restic.net/) 构建文件级快照，支持本地目录、Dropbox 挂载以及 S3/Minio 等远端仓库。`sudo saltgoat magetools backup restic` 模块提供站点级的安装、巡检与恢复命令，同时保留 Salt 状态 `optional.backup-restic` 作为集中化部署的选项。

---

## 0. 功能概览

- **按站点独立管理**：`install --site <name>` 会为站点生成独立的 env/include/exclude 文件、systemd service/timer 以及 `/etc/restic/sites.d/<site>.env` 元数据。
- **自动管理密钥**：若未提供密码，CLI 会生成随机密码并写入 `salt/pillar/secret/auto.sls` 下的 `secrets.restic_sites.<site>.password`，不会进入版本库。
- **默认权限处理**：根据仓库路径自动选择 `ProtectHome`、`RepoOwner` 与 `service_user`，确保 `/home/<user>/Dropbox/...` 等路径可写。
- **事件通知**：手动备份成功/失败会发送 Salt 事件 `saltgoat/backup/restic/(success|failure)`，配合现有 Telegram Reactor 可收到告警。
- **Salt Schedule 兼容**：若机器未安装 `salt-minion`，systemd timer 会继续生效；如需集中管理，可改用 Salt 状态。

---

## 1. 前置准备

### 1.1 Pillar/Secret 目录

1. 复制并填写密钥模板（不会加入版本控制）：
   ```bash
   cp salt/pillar/secret/restic.sls.example salt/pillar/secret/restic.sls   # 可选：集中管理共享仓库
   cp salt/pillar/secret/auth.sls.example   salt/pillar/secret/auth.sls     # 其它密钥同理
   ```
   - 若只使用 CLI 自动生成密码，可跳过 `restic.sls`，脚本会写入 `salt/pillar/secret/auto.sls`。
   - 建议在填写后执行一次 `sudo saltgoat pillar refresh` 验证语法。
   - 多站点示例（复制自 `.example`）：
     ```yaml
     secrets:
       restic:
         repo: "/var/backups/restic/repos/default"
         password: "ChangeMeRestic!"
         service_user: "root"
         repo_owner: "root"
         paths:
           - /var/www/example
         tags:
           - example
           - magento
       restic_sites:
         bank:
           repo: "/home/doge/Dropbox/bank/restic-backups"
           password: "ChangeMeBank!"
           repo_owner: "doge"
           paths:
             - /var/www/bank
             - /var/log/nginx/bank
           tags:
             - bank
             - magento
         tank:
           repo: "/home/doge/Dropbox/tank/restic-backups"
           password: "ChangeMeTank!"
           repo_owner: "doge"
           paths:
             - /var/www/tank
           tags:
             - tank
             - magento
     ```

2. （可选）复制 Pillar 示例便于批量管理：
   ```bash
   cp salt/pillar/backup-restic.sls.sample salt/pillar/backup-restic.sls
   ```
   该文件支持从 `pillar['secrets']` 读取仓库地址/凭据，适合统一配置所有主机。

### 1.2 检查 Restic 软件包

`install` 子命令会自动安装 `restic`。如果机器无法访问仓库，可提前执行：
```bash
sudo apt update
sudo apt install -y restic
```

---

## 2. 快速安装（每个站点执行一次）

```bash
sudo saltgoat magetools backup restic install \
  --site bank \
  --repo /home/doge/Dropbox/bank/restic-backups \
  --paths "/var/www/bank var/log/nginx/bank" \
  --repo-owner doge
```

该命令会：

1. 安装 `restic`（如未安装）。
2. 推导站点代号 `bank` → `bank`，并在 `/etc/restic/` 下生成：
   - `bank.env`：仓库地址、密码、标签、保留策略；
   - `bank.include` / `bank.exclude`：待备份路径与排除规则；
   - `sites.d/bank.env`：供 `summary` 命令读取的元数据。
3. 如果 Pillar/secret 中不存在密码，会生成随机密码写入 `secrets.restic_sites.bank.password`。
4. 创建 systemd unit：
   - `saltgoat-restic-bank.service`
   - `saltgoat-restic-bank.timer`（默认 `OnCalendar=daily`，可通过 `--timer` 与 `--random-delay` 调整）。
5. 根据仓库路径自动选择属主与 `ProtectHome` 策略，确保 Dropbox 等路径具备写权限。
6. 首次执行一次备份；如失败会提示使用 `run --site bank` 手动调试。

不带 `--repo` 时遵循以下默认：
- 存在 `~/Dropbox` → `/home/<user>/Dropbox/<site>/restic-backups`
- 否则 → `/var/backups/restic/<site>`

常用可选项：
- `--paths` 多次传入或使用空格/逗号分隔；
- `--tag` 附加 Restic 标签；
- `--service-user` 指定执行备份的系统用户（默认 root）；
- `--repo-owner` 设置仓库属主，备份完成后会自动 `chown`。

---

## 3. CLI 快速参考

| 命令 | 说明 |
|------|------|
| `install --site <name> [...]` | 创建/更新站点配置，生成 env/include/exclude，注册 systemd timer；再次运行可调整参数。 |
| `run [--site <name>] [--paths ...] [--repo ...]` | 手动执行备份。仅传 `--site` 时复用站点配置；追加 `--paths/--repo/--password-file` 可执行一次性备份。 |
| `status [--site <name>]` | 查看指定站点或所有站点的 systemd 状态。 |
| `summary` | 读取 `/etc/restic/sites.d/*.env`，输出快照数量、最后备份时间、容量与服务状态。 |
| `logs --site <name> [--lines N]` | 查看 systemd 日志。 |
| `snapshots --site <name>` | 调用 Restic 列出快照。 |
| `check --site <name>` | `restic check --read-data-subset=1/5`。 |
| `forget --site <name> [restic args]` | 手动执行 `restic forget`（默认追加 `--prune`）。 |
| `exec --site <name> <subcommand>` | 直接传递任意 Restic 子命令，例如 `restore`、`stats`、`mount`。 |

### 3.1 定时器与增量备份

- `install` 会自动启用 `saltgoat-restic-<site>.timer`（默认 `OnCalendar=daily`），因此**无需额外写 cron**。Restic 的快照天然支持增量存储，后续运行只会上传变化的块。
- 查看排程：
  ```bash
  sudo systemctl list-timers 'saltgoat-restic-*'
  sudo saltgoat magetools backup restic status --site bank   # 查看单站点
  ```
- 调整频率只需重新执行安装命令并传入新的表达式：
  ```bash
  sudo saltgoat magetools backup restic install \
    --site bank \
    --timer 'hourly' \
    --random-delay 5m
  ```
  亦可使用完整的 `OnCalendar` 语法，例如 `--timer 'Mon..Sun 03:00'`。
- 若想临时取消排程，可运行 `sudo systemctl disable --now saltgoat-restic-<site>.timer`，稍后再通过 `install` 恢复。

### 3.2 通知与事件

- 无论是 systemd timer 还是手动 `run`，都会发送 `saltgoat/backup/restic/(success|failure)` 事件；配合默认的 `reactor/backup_notification.sls` 会在 `/var/log/saltgoat/alerts.log` 中追加 `[BACKUP]` 记录。
- 为了即时推送，CLI 与定时服务还会检查 `/etc/saltgoat/telegram.json`，使用 `/opt/saltgoat-reactor/reactor_common.py` 直接广播 Telegram 消息（同时保留 Salt 事件，便于其它自动化继续消费）。
- 快速自检：
  ```bash
  sudo tail -n 20 /var/log/saltgoat/alerts.log    # 确认出现 [BACKUP] 与 [TELEGRAM] 行
  sudo journalctl -u saltgoat-restic-<site>.service -n 50
  ```
- 如果日志里看到 `TELEGRAM ... send_failed`，通常与网络、token 或 chat_id 有关；`config_missing/config_empty` 则表示 `/etc/saltgoat/telegram.json` 尚未配置，按模板补齐即可。

---

## 4. 日常巡检

```bash
# 汇总所有站点
sudo saltgoat magetools backup restic summary

# 查看单个站点状态
sudo saltgoat magetools backup restic status --site bank

# 查看最近 200 行日志
sudo saltgoat magetools backup restic logs --site bank --lines 200

# 手动执行一次备份并追加标签
sudo saltgoat magetools backup restic run --site bank --tag manual-test
```

`summary` 输出示例：
```
站点         快照数 最后备份           容量     服务状态             最后执行
--------------------------------------------------------------------------------------
bank         12     2024-10-29 05:47  1.2G     active/finished(0)   2024-10-29 05:47:12
```

- `快照数` / `最后备份` / `容量` 来自 `restic snapshots` 与 `restic stats --json latest`；
- `服务状态` 组合了 `systemctl show` 的 `ActiveState/SubState` 与 `ExecMainStatus`；
- `最后执行` 读取 `journalctl` 的时间戳。

若 `summary` 报错，先确认 `/etc/restic/sites.d` 下是否存在 `.env`，或该站点是否已成功安装。

---

## 5. 结合 Pillar / Salt 状态

虽然 CLI 能独立管理站点，仍可通过 Pillar 与 Salt 状态批量部署：

1. 编辑 `salt/pillar/backup-restic.sls`（示例来自 `.sample`）：
   ```yaml
   {% set secrets = pillar.get('secrets', {}) %}
   {% set restic = secrets.get('restic', {}) %}

   backup:
     restic:
       enabled: true
       repo: "{{ restic.get('repo', '/var/backups/restic/repos/default') }}"
       password: "{{ restic.get('password', 'ChangeMeRestic!') }}"
       paths:
         - /var/www/example
       tags:
         - example
         - magento
       timer: daily
       randomized_delay: 15m
       service_user: "{{ restic.get('service_user', 'root') }}"
       repo_owner: "{{ restic.get('repo_owner', 'root') }}"
   ```
2. 在 `salt/pillar/top.sls` include `backup-restic`，执行 `sudo saltgoat pillar refresh`。
3. 运行 `sudo salt-call state.apply optional.backup-restic`（或通过 `sudo saltgoat install optional --include backup-restic`）即可生成同名 systemd 单元。该方案适合希望统一管理所有主机、且无需站点维度拆分的场景。

> 如需切换到 CLI 管理，可保留 Pillar 作为默认模板，再对特定站点运行 `install --site` 覆盖。

---

## 6. 恢复与演练

1. 列出快照：
   ```bash
   sudo saltgoat magetools backup restic snapshots --site bank
   ```
2. 恢复最新快照到临时目录：
   ```bash
   sudo saltgoat magetools backup restic exec --site bank restore latest --target /tmp/restic-restore
   ```
3. 指定时间点恢复：
   ```bash
   sudo saltgoat magetools backup restic exec --site bank restore 2024-10-27T05:00:00 --target /srv/restore-bank
   ```
   - 只恢复部分目录/文件时，可追加 `--include /var/www/bank/app/etc` 或 `--exclude` 参数。
   - 恢复到不同机器时，只需拷贝 `/etc/restic/<site>.env` 与仓库密码，随后照此命令在目标主机执行。
4. 挂载快照用于浏览：
   ```bash
   sudo saltgoat magetools backup restic exec --site bank mount /mnt/restic-bank
   ```
   完成后使用 `fusermount -u /mnt/restic-bank` 卸载。

定期演练建议：
- 每季度抽样恢复一个站点到临时目录，确认文件完整；
- 结合 `restic check --read-data-subset=1/5` 检查仓库一致性；
- 若仓库位于 Dropbox/外接盘，确保定期同步/挂载状态良好。

---

## 7. 常见问题

- **提示未找到环境文件**：尚未执行 `install --site` 或站点名称拼写错误。使用 `summary` 查看已配置的站点代号。
- **备份失败，日志显示权限被拒绝**：确认仓库路径属主、`--repo-owner` 与 systemd 服务用户一致；必要时重新运行安装命令。
- **多站点备份到同一仓库**：分别运行 `install --site`，将 `--repo` 指向同一目录并使用不同 `--tag` 区分。
- **需要与 mysqldump/XtraBackup 联动**：在 `salt/pillar/magento-schedule.sls` 定义 `mysql_dump_jobs`，结合 Telegram Reactor 可获得通知，详见 [`docs/mysql-backup.md`](MYSQL_BACKUP.md#salt-schedule-逻辑导出)。
- **恢复到其它路径**：`restore` 命令的 `--target` 可以指定任意空目录；若目标目录不为空，可先使用 `--path` 或 `--include` 过滤出需要的文件，再手动迁移。

如需进一步的密钥/密码管理流程，请参考 [`docs/secret-management.md`](SECRET_MANAGEMENT.md)。

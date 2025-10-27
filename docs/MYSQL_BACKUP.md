# MySQL / Percona 备份指南

SaltGoat 提供 `optional.mysql-backup` 可选模块，基于 [Percona XtraBackup 8.4](https://www.percona.com/software/mysql-database/percona-xtrabackup)，支持在线热备、增量去重与定时任务。核心特点：

- 通过 `mysqld` 热备份，不阻塞读写；
- 自动创建备份专用 MySQL 账号，避免使用 root；
- 以日期目录存储（默认 `/var/backups/mysql/xtrabackup/YYYYMMDD_HHMMSS`），支持定期清理；
- systemd timer 管理周期执行，可与 Restic 二次归档整合；
- CLI 命令统一触发安装、运行、日志与巡检。

> CLI 入口：`saltgoat magetools xtrabackup mysql <subcommand>`。旧命令 `saltgoat magetools backup mysql ...` 仍可使用，但会提示迁移。

-------------------------------------------------------------------------------

## 1. 快速安装与首次备份

1. 确认 Pillar 中存在 `mysql_password`（系统初始即生成）；仓库已附带 `salt/pillar/mysql-backup.sls` 示例，可直接复制该文件并将其中的 `ChangeMeRoot!`/`ChangeMeBackup!` 改成实际密码。
2. 写入 Pillar 示例（默认路径 `/var/backups/mysql/xtrabackup`，备份账号 `backup`，项目已提供 `salt/pillar/mysql-backup.sls`，记得将其加入 `salt/pillar/top.sls`）：

   ```yaml
   mysql_backup:
     enabled: true
     backup_dir: /var/backups/mysql/xtrabackup
     mysql_user: backup
     mysql_password: "StrongBackUpP@ss"
     service_user: root
     repo_owner: doge           # 备份完成后赋权给哪位用户，常见为 Dropbox 同步用户
     timer: daily
     randomized_delay: 20m
     retention_days: 7          # 超过 N 天的目录自动清理
     extra_args: "--parallel=4 --compress"
   ```

3. 执行安装（需 root 权限，仅需运行一次即可创建账号、脚本与 timer）：

  ```bash
  sudo saltgoat magetools xtrabackup mysql install
  ```

   安装过程会：
   - 安装 `percona-release` 并自动启用 `pxb-84-lts` 官方仓库；
   - 安装 `percona-xtrabackup-84`；
   - 创建/更新备份账号并授予 `BACKUP_ADMIN`、`REPLICATION CLIENT`、`LOCK TABLES`、`PROCESS`、`RELOAD` 以及 `performance_schema.*` 的只读权限；
   - 写入 `/etc/mysql/mysql-backup.env` 环境变量；
   - 生成 `/usr/local/bin/saltgoat-mysql-backup` 备份脚本；
   - 部署 `saltgoat-mysql-backup.service` / `.timer` 并执行一次测试备份；
   - 记录元数据 `/etc/mysql/backup.d/mysql.env`，供 `summary` 命令使用。

-------------------------------------------------------------------------------

## 2. 日常运维命令

```bash
sudo saltgoat magetools xtrabackup mysql run          # 立即触发一次热备
sudo saltgoat magetools xtrabackup mysql status       # 查看 service / timer 状态
sudo saltgoat magetools xtrabackup mysql logs 150     # 查看最近 150 行备份日志
sudo saltgoat magetools xtrabackup mysql summary      # 输出备份目录、容量、最近运行状态
```

典型输出（`summary`）：

```
标识         目录                             最近备份              容量      服务状态             最近执行
--------------------------------------------------------------------------------------------------------------
mysql        /var/backups/mysql/xtrabackup    2025-10-27 01:00      2.1G      inactive/dead(0)    2025-10-27 01:00:03
```

`inactive/dead(0)` 表示上一次 systemd 执行正常结束（返回码 0）；若看到 `(1)` 或 `(failed)`，请使用 `logs` 查看详细报错。

-------------------------------------------------------------------------------

## 3. 备份文件结构与保留策略

- 备份目录按时间戳创建，例如 `/var/backups/mysql/xtrabackup/20251027_010000`；
- 当 `retention_days` 设置为 7 时，定时脚本会自动删除 7 天前的目录；
- 若启用 `--compress`，Percona XtraBackup 会在目标目录中生成 `.qp` 压缩文件，可节省空间；
- 如需把备份目录继续交给 Restic/Dropbox，请在 Restic `paths` 中添加 `/var/backups/mysql/xtrabackup`。

-------------------------------------------------------------------------------

## 4. 恢复流程

> 以下步骤建议在测试环境反复演练，确认流程熟悉后再用于生产。

1. **准备阶段（Apply redo logs）**

   ```bash
   sudo xtrabackup --prepare --target-dir=/var/backups/mysql/xtrabackup/20251027_010000
   ```

2. **停止 MySQL 并清空 datadir**（恢复前必须停止服务并备份当前数据）：

   ```bash
   sudo systemctl stop mysql
   sudo mv /var/lib/mysql /var/lib/mysql.bak.$(date +%s)
   sudo mkdir -p /var/lib/mysql
   sudo chown mysql:mysql /var/lib/mysql
   ```

3. **回放备份数据**

   ```bash
   sudo xtrabackup --copy-back --target-dir=/var/backups/mysql/xtrabackup/20251027_010000
   sudo chown -R mysql:mysql /var/lib/mysql
   ```

4. **启动 MySQL 并验证**

   ```bash
   sudo systemctl start mysql
   sudo mysql -e "SHOW DATABASES;"
   ```

5. 确认无误后，可删除旧的 `/var/lib/mysql.bak.*` 和已恢复的备份目录。

> **提示**：若需要跨服务器恢复，可将备份目录打包或交给 Restic，还原时使用 `--copy-back` 即可。

-------------------------------------------------------------------------------

## 5. Pillar 配置参考

```yaml
mysql_backup:
  enabled: true
  backup_dir: /var/backups/mysql/xtrabackup
  mysql_user: backup
  mysql_password: "StrongBackUpP@ss"
  connection_user: root
  connection_password: "{{ pillar['mysql_password'] }}"
  service_user: root
  repo_owner: doge
  timer: daily
  randomized_delay: 20m
  retention_days: 7
  prepare_backup: false
  compress: true
  extra_args: "--parallel=4"
```

常见参数说明：

| 参数 | 作用 |
|------|------|
| `backup_dir` | 备份输出目录（按日期创建子目录） |
| `mysql_user` / `mysql_password` | 备份专用 MySQL 账号，自动创建 |
| `connection_*` | 执行 `CREATE USER`/`GRANT` 所用的权限账号，默认读取 `pillar['mysql_password']` |
| `service_user` | systemd 服务运行用户，默认 root（可改为拥有备份目录权限的账号） |
| `repo_owner` | 备份完成后给目录做 `chown -R` 的用户，便于 Dropbox/Restic 同步 |
| `timer` / `randomized_delay` | systemd 定时计划，可填写 `hourly` / `weekly` 或 Cron 表达式 |
| `retention_days` | 清理旧备份的天数；设为 `0` 表示不自动删除 |
| `prepare_backup` | 是否在备份完成后立即执行 `xtrabackup --prepare` |
| `compress` | 是否启用 XtraBackup 内置压缩 |
| `extra_args` | 传递给 `xtrabackup` 的附加参数，如 `--parallel=4` |

-------------------------------------------------------------------------------

## 6. 常见问题（FAQ）

| 问题 | 解决方法 |
|------|----------|
| `xtrabackup` 命令不存在 | 确认已安装 `percona-xtrabackup-84`，必要时运行 `apt-cache policy percona-xtrabackup-84` |
| 备份失败 `access denied` | 检查 `mysql_backup` Pillar 中的 `mysql_password` 是否与 `mysql.user` 中一致；必要时重新生成并 `install` | 
| systemd 服务一直失败 | 查看 `saltgoat magetools xtrabackup mysql logs`，常见原因是目录权限或 MySQL 账号缺失 |
| 如何归档/远程存储 | 可将备份输出目录加入 Restic `paths`，或编写脚本上传至 S3/OSS |
| 如何执行增量备份 | 可在 `extra_args` 中添加 `--incremental-basedir=/path/to/full` + `timer` 定制；目前示例默认为全量 |

如需整合 Restic、增量策略或备份校验，可在 `modules/magetools/mysql-backup.sh` 基础上继续扩展。欢迎在实际场景验证后更新文档。

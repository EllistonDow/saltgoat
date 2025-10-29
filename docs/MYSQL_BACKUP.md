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
     mysql_password: "{{ salt['pillar.get']('secrets.mysql_backup_password', 'ChangeMeBackup!') }}"
     service_user: root
     repo_owner: deploy         # 备份完成后赋权给哪位用户，常见为 Dropbox 同步用户
     timer: daily
     randomized_delay: 20m
     retention_days: 7          # 超过 N 天的目录自动清理
     extra_args: "--parallel=4 --compress"
   ```

   > **自定义备份路径**
   >
   > 1. 编辑 `salt/pillar/mysql-backup.sls`（如不存在请新建），写入：
   >    ```yaml
   >    mysql_backup:
   >      enabled: true
   >      backup_dir: /home/doge/Dropbox/bank/databases
   >      repo_owner: doge
   >      service_user: doge
   >      mysql_user: backup
   >      mysql_password: "{{ salt['pillar.get']('mysql_backup_password') }}"
   >      connection_password: "{{ salt['pillar.get']('mysql_password') }}"
   >    ```
   >    `mysql_backup_password` 建议单独写在 `salt/pillar/secret/mysql-backup.sls` 之类的私有 Pillar 文件，再在 `top.sls` 中按需 include，避免把真实密码提交到仓库。若目录位于 Dropbox 等用户空间，请确保 `service_user`/`repo_owner` 与该目录的属主一致，使 systemd 任务和备份文件都拥有写权限。
   > 2. 执行 `saltgoat pillar refresh` 同步最新 Pillar。
   > 3. 重新运行 `sudo saltgoat magetools xtrabackup mysql install`，Salt 状态会依照新的路径创建目录、刷新 `/etc/mysql/mysql-backup.env` 并重启定时器。
   > 4. 之后无论是定时器还是 `saltgoat magetools xtrabackup mysql run` 都会使用新的 `backup_dir`。如需让逻辑导出 (`xtrabackup mysql dump`) 保存到其他位置，可在命令里追加 `--backup-dir /path/to/dir`。

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

## 3. 单站点逻辑备份（mysqldump）

`xtrabackup mysql dump` 支持对单个业务数据库做逻辑导出，默认压缩为 `.sql.gz` 并放到 `/var/backups/mysql/dumps`。常见用法如下：

```bash
# 备份 bankmage 数据库到 Dropbox，并指定备份文件属主
sudo saltgoat magetools xtrabackup mysql dump \
    --database bankmage \
    --backup-dir /home/doge/Dropbox/bank/databases \
    --repo-owner doge

# 导出为未压缩的 .sql（适合临时查看）
sudo saltgoat magetools xtrabackup mysql dump \
    --database staging_db \
    --backup-dir /tmp/mysql-dumps \
    --no-compress
```

参数说明：

| 参数 | 作用 |
|------|------|
| `--database`（必填） | 要导出的数据库名称 |
| `--backup-dir`       | 备份输出目录，默认 `/var/backups/mysql/dumps` |
| `--repo-owner`       | 备份文件的属主，便于 Dropbox/Restic 同步；未指定时沿用 `mysql-backup.env` 的 `MYSQL_BACKUP_REPO_OWNER` |
| `--no-compress`      | 关闭 gzip 压缩，输出原始 `.sql` |

脚本会自动读取 `/etc/mysql/mysql-backup.env` 中的备份账号信息，使用 `mysqldump --single-transaction --routines --events --set-gtid-purged=OFF` 进行导出。完成后会将文件权限设为 `640` 并执行 `chown`，便于后续同步或归档。

恢复 `.sql.gz` 时，可按以下步骤操作：

1. 如果目标库不存在，可执行：
   ```bash
   sudo saltgoat magetools mysql create \n       --database bankmage \n       --user bank \n       --password 'ChangeMe!' \n       --no-super
   ```
2. 导入备份：
   ```bash
   gunzip -c /path/to/bankmage_YYYYMMDD.sql.gz | sudo mysql bankmage
   ```
   若是未压缩 `.sql`，直接 `sudo mysql bankmage < dump.sql`。
3. 验证数据：
   ```bash
   sudo mysql -e "SHOW TABLES FROM bankmage;"
   ```

如需为新站点准备数据库和账户，可执行 `sudo saltgoat magetools mysql create --database <name> --user <user> --password '<pass>'`，脚本会自动授予 ALL + PROCESS/SUPER 权限（可用 `--no-super` 关闭）并保持幂等。

-------------------------------------------------------------------------------

## 4. 备份文件结构与保留策略

- 备份目录按时间戳创建，例如 `/var/backups/mysql/xtrabackup/20251027_010000`；
- 当 `retention_days` 设置为 7 时，定时脚本会自动删除 7 天前的目录；
- 若启用 `--compress`，Percona XtraBackup 会在目标目录中生成 `.qp` 压缩文件，可节省空间；
- 如需把备份目录继续交给 Restic/Dropbox，请在 Restic `paths` 中添加 `/var/backups/mysql/xtrabackup`。

-------------------------------------------------------------------------------

## 5. 恢复流程

> 以下步骤建议在测试环境反复演练，确认流程熟悉后再用于生产。

1. **准备阶段（Apply redo logs）**

   ```bash
   sudo xtrabackup --prepare --target-dir=/var/backups/mysql/xtrabackup/20251027_010000
   ```

2. **停止 MySQL 并清空 datadir**（恢复前必须停止服务并备份当前数据）：
如果使用 `dump` 导出的逻辑备份，则无需停机，可直接在目标实例执行 `gunzip -c dump.sql.gz | sudo mysql <dbname>`。物理备份（XtraBackup）适合整库回滚或灾难恢复，迁移单站点时建议使用逻辑备份流程。


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

## 6. Pillar 配置参考

```yaml
mysql_backup:
  enabled: true
  backup_dir: /var/backups/mysql/xtrabackup
  mysql_user: backup
  mysql_password: "{{ salt['pillar.get']('secrets.mysql_backup_password', 'ChangeMeBackup!') }}"
  connection_user: root
  connection_password: "{{ salt['pillar.get']('secrets.mysql_password', 'ChangeMeRoot!') }}"
  service_user: root
  repo_owner: deploy
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

## 7. 常见问题（FAQ）

| 问题 | 解决方法 |
|------|----------|
| `xtrabackup` 命令不存在 | 确认已安装 `percona-xtrabackup-84`，必要时运行 `apt-cache policy percona-xtrabackup-84` |
| 备份失败 `access denied` | 检查 `mysql_backup` Pillar 中的 `mysql_password` 是否与 `mysql.user` 中一致；必要时重新生成并 `install` | 
| systemd 服务一直失败 | 查看 `saltgoat magetools xtrabackup mysql logs`，常见原因是目录权限或 MySQL 账号缺失 |
| 如何归档/远程存储 | 可将备份输出目录加入 Restic `paths`，或编写脚本上传至 S3/OSS |
| 如何执行增量备份 | 可在 `extra_args` 中添加 `--incremental-basedir=/path/to/full` + `timer` 定制；目前示例默认为全量 |

如需整合 Restic、增量策略或备份校验，可在 `modules/magetools/mysql-backup.sh` 基础上继续扩展。欢迎在实际场景验证后更新文档。

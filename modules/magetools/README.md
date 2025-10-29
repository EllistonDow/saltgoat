# SaltGoat Magento工具集

## 概述

Magento工具集为SaltGoat提供了专门的Magento开发和维护工具，包括CLI工具安装、缓存管理、索引管理等功能。

## 功能特性

### 📦 工具安装
- **n98-magerun2** - Magento 2 CLI工具
- **phpunit** - PHP单元测试框架
- **xdebug** - Xdebug调试工具

### 🔧 维护管理
- **维护模式控制** - 启用/禁用维护模式
- **日常维护** - 缓存清理、索引重建、会话/日志清理
- **每周维护** - 备份、日志轮换、Valkey 刷新（可选）、性能检查
- **每月维护** - 完整部署流程（维护模式→清理→升级→编译→部署→索引→禁用维护→清理缓存）
- **健康检查** - Magento状态、数据库连接、缓存状态、索引状态

### ⏰ 定时任务管理
- **Salt Schedule** - 使用 Salt 原生状态管理（推荐）
- **系统 Cron** - 使用系统原生 crontab 管理
- **智能检测** - 自动检测数据库架构更新并执行相应操作

### 🗂️ 缓存管理
- 清理所有缓存
- 检查缓存状态
- 预热缓存
- Magento Valkey 配置与检测（Salt 原生）

### 📊 索引管理
- 重建所有索引
- 检查索引状态

### 🚀 部署管理
- 部署到生产环境

### 💾 备份恢复
- 创建完整备份
- 从备份恢复

### 📈 性能分析
- 分析性能状况

### 🔒 安全扫描
- 扫描安全问题

### 🔄 更新管理
- 更新Magento

## 使用方法

### 基本语法
```bash
saltgoat magetools <command> [options]
```

### 工具安装
```bash
# 安装N98 Magerun2
saltgoat magetools install n98-magerun2

# 安装PHPUnit
saltgoat magetools install phpunit

# 安装Xdebug
saltgoat magetools install xdebug
```

### Valkey 管理
```bash
# 使用 Salt 原生流程配置 Valkey
saltgoat magetools valkey-setup bank
saltgoat magetools valkey-setup bank --reuse-existing --cache-db 13 --page-db 14 --session-db 15

# 检测当前 Valkey 配置是否生效
saltgoat magetools valkey-check bank --expected-owner www-data --expected-perms 755

# 兼容旧流程：使用 Shell 脚本重新分配数据库
saltgoat magetools valkey-renew bank
```

### RabbitMQ（Salt 原生）
```bash
# 使用 Pillar 中的 rabbitmq_password 作为默认
sudo saltgoat magetools rabbitmq-salt smart bank

# 如需覆盖参数，可显式传参
sudo saltgoat magetools rabbitmq-salt all bank \
  --threads 3 \
  --amqp-host 127.0.0.1 --amqp-port 5672 \
  --amqp-user bank --amqp-password 'StrongP@ss' --amqp-vhost '/bank' \
  --service-user www-data --php-memory 2G

# 仅检测，不会修改
sudo saltgoat magetools rabbitmq-salt check bank --mode smart --threads 1

# 列出站点或全局的消费者 unit（含旧版/模板）
sudo saltgoat magetools rabbitmq-salt list bank
sudo saltgoat magetools rabbitmq-salt list all

# 清理 systemd unit，并从 env.php 中移除 queue 配置
sudo saltgoat magetools rabbitmq-salt remove bank

# 若误建了 site=tank，可直接清理
sudo saltgoat magetools rabbitmq-salt remove tank

- `smart` 模式默认生成 10 个核心队列消费者；`all` 模式会部署 Magento 官方 21 个消费者，适合大促或批量导入时使用。
- 默认线程数为 1，可用 `--threads N` 为每个消费者生成更多实例。
- `list all` 会列出整台主机上所有 `magento-consumer@*.service`，便于排查残留实例。
- `remove <site>` 不仅停用 systemd unit，还会将该站点 `app/etc/env.php` 中的 `queue.amqp` 配置清空，方便重新部署。
- 默认 AMQP 凭据来自 `salt/pillar/saltgoat.sls` 的 `rabbitmq_password`，也可通过 `--amqp-password` 覆盖。

### Restic 备份（可选模块）

```bash
# 一键初始化（自动安装 restic、生成 Pillar/密码，并默认备份 /var/www/<site>）
sudo saltgoat magetools backup restic install --site bank --repo /home/Dropbox/bank/snapshots
```

```bash
# 先在 salt/pillar/backup-restic.sls 中配置 repo/凭据，并在 top.sls 引入

# 根据 Pillar 配置安装 Restic + systemd timer
sudo saltgoat magetools backup restic install

# 立即执行一次备份
sudo saltgoat magetools backup restic run

# 查看 systemd timer/service 状态或日志
sudo saltgoat magetools backup restic status
sudo saltgoat magetools backup restic logs 100
sudo saltgoat magetools backup restic summary      # 汇总各站点的快照与服务状态

# 使用 Restic CLI 列出快照/执行检查/保留策略
sudo saltgoat magetools backup restic snapshots
sudo saltgoat magetools backup restic check
sudo saltgoat magetools backup restic forget --keep-daily 7 --keep-weekly 4
sudo saltgoat magetools backup restic exec restore latest --target /tmp/restore

# 仅备份单个站点并写入本地主机仓库
sudo saltgoat magetools backup restic run --site bank --backup-dir /home/Dropbox/bank/snapshots --password-file ~/.config/restic-bank.txt --tag bank-manual
```

- Restic 子命令需要读取 `/etc/restic/restic.env`，建议以 sudo 执行；`run` 默认备份 Pillar 中的所有路径，传入 `--site/--paths/--backup-dir(--repo)/--tag/--password(--password-file)` 后会直接执行一次手动备份，适用于单站点或临时仓库。
- `summary` 会读取 `/etc/restic/sites.d/*.env`，展示每个站点的仓库、最新快照时间、容量与 systemd 服务状态。
- `saltgoat magetools backup restic install` 会自动安装 restic、写入 `salt/pillar/backup-restic.sls`、在 `saltgoat.sls` 中生成 `restic_password`（可通过 `saltgoat passwords --show` 查看）并下发 systemd service/timer。
- 若尚未部署 `optional.backup-restic`，可用 `--password` 或 `--password-file` 临时提供凭据，但仍需提前执行 `sudo apt install restic` 并使用 `saltgoat magetools backup restic exec init --repo ...` 初始化仓库。
- 结合 `saltgoat magetools maintenance <site> weekly --trigger-restic --restic-site <site> --restic-backup-dir /home/Dropbox/<site>/snapshots` 可将单站点备份纳入每周自动任务。

### XtraBackup（Percona MySQL 热备）

```bash
# 根据 Pillar 配置部署 optional.mysql-backup
sudo saltgoat magetools xtrabackup mysql install

# 立即触发一次备份 / 查看状态或日志
sudo saltgoat magetools xtrabackup mysql run
sudo saltgoat magetools xtrabackup mysql status
sudo saltgoat magetools xtrabackup mysql logs 200

# 巡检所有站点的备份目录、容量与最后执行时间
sudo saltgoat magetools xtrabackup mysql summary

# 导出单库 mysqldump（默认压缩到 /var/backups/mysql/dumps）
sudo saltgoat magetools xtrabackup mysql dump \
    --database bankmage \
    --backup-dir /home/doge/Dropbox/bank/databases \
    --repo-owner doge

# 创建 Magneto 站点数据库与账号（授予 ALL + PROCESS/SUPER）
sudo saltgoat magetools mysql create \
    --database tankmage \
    --user tank \
    --password 'tank.2010'
```

- 定时任务由 `saltgoat-mysql-backup.timer` 管理，输出目录默认 `/var/backups/mysql/xtrabackup/<timestamp>`，可在 `salt/pillar/mysql-backup.sls` 中自定义。
- 备份完成后会自动 `chown -R repo_owner`，便于 Dropbox/Restic 二次归档。
- `dump` 会使用 mysqldump 生成 `.sql.gz` 文件，可带 `--backup-dir`、`--repo-owner` 与 `--no-compress` 细化输出。
- `mysql create` 会读取 Pillar 中的 root 密码，自动建库/建用户并授予默认权限，可用 `--no-super`、`--charset`、`--collation` 等选项调整。
- 旧命令 `saltgoat magetools backup mysql ...` 仍可用，但会提示迁移至 `xtrabackup`。

#### Valkey 配置命令说明
- `valkey-setup`：通过 Salt 状态写入 env.php，支持 `--reuse-existing`、`--cache-db`、`--page-db`、`--session-db`、`--cache-prefix`、`--session-prefix`、`--host`、`--port` 等参数。
- `valkey-check`：验证 env.php、Valkey 连接、权限与密码一致性，可选参数包括 `--site-path`、`--expected-owner`、`--expected-group`、`--expected-perms`、`--valkey-conf`。
- `valkey-renew`：保留传统 Shell 脚本流程，用于快速重新分配数据库或清理旧缓存。

### 维护管理
```bash
# 检查维护状态
saltgoat magetools maintenance tank status

# 启用/禁用维护模式
saltgoat magetools maintenance tank enable
saltgoat magetools maintenance tank disable

# 执行维护任务
saltgoat magetools maintenance tank daily
saltgoat magetools maintenance tank weekly
saltgoat magetools maintenance tank monthly

# 健康检查和备份
saltgoat magetools maintenance tank health
saltgoat magetools maintenance tank backup
saltgoat magetools maintenance tank cleanup
saltgoat magetools maintenance tank deploy

# 示例：允许 weekly 任务刷新 Valkey 并触发 Restic
saltgoat magetools maintenance tank weekly --allow-valkey-flush --trigger-restic
```

### 定时任务管理（Salt Schedule）
```bash
saltgoat magetools cron tank install      # 安装 Salt Schedule 维护任务
saltgoat magetools cron tank status       # 查看计划任务与 salt-minion 状态
saltgoat magetools cron tank test         # 手动触发任务并验证
saltgoat magetools cron tank logs         # 查看维护/健康检查日志
saltgoat magetools cron tank uninstall    # 移除 Salt Schedule 任务
```

### 其他功能
```bash
# 性能分析
saltgoat magetools performance

# 安全扫描
saltgoat magetools security

# 备份
saltgoat magetools backup magento        # 旧版本地备份（tar + setup:db:backup）
saltgoat magetools backup restic run     # 若启用 Restic 模块，执行一次快照

# 部署
saltgoat magetools deploy
```

## 工具说明

### N98 Magerun2
Magento 2的官方CLI工具，提供：
- 缓存管理
- 索引重建
- 系统信息查看
- 开发者控制台

### PHPUnit
PHP单元测试框架，用于：
- 测试自定义模块
- 确保代码质量
- 功能回归测试
- 代码覆盖率分析

### Xdebug
PHP调试工具，提供：
- 断点调试
- 性能分析
- 代码覆盖率
- 远程调试

## 详细文档

### Magento 维护系统
详细的维护系统文档请参考：
- [Magento 维护系统完整文档](../docs/MAGENTO_MAINTENANCE.md)

该文档包含：
- 完整的维护任务说明
- 定时任务配置详解
- 健康检查功能说明
- 故障排除指南
- 最佳实践建议

## 帮助信息

```bash
# 查看帮助
saltgoat magetools help
saltgoat help magetools
```

## 注意事项

1. **PHP扩展**: PHPUnit需要dom、mbstring、xml、xmlwriter等扩展
2. **权限**: 某些操作需要sudo权限
3. **Magento环境**: 部分功能需要在Magento项目目录中运行
4. **版本兼容**: 工具版本与Magento版本需要兼容

## 版本信息

- **SaltGoat版本**: v1.0.5+
- **支持Magento**: 2.4.8+
- **PHP要求**: 8.3

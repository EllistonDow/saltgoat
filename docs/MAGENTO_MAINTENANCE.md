# SaltGoat Magento 2 维护系统文档

## 概述

SaltGoat Magento 2 维护系统提供了完整的自动化维护解决方案，包括日常维护、定时任务管理、健康检查等功能。系统采用 Salt 原生实现，完全符合 SaltGoat 的设计理念。

## 快速开始

```bash
# 安装 / 更新 Salt Schedule
saltgoat magetools cron <site> install

# 检查计划任务与 Salt Minion 状态
saltgoat magetools cron <site> status

# 立即触发一次例行维护，用于验证
saltgoat magetools cron <site> test
```

> 如果目标主机尚未运行 `salt-minion`，`install` 会自动写入 `/etc/cron.d/magento-maintenance` 作为临时替代；待 Minion 就绪后再次执行即可切换回 Salt Schedule。

## 功能特性

### 🔧 维护管理
- **维护模式控制** - 启用/禁用维护模式
- **日常维护** - 缓存清理、索引重建、会话清理、日志清理
- **每周维护** - 备份、日志轮换、Valkey 清空（可选）、性能检查
- **每月维护** - 完整部署流程（维护模式→清理→升级→编译→部署→索引→禁用维护→清理缓存）
- **健康检查** - Magento状态、数据库连接、缓存状态、索引状态

### ⏰ 定时任务管理
- **系统 Cron（可选）** - 必要时可手动维护传统 cron 任务
- **Salt Schedule** - 使用 Salt 原生状态管理（推荐）
- **智能检测** - 自动检测数据库架构更新并执行相应操作

### 📊 监控与日志
- **统一日志格式** - 使用 SaltGoat 的统一日志格式
- **详细状态报告** - 提供系统各组件状态信息
- **错误处理** - 智能错误检测和处理

## 使用方法

### 基本语法
```bash
saltgoat magetools maintenance <site> <action>
saltgoat magetools cron <site> <action>
```

> **提示**：若目标主机未安装或未运行 `salt-minion`，上述 `saltgoat magetools cron` 命令会自动改用系统 Cron，在 `/etc/cron.d/magento-maintenance` 写入计划任务；待 `salt-minion` 启用后再次执行 `install` 即可恢复为 Salt Schedule。

### 维护管理命令

#### 维护状态检查
```bash
# 检查维护状态
saltgoat magetools maintenance tank status
```

#### 维护模式控制
```bash
# 启用维护模式
saltgoat magetools maintenance tank enable

# 禁用维护模式
saltgoat magetools maintenance tank disable
```

#### 维护任务执行
```bash
# 执行每日维护任务
saltgoat magetools maintenance tank daily

# 执行每周维护任务
saltgoat magetools maintenance tank weekly

# 执行每月维护任务（完整部署流程）
saltgoat magetools maintenance tank monthly

# 执行健康检查
saltgoat magetools maintenance tank health

# 创建备份
saltgoat magetools maintenance tank backup

# 清理日志和缓存
saltgoat magetools maintenance tank cleanup

# 完整部署流程
saltgoat magetools maintenance tank deploy

# 示例：每周任务同时刷新 Valkey 并触发 Restic
saltgoat magetools maintenance tank weekly --allow-valkey-flush --trigger-restic
```

常用参数：

| 参数 | 说明 |
|------|------|
| `--site-path PATH` | 指定站点根目录（默认 `/var/www/<site>`） |
| `--magento-user USER` | 执行 Magento CLI 的用户（默认 `www-data`） |
| `--php-bin PATH` | PHP 可执行文件路径（默认 `php`） |
| `--composer-bin PATH` | Composer 可执行文件 |
| `--valkey-cli PATH` | valkey-cli 可执行文件（旧 `--redis-cli` 仍兼容，仅打印弃用提示） |
| `--allow-valkey-flush` | 允许在 weekly 任务中执行 `valkey-cli FLUSHALL`（旧 `--allow-redis-flush` alias） |
| `--allow-setup-upgrade` | 允许 monthly/ deploy 执行 `setup:upgrade` |
| `--backup-dir PATH` | 启用传统归档备份并指定输出目录 |
| `--mysql-database NAME` | 归档备份使用的数据库名称（默认与站点同名） |
| `--mysql-user USER` / `--mysql-password PASS` | mysqldump 用户与密码 |
| `--trigger-restic` | 若已启用 Restic 模块，联动触发一次快照 |
| `--restic-site NAME` | 触发 Restic 时仅备份指定站点（传递给 `backup restic run --site`） |
| `--restic-backup-dir PATH` | 覆盖 Restic 仓库（如 `/home/Dropbox/<site>/snapshots`） |
| `--restic-extra-path PATH` | Restic 额外路径，可多次使用或改用 `--restic-extra-paths "p1,p2"` |
| `--static-langs \"en_US zh_CN\"` | 静态资源部署语言列表 |
| `--static-jobs N` | 静态资源部署线程数（默认 4） |

> 提示：`--restic-*` 参数依赖 `optional.backup-restic` 下发的仓库与密码配置（来自 Pillar）。若仅需一次性备份，可直接使用 `saltgoat magetools backup restic run --password-file ...`。

### 定时任务管理

#### Salt Schedule（推荐）
```bash
# 安装 Salt Schedule 任务
saltgoat magetools cron tank install

# 查看状态
saltgoat magetools cron tank status

# 测试功能
saltgoat magetools cron tank test

# 查看日志
saltgoat magetools cron tank logs

# 卸载任务
saltgoat magetools cron tank uninstall
```

> `saltgoat magetools cron` 现在基于 Salt Schedule 管理所有维护计划，无需再手动编辑 crontab。

## 维护任务详解

### 每日维护任务
**执行时间**: 默认每天凌晨 02:00

**包含操作**
1. 缓存清理 `cache:clean`
2. 索引状态巡检 `indexer:status`
3. 仅在索引异常时自动重建 `indexer:reindex`
4. 权限巡检（提示 root 属主文件）
5. 会话清理 `session:clean`
6. 日志清理 `log:clean`

> 可通过 `--site-path`、`--php-bin`、`--magento-user` 等参数自定义运行环境。

### 每周维护任务
**执行时间**: 默认每周日凌晨 03:00

**包含操作**
1. 缓存刷新 `cache:flush`
2. 索引状态巡检 + 全量重建（保障一周一次的干净基线）
3. 日志轮换（>100MB 文件 truncate）
4. 队列消费者列表、cron 可用性、FPC 模式等运行时检查
5. 归档备份（仅在提供 `--backup-dir` 时启用；推荐以 Restic/XtraBackup 为主）  
6. 可选 Restic 快照（`--trigger-restic`，可叠加 `--restic-site/--restic-backup-dir/--restic-extra-path`）
7. 可选 Valkey 清空（`--allow-valkey-flush`）
8. 依赖巡检 `n98-magerun2 sys:check` / `composer outdated --no-dev`

### 每月维护任务（完整部署流程）
**执行时间**: 默认每月 1 日凌晨 04:00

**包含操作**
1. 启用维护模式 `maintenance:enable`
2. 清理缓存/生成文件/静态资源/产品缓存
3. 可选 `setup:upgrade`（通过 `--allow-setup-upgrade` 启用）
4. 编译依赖 `setup:di:compile`
5. 静态部署 `setup:static-content:deploy -f -j N`
6. 全量索引 `indexer:reindex`
7. 禁用维护模式并清理缓存
8. Sitemap 生成、模块状态报告

### 健康检查任务
**执行时间**: 每小时
**检查项目**:
1. **Magento CLI 基础命令**（版本、DB 状态、缓存/索引状态）
2. **队列消费者列表** - 观察队列绑定是否完整
3. **Cron 日志校验** - 检查 Magento cron 日志是否持续更新
4. **FPC 模式确认** - 输出当前缓存引擎配置
5. **n98-magerun2 sys:check**（若已安装）
6. **站点磁盘使用情况**

**智能功能**:
- 自动检测并输出索引/缓存异常
- 触发 Magento Cron，便于确认脚本能够被执行
- 通过 Telegram / `/var/log/saltgoat/alerts.log` 输出健康检查上下文

### 备份策略建议
- **推荐组合**：使用 Restic（`saltgoat-restic-backup` 或 `saltgoat magetools backup restic run`）搭配 XtraBackup 物理备份，满足长期和快速恢复需求。
- **单库导出**：`saltgoat magetools xtrabackup mysql dump` 面向站点迁移/调试场景，命令会输出备份文件大小，通过 Salt event 与 Telegram 双管齐下记录结果。
- **归档备份**：只有在传入 `--backup-dir` 时才会生成 tar/mysqldump，若已启用 Restic/XtraBackup，可视情况关闭以避免重复占用存储。
- **可观测性**：所有备份事件都会写入 `/var/log/saltgoat/alerts.log`；配置了 Telegram 的主机还能收到 `profile_summary/send_ok` 日志，用于审计。

#### 按数据库定制 Salt Schedule（示例 Pillar）
```yaml
magento_schedule:
  mysql_dump_jobs:
    - name: tankmage-dump-hourly
      cron: '0 * * * *'
      database: tankmage
      backup_dir: /home/doge/Dropbox/tank/databases
      repo_owner: doge
      site: tank
    - name: bankmage-dump-every-2h
      cron: '0 */2 * * *'
      database: bankmage
      backup_dir: /home/doge/Dropbox/bank/databases
      repo_owner: doge
      no_compress: true
      site: bank
```
建议复制 `salt/pillar/magento-schedule.sls.sample` 为实际文件后再写入上述配置；执行 `saltgoat magetools cron <site> install` 后会生成对应的 Salt Schedule（若 `salt-minion` 不可用则写入 `/etc/cron.d/magento-maintenance`）。每次导出仍会触发 Salt event 与 Telegram 通知，便于追踪。

> 提示：在 mysqldump 任务中加入 `site` 或 `sites` 字段，SaltGoat 才能在多站点场景下仅为指定站点安装/卸载该计划任务。

## 定时任务配置

### Salt Schedule 配置
Salt Schedule 通过 Salt Minion 内置计划任务管理维护流程。执行以下命令可以查看当前配置：

```bash
salt-call --local schedule.list --out=yaml | grep -A3 'magento-'
```

默认会创建以下任务：

- `magento-cron`：每分钟执行一次 `php bin/magento cron:run`
- `magento-daily-maintenance`：每日凌晨 2 点运行日常维护
- `magento-weekly-maintenance`：每周日凌晨 3 点运行每周维护
- `magento-monthly-maintenance`：每月 1 日凌晨 4 点运行完整部署流程
- `magento-health-check`：每小时进行健康检查

需要调整时间时，可以通过 `salt-call schedule.modify` 修改对应任务的 `cron` 表达式。

```bash
salt-call --local schedule.modify magento-cron cron '*/10 * * * *'
```

> 若 `salt-minion` 当前不可用，上述命令会返回空列表；此时 `saltgoat magetools cron <site> install` 将自动生成 `/etc/cron.d/magento-maintenance` 作为临时替代方案。

### Salt Beacons 与 Reactor
SaltGoat 提供事件驱动的维护能力，推荐通过以下命令启用并检查状态：

```bash
# 配置服务/资源 Beacon，并启用 Reactor 自动化
saltgoat monitor enable-beacons

# 查看当前 Beacon 与 Schedule 状态
saltgoat monitor beacons-status
```

启用后，Salt 会自动监控关键服务与资源使用率，并在阈值触发时写入 `/var/log/saltgoat/alerts.log`，必要时重启服务或触发权限修复。

> **依赖说明**：Beacon/Reactor 功能需要在本机运行 `salt-minion`，并能访问配置了 Reactor 的 `salt-master`。若命令检测到依赖缺失，会给出警告并保留配置文件，待服务上线后再次执行即可生效。

### 日志文件
- `/var/log/magento-cron.log` - Magento cron 任务日志
- `/var/log/magento-maintenance.log` - 维护任务日志
- `/var/log/magento-health.log` - 健康检查日志

## 技术实现

### Salt States
维护系统使用以下 Salt States：
- `salt/states/optional/magento-schedule.sls` - 定时任务配置（Salt Schedule 优先，自动回退 Cron）
- `salt/states/optional/magento-maintenance/*.sls` - 维护子任务（daily/weekly/monthly/backup/health 等）

### 权限管理
- 使用 `sudo -u www-data` 执行 Magento CLI 命令
- 确保文件所有权为 `www-data:www-data`
- 正确的文件权限设置

### 错误处理
- 智能错误检测和处理
- 详细的错误日志记录
- 优雅的错误恢复机制

## 最佳实践

### 1. 定时任务选择
- **推荐使用 Salt Schedule** - 符合 SaltGoat 设计理念
- **如需备用** - 可手动编写 cron 任务，但推荐保持 Salt Schedule 为主

### 2. 维护频率
- **每日维护** - 适合高流量站点
- **每周维护** - 适合中等流量站点
- **每月维护** - 适合低流量站点或开发环境

### 3. 监控建议
- 定期检查维护日志
- 监控健康检查结果
- 设置告警机制

### 4. 备份策略
- 执行重要操作前创建备份
- 定期测试备份恢复流程
- 保留多个备份版本

## 故障排除

### 常见问题

#### 1. 权限问题
```bash
# 修复权限
saltgoat magetools permissions fix /var/www/tank
```

#### 2. 数据库连接问题
```bash
# 检查数据库状态
saltgoat magetools maintenance tank health
```

#### 3. 缓存问题
```bash
# 清理缓存
saltgoat magetools maintenance tank cleanup
```

#### 4. 定时任务不执行
```bash
# 检查定时任务状态
saltgoat magetools cron tank status
```

### 日志分析
```bash
# 查看维护日志
saltgoat magetools cron tank logs

# 查看系统日志
tail -f /var/log/magento-maintenance.log
tail -f /var/log/magento-health.log
```

## 版本信息

- **SaltGoat版本**: v0.8.1+
- **支持Magento**: 2.4.x
- **PHP要求**: 8.1+
- **Salt要求**: 3000+

## 更新日志

### v0.8.1
- 添加 Salt Schedule 支持
- 实现智能健康检查
- 优化错误处理机制
- 统一日志格式

### v0.8.0
- 添加维护管理功能
- 实现定时任务管理
- 添加健康检查功能

---

**注意**: 本系统专为 SaltGoat 设计，使用 Salt 原生功能实现，确保与 SaltGoat 生态系统的完美集成。

# SaltGoat Magento 2 维护系统文档

## 概述

SaltGoat Magento 2 维护系统提供了完整的自动化维护解决方案，包括日常维护、定时任务管理、健康检查等功能。系统采用 Salt 原生实现，完全符合 SaltGoat 的设计理念。

## 功能特性

### 🔧 维护管理
- **维护模式控制** - 启用/禁用维护模式
- **日常维护** - 缓存清理、索引重建、会话清理、日志清理
- **每周维护** - 备份、日志轮换、Redis清空、性能检查
- **每月维护** - 完整部署流程（维护模式→清理→升级→编译→部署→索引→禁用维护→清理缓存）
- **健康检查** - Magento状态、数据库连接、缓存状态、索引状态

### ⏰ 定时任务管理
- **系统 Cron** - 使用系统原生 crontab 管理
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
saltgoat magetools salt-schedule <site> <action>
```

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
```

### 定时任务管理

#### Salt Schedule（推荐）
```bash
# 安装 Salt Schedule 任务
saltgoat magetools salt-schedule tank install

# 查看状态
saltgoat magetools salt-schedule tank status

# 测试功能
saltgoat magetools salt-schedule tank test

# 查看日志
saltgoat magetools salt-schedule tank logs

# 卸载任务
saltgoat magetools salt-schedule tank uninstall
```

#### 系统 Cron（备用方案）
```bash
# 安装系统 Cron 任务
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

## 维护任务详解

### 每日维护任务
**执行时间**: 每天凌晨2点
**包含操作**:
1. **缓存清理** - `php bin/magento cache:flush`
2. **索引重建** - `php bin/magento indexer:reindex`
3. **会话清理** - `php bin/magento session:clean`
4. **日志清理** - `php bin/magento log:clean`

**目的**: 保持系统日常运行状态，清理临时数据

### 每周维护任务
**执行时间**: 每周日凌晨3点
**包含操作**:
1. **创建备份** - `php bin/magento setup:backup`
2. **日志轮换** - 清理大于100MB的日志文件
3. **Redis清空** - `redis-cli FLUSHALL`
4. **性能检查** - `n98-magerun2 sys:check`

**目的**: 深度清理和性能优化

### 每月维护任务（完整部署流程）
**执行时间**: 每月1日凌晨4点
**包含操作**:
1. **启用维护模式** - `php bin/magento maintenance:enable`
2. **清理缓存和生成文件** - 删除 `var/{cache,page_cache,view_preprocessed,di}/*`、`pub/static/*`、`generated/*`
3. **数据库升级** - `php bin/magento setup:upgrade`
4. **编译依赖注入** - `php bin/magento setup:di:compile`
5. **部署静态内容** - `php bin/magento setup:static-content:deploy -f -j 4`
6. **重建索引** - `php bin/magento indexer:reindex`
7. **禁用维护模式** - `php bin/magento maintenance:disable`
8. **清理缓存** - `php bin/magento cache:clean`

**目的**: 完整的系统更新和部署流程

### 健康检查任务
**执行时间**: 每小时
**检查项目**:
1. **Magento状态** - 检查CLI是否正常工作
2. **数据库连接** - 检查数据库连接和架构状态
3. **缓存状态** - 检查缓存系统状态
4. **索引状态** - 检查索引系统状态

**智能功能**:
- 自动检测数据库架构更新需求
- 自动执行 `setup:upgrade` 和 `cache:clean`
- 提供详细的状态报告

## 定时任务配置

### Salt Schedule 配置
Salt Schedule 使用 `/etc/cron.d/magento-maintenance` 配置文件：

```bash
# Magento 2 定时维护任务
# 每5分钟执行 Magento cron
*/5 * * * * www-data cd /var/www/tank && sudo -u www-data php bin/magento cron:run >> /var/log/magento-cron.log 2>&1

# 每日维护任务 - 每天凌晨2点执行
0 2 * * * root /usr/local/bin/magento-maintenance-salt tank daily >> /var/log/magento-maintenance.log 2>&1

# 每周维护任务 - 每周日凌晨3点执行
0 3 * * 0 root /usr/local/bin/magento-maintenance-salt tank weekly >> /var/log/magento-maintenance.log 2>&1

# 每月维护任务 - 每月1日凌晨4点执行（完整部署流程）
0 4 1 * * root /usr/local/bin/magento-maintenance-salt tank monthly >> /var/log/magento-maintenance.log 2>&1

# 健康检查任务 - 每小时执行
0 * * * * root /usr/local/bin/magento-maintenance-salt tank health >> /var/log/magento-health.log 2>&1
```

### 日志文件
- `/var/log/magento-cron.log` - Magento cron 任务日志
- `/var/log/magento-maintenance.log` - 维护任务日志
- `/var/log/magento-health.log` - 健康检查日志

## 技术实现

### Salt States
维护系统使用以下 Salt States：
- `salt/states/optional/magento-schedule.sls` - 定时任务配置
- `salt/states/scripts/magento-maintenance-salt.sh` - 维护脚本

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
- **系统 Cron 作为备用** - 在 Salt Schedule 不可用时使用

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
saltgoat magetools salt-schedule tank status
```

### 日志分析
```bash
# 查看维护日志
saltgoat magetools salt-schedule tank logs

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

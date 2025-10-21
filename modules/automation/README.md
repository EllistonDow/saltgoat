# SaltGoat 自动化模块

## 📋 功能概述

自动化模块提供系统自动化功能，包括任务自动化、报告生成、定时任务管理等自动化操作。

## 🚀 使用方法

### 基本语法
```bash
saltgoat <automation_command> [options]
```

### 支持的自动化功能

| 功能 | 命令 | 描述 |
|------|------|------|
| `automation` | 任务自动化 | 创建、管理自动化任务 |
| `reports` | 报告生成 | 生成系统报告和分析 |

## 📖 使用示例

### 任务自动化
```bash
# 创建自动化任务
saltgoat automation create "daily-backup" "backup-database"

# 列出自动化任务
saltgoat automation list

# 运行自动化任务
saltgoat automation run "daily-backup"

# 删除自动化任务
saltgoat automation delete "daily-backup"
```

### 报告生成
```bash
# 生成系统报告
saltgoat reports system

# 生成性能报告
saltgoat reports performance

# 生成安全报告
saltgoat reports security

# 列出报告
saltgoat reports list

# 清理旧报告
saltgoat reports cleanup
```

## 🔧 自动化功能详解

### 任务自动化功能
- **任务创建**: 定义自动化任务和触发条件
- **任务管理**: 启动、停止、删除任务
- **任务监控**: 监控任务执行状态
- **日志记录**: 记录任务执行日志
- **错误处理**: 自动错误处理和重试

### 报告生成功能
- **系统报告**: 系统状态、资源使用报告
- **性能报告**: 性能指标、趋势分析报告
- **安全报告**: 安全扫描、风险评估报告
- **报告管理**: 报告存储、清理、归档

## 📊 自动化任务示例

### 数据库备份任务
```bash
# 创建每日数据库备份任务
saltgoat automation create "daily-mysql-backup" \
  --schedule "0 2 * * *" \
  --command "saltgoat database mysql backup all" \
  --description "每日MySQL数据库备份"
```

### 系统监控任务
```bash
# 创建系统健康检查任务
saltgoat automation create "health-check" \
  --schedule "*/15 * * * *" \
  --command "saltgoat maintenance health" \
  --description "每15分钟系统健康检查"
```

### 日志清理任务
```bash
# 创建日志清理任务
saltgoat automation create "log-cleanup" \
  --schedule "0 1 * * 0" \
  --command "saltgoat maintenance cleanup logs" \
  --description "每周日志清理"
```

## 📈 报告示例

### 系统报告
```
==========================================
SaltGoat 系统报告
生成时间: 2025-01-21 15:30:00
==========================================
[INFO] 系统信息:
- 操作系统: Ubuntu 24.04 LTS
- 内核版本: 6.8.0-85-generic
- 运行时间: 7天 12小时
- 负载平均: 0.15, 0.20, 0.25

[INFO] 资源使用:
- CPU使用率: 15%
- 内存使用率: 45%
- 磁盘使用率: 60%
- 网络状态: 正常

[INFO] 服务状态:
- Nginx: 运行中
- MySQL: 运行中
- PHP-FPM: 运行中
- Valkey: 运行中
==========================================
```

### 性能报告
```
==========================================
SaltGoat 性能报告
生成时间: 2025-01-21 15:30:00
==========================================
[INFO] 性能指标:
- 系统性能评分: 85/100
- Nginx性能评分: 90/100
- MySQL性能评分: 88/100
- PHP性能评分: 82/100

[INFO] 性能趋势:
- CPU使用率: 稳定
- 内存使用率: 稳定
- 磁盘I/O: 正常
- 网络延迟: 正常

[INFO] 优化建议:
- 启用MySQL查询缓存
- 优化PHP内存限制
- 清理系统日志
==========================================
```

## 📁 文件结构

```
modules/automation/
├── automation.sh          # 主自动化脚本
├── reports.sh             # 报告生成脚本
└── README.md              # 本文档
```

## 🔗 相关功能

- **系统维护**: `saltgoat maintenance` - 系统维护
- **监控集成**: `saltgoat monitoring` - 监控配置
- **性能分析**: `saltgoat profile analyze` - 性能分析

## 📝 更新日志

- **v0.5.7** - 模块化重构，完善自动化功能
- 任务自动化管理系统
- 智能报告生成功能
- 定时任务和监控集成

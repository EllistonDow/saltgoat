# SaltGoat 系统维护模块

## 📋 功能概述

系统维护模块提供全面的系统维护功能，包括系统更新、服务管理、日志清理、备份恢复等操作。

## 🚀 使用方法

### 基本语法
```bash
saltgoat maintenance <operation> [options]
```

### 支持的维护操作

| 操作 | 描述 | 功能 |
|------|------|------|
| `update` | 系统更新 | 检查、升级、清理系统包 |
| `service` | 服务管理 | 启动、停止、重启、重载服务 |
| `cleanup` | 系统清理 | 清理日志、临时文件、缓存 |
| `disk` | 磁盘管理 | 磁盘使用分析、大文件查找 |
| `health` | 健康检查 | 系统健康状态检查 |

## 📖 使用示例

### 系统更新
```bash
# 检查系统更新
saltgoat maintenance update check

# 升级系统包
saltgoat maintenance update upgrade

# 完整升级
saltgoat maintenance update dist-upgrade

# 自动清理
saltgoat maintenance update autoremove

# 清理包缓存
saltgoat maintenance update clean
```

### 服务管理
```bash
# 重启服务
saltgoat maintenance service restart nginx

# 启动服务
saltgoat maintenance service start mysql

# 停止服务
saltgoat maintenance service stop php8.3-fpm

# 重载配置
saltgoat maintenance service reload nginx

# 查看服务状态
saltgoat maintenance service status nginx
```

### 系统清理
```bash
# 清理系统日志
saltgoat maintenance cleanup logs

# 清理临时文件
saltgoat maintenance cleanup temp

# 清理包缓存
saltgoat maintenance cleanup cache

# 清理用户缓存
saltgoat maintenance cleanup user-cache
```

### 磁盘管理
```bash
# 查看磁盘使用情况
saltgoat maintenance disk usage

# 查找大文件
saltgoat maintenance disk find-large 100M

# 查找大目录
saltgoat maintenance disk find-large-dirs 1G
```

### 健康检查
```bash
# 系统健康检查
saltgoat maintenance health
```

## 🔧 维护功能详解

### 系统更新功能
- **检查更新**: 显示可用的系统更新
- **安全更新**: 优先安装安全补丁
- **版本锁定**: 保护核心软件版本
- **自动清理**: 清理不需要的包

### 服务管理功能
- **服务控制**: 启动、停止、重启服务
- **配置重载**: 重新加载配置文件
- **状态检查**: 查看服务运行状态
- **依赖管理**: 处理服务依赖关系

### 系统清理功能
- **日志清理**: 清理旧日志文件
- **临时文件**: 清理系统临时文件
- **缓存清理**: 清理各种缓存文件
- **空间回收**: 回收磁盘空间

### 磁盘管理功能
- **使用分析**: 分析磁盘使用情况
- **大文件查找**: 查找占用空间的大文件
- **目录分析**: 分析目录大小分布
- **空间优化**: 提供空间优化建议

## 📊 维护报告

### 健康检查报告
```
==========================================
系统健康检查报告
==========================================
[SUCCESS] 系统运行时间: 7天 12小时
[SUCCESS] 内存使用率: 45%
[SUCCESS] 磁盘使用率: 60%
[WARNING] 发现 3 个服务需要重启
[INFO] 建议运行: saltgoat maintenance service restart <service>
==========================================
```

### 更新检查报告
```
==========================================
系统更新检查
==========================================
[INFO] 发现 6 个可用更新
[INFO] 安全更新: 3 个
[INFO] 功能更新: 3 个
[INFO] 建议运行: sudo apt update && sudo apt upgrade
==========================================
```

## 📁 文件结构

```
modules/maintenance/
├── maintenance.sh          # 主维护脚本
├── backup.sh              # 备份功能
├── logs.sh                # 日志管理
└── README.md              # 本文档
```

## 🔗 相关功能

- **故障诊断**: `saltgoat diagnose` - 系统故障诊断
- **性能分析**: `saltgoat profile analyze` - 性能分析
- **版本锁定**: `saltgoat version-lock` - 版本管理

## 📝 更新日志

- **v0.5.7** - 模块化重构，完善维护功能
- 智能更新检查和版本保护
- 服务管理和健康检查
- 系统清理和磁盘管理

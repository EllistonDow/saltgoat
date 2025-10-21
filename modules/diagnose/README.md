# SaltGoat 故障诊断模块

## 📋 功能概述

故障诊断模块提供全面的系统和服务诊断功能，帮助快速识别和解决LEMP环境中的问题。

## 🚀 使用方法

### 基本语法
```bash
saltgoat diagnose <type>
```

### 支持的诊断类型

| 类型 | 描述 | 检查内容 |
|------|------|----------|
| `nginx` | Nginx服务诊断 | 服务状态、配置语法、端口占用、日志错误 |
| `mysql` | MySQL服务诊断 | 服务状态、连接测试、配置安全、错误日志 |
| `php` | PHP服务诊断 | PHP-FPM状态、版本检查、扩展检查、日志分析 |
| `system` | 系统状态诊断 | CPU、内存、负载、更新状态、时间同步 |
| `network` | 网络连接诊断 | 外网连接、DNS解析、防火墙、SSH配置 |
| `all` | 完整系统诊断 | 以上所有诊断类型的综合检查 |

## 📖 使用示例

### 诊断单个服务
```bash
# 诊断Nginx服务
saltgoat diagnose nginx

# 诊断MySQL服务
saltgoat diagnose mysql

# 诊断PHP服务
saltgoat diagnose php
```

### 诊断系统状态
```bash
# 诊断系统状态
saltgoat diagnose system

# 诊断网络连接
saltgoat diagnose network
```

### 完整系统诊断
```bash
# 执行完整系统诊断
saltgoat diagnose all
```

## 📊 输出说明

### 状态标识
- ✅ **绿色** - 正常状态，无问题
- ⚠️ **黄色** - 警告信息，需要关注
- ❌ **红色** - 错误问题，需要修复

### 诊断结果格式
```
==========================================
[INFO] 开始诊断 <服务名>...
[WARNING] <服务名>诊断完成 - 发现 X 个问题:
[ERROR]   问题描述
[INFO]    建议修复: 修复命令或建议
==========================================
```

## 🔧 常见问题解决

### Nginx相关问题
- **服务未运行**: `sudo systemctl start nginx`
- **配置语法错误**: 检查 `/etc/nginx/nginx.conf` 和 `sites-enabled/` 目录
- **端口占用**: 检查并停止占用端口80的进程

### MySQL相关问题
- **服务未运行**: `sudo systemctl start mysql`
- **连接失败**: 检查MySQL服务状态和用户权限
- **配置安全**: 修改 `bind-address` 为 `127.0.0.1`

### PHP相关问题
- **PHP-FPM未运行**: `sudo systemctl start php8.3-fpm`
- **缺少扩展**: `sudo apt install php8.3-<extension>`
- **内存限制**: 修改 `php.ini` 中的 `memory_limit`

### 系统相关问题
- **磁盘空间不足**: 清理临时文件或增加磁盘容量
- **内存使用过高**: 检查内存使用情况，优化应用程序
- **系统更新**: `sudo apt update && sudo apt upgrade`

## 📁 文件结构

```
modules/diagnose/
├── diagnose.sh          # 主诊断脚本
└── README.md            # 本文档
```

## 🔗 相关功能

- **性能分析**: `saltgoat profile analyze` - 深度性能分析
- **版本锁定**: `saltgoat version-lock` - 软件版本管理
- **系统维护**: `saltgoat maintenance` - 系统维护工具

## 📝 更新日志

- **v0.5.7** - 初始版本，支持6种诊断类型
- 智能问题检测和修复建议
- 完整的诊断摘要和评分系统

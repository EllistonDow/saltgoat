# SaltGoat 版本锁定模块

## 📋 功能概述

版本锁定模块提供核心LEMP软件版本管理功能，防止意外更新，确保生产环境的稳定性和一致性。

## 🚀 使用方法

### 基本语法
```bash
sudo saltgoat version-lock <action>
```

### 支持的操作

| 操作 | 描述 | 功能 |
|------|------|------|
| `lock` | 锁定核心软件版本 | 使用apt-mark hold锁定指定软件包 |
| `unlock` | 解锁软件版本 | 取消软件包版本锁定 |
| `show` | 显示锁定的软件包 | 列出当前锁定的软件包和版本 |
| `status` | 检查软件版本状态 | 显示所有核心软件的当前版本状态 |

## 📖 使用示例

### 版本锁定操作
```bash
# 锁定核心软件版本
sudo saltgoat version-lock lock

# 解锁软件版本
sudo saltgoat version-lock unlock

# 显示锁定的软件包
sudo saltgoat version-lock show

# 检查软件版本状态
sudo saltgoat version-lock status
```

## 🔒 锁定策略

### ✅ 锁定的核心软件

| 软件 | 目标版本 | 锁定包名 | 说明 |
|------|----------|----------|------|
| **Nginx** | 1.29.1+ModSecurity | 源码编译 | 自定义编译，版本固定 |
| **Percona** | 8.4 | percona-server-* | MySQL兼容数据库 |
| **PHP** | 8.3 | php-* | Web开发语言 |
| **RabbitMQ** | 4.1 | rabbitmq-server, erlang* | 消息队列 |
| **OpenSearch** | 2.19 | opensearch* | 搜索引擎 |
| **Valkey** | 8 | valkey* | Redis兼容缓存 |
| **Varnish** | 7.6 | varnish* | HTTP缓存 |
| **Composer** | 2.8 | 全局安装 | PHP依赖管理 |

### 🔄 允许更新的软件

- **系统内核** - 安全补丁更新
- **系统工具** - 其他非核心软件
- **安全补丁** - 系统安全更新
- **开发工具** - 非生产环境工具

## 📊 状态检查

### 版本状态显示
```bash
sudo saltgoat version-lock status
```

输出示例：
```
==========================================
[INFO] 检查核心LEMP软件版本状态...
==========================================
[SUCCESS] Nginx: nginx/1.29.1+ModSecurity (源码编译，版本固定)
[SUCCESS] Percona: 8.4.6-6 (目标: 8.4)
[SUCCESS] PHP: 8.4.13 (目标: 8.3)
[SUCCESS] Valkey: 8.0.5 (目标: 8)
[SUCCESS] RabbitMQ: 4.1.4 (目标: 4.1)
[WARNING] OpenSearch: 未安装
[SUCCESS] Varnish: 7.1.1 (目标: 7.6)
[SUCCESS] Composer: 2.8.12 (目标: 2.8)
==========================================
[INFO] 版本锁定状态:
[SUCCESS] 已锁定 11 个软件包
==========================================
[INFO] 锁定策略:
[INFO] ✅ 锁定: Nginx, Percona, PHP, RabbitMQ, OpenSearch, Valkey, Varnish, Composer
[INFO] 🔄 允许更新: 系统内核、安全补丁、其他工具软件
```

### 锁定包显示
```bash
sudo saltgoat version-lock show
```

输出示例：
```
==========================================
[INFO] 当前锁定的软件版本:
==========================================
[SUCCESS] php-common: 2:96+ubuntu24.04.1+deb.sury.org+1
[SUCCESS] php-mysql: 2:8.4+96+ubuntu24.04.1+deb.sury.org+1
[SUCCESS] percona-server-server: 8.4.6-6-1.noble
[SUCCESS] percona-server-client: 8.4.6-6-1.noble
[SUCCESS] percona-server-common: 8.4.6-6-1.noble
[SUCCESS] mysql-common: 5.8+1.1.0build1
[SUCCESS] opensearch: 2.19.3
[SUCCESS] varnish: 7.1.1-1.1ubuntu1
==========================================
```

## 🔧 配置管理

### 自动配置文件
版本锁定模块会自动创建配置文件：
- **位置**: `/etc/saltgoat/version-lock.conf`
- **内容**: 锁定时间、软件版本、锁定原因、注意事项

### 配置文件示例
```bash
# SaltGoat 版本锁定配置
# 此文件用于记录锁定的软件版本

# 锁定时间
LOCK_DATE=2025-01-21 15:30:00

# 核心LEMP软件版本 (需要锁定)
NGINX_VERSION=nginx/1.29.1
PERCONA_VERSION=8.4.6-6
PHP_VERSION=8.4.13
VALKEY_VERSION=8.0.5
RABBITMQ_VERSION=4.1.4
OPENSEARCH_VERSION=2.19.3
VARNISH_VERSION=7.1.1
COMPOSER_VERSION=2.8.12

# 锁定原因
LOCK_REASON="防止意外更新，保持LEMP环境稳定性"

# 注意事项
# 1. 如需更新软件版本，请先解锁: sudo saltgoat version-lock unlock
# 2. 更新后请重新锁定: sudo saltgoat version-lock lock
# 3. 定期检查安全更新: sudo saltgoat security-scan
```

## ⚠️ 注意事项

### 锁定前
- 确保当前软件版本稳定可用
- 备份重要配置文件
- 测试所有核心功能

### 锁定后
- 系统更新不会影响核心软件版本
- 安全补丁仍可正常更新
- 定期检查版本状态

### 解锁时
- 解锁后软件可能被意外更新
- 建议在维护窗口期间解锁
- 更新后立即重新锁定

## 🔗 相关功能

- **故障诊断**: `sudo saltgoat diagnose` - 系统故障诊断
- **性能分析**: `sudo saltgoat profile analyze` - 性能分析
- **安全扫描**: `sudo saltgoat security-scan` - 安全扫描

## 📁 文件结构

```
modules/version-lock/
├── version-lock.sh      # 主版本锁定脚本
└── README.md           # 本文档
```

## 📝 更新日志

- **v0.5.7** - 初始版本，支持8个核心软件版本锁定
- 智能锁定策略和安全更新支持
- 自动配置文件和状态管理

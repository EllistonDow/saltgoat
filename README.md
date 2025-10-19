# SaltGoat - LEMP Stack Automation

基于 Salt 的全自动 LEMP 安装项目，专为 Ubuntu 24.04 设计。使用 Salt 原生功能，提供完整的 LEMP 环境安装、配置和管理功能。

## 🎯 项目特点

> **项目状态**: ✅ **完成** - 所有功能已实现并测试通过

### ✅ 完全自动化
- 一键安装所有组件
- 自动配置服务和依赖关系
- 自动设置防火墙和安全规则

### ✅ Salt 原生功能
- **Salt Pillars**：配置数据管理
- **Salt Grains**：系统信息检测
- **Salt States**：状态管理
- **Salt CLI**：命令行参数传递
- **无外部依赖**：不需要 .env 文件

### ✅ 智能内存检测
- 自动检测服务器内存并调整配置
- 支持 64GB/128GB/256GB 服务器
- 动态优化 PHP、MySQL、OpenSearch、RabbitMQ 配置

### ✅ 安全优先
- 内置 ModSecurity Web 应用防火墙
- Fail2ban 自动防护
- 强密码要求和安全配置
- UFW 防火墙自动配置

## 系统要求

- Ubuntu 24.04
- x86 架构
- Root 权限

## 组件版本

| 组件 | 版本 | 说明 |
|------|------|------|
| Composer | 2.8 | PHP 依赖管理 |
| OpenSearch | 2.19 | 搜索引擎 (可选) |
| Percona | 8.4 | MySQL 数据库 |
| PHP | 8.3 | PHP 运行环境 |
| RabbitMQ | 4.1 | 消息队列 (可选) |
| Valkey | 8 | Redis 替代 (可选) |
| Varnish | 7.6 | HTTP 缓存 (可选) |
| Nginx | 1.29.1+ModSecurity | Web 服务器 |
| Fail2ban | Latest | 安全防护 (可选) |
| Webmin | Latest | Web 管理界面 (可选) |
| phpMyAdmin | Latest | MySQL 管理界面 (可选) |
| Certbot | Latest | SSL 证书管理 (可选) |

## 🚀 快速开始

### 1. 基础安装（Salt 原生方式）
```bash
# 设置密码并安装所有组件（推荐）
sudo ./saltgoat install all --mysql-password 'MyPass123!' --valkey-password 'Valkey123!' --rabbitmq-password 'RabbitMQ123!' --webmin-password 'Webmin123!' --phpmyadmin-password 'phpMyAdmin123!'

# 或者分步安装
sudo ./saltgoat install core --mysql-password 'MyPass123!'
sudo ./saltgoat install optional --valkey-password 'Valkey123!' --rabbitmq-password 'RabbitMQ123!'
```

### 2. Magento 优化（智能检测）
```bash
# 使用 Salt 原生方式优化
sudo ./saltgoat optimize magento
```

### 3. 服务状态检查
```bash
# 检查所有服务状态
sudo ./saltgoat status

# 查看组件版本信息
sudo ./saltgoat versions

# 查看配置的密码
sudo ./saltgoat passwords
```

### 4. 多站点管理
```bash
# 创建新站点数据库
sudo ./manage-mysql.sh create mysite mypassword

# 创建新站点 Nginx 配置
sudo ./manage-nginx.sh create mysite example.com

# 创建新站点 RabbitMQ 用户
sudo ./manage-rabbitmq.sh create mysite mypassword
```

## 多站点管理

SaltGoat 支持多站点环境，提供专门的管理脚本：

### 数据库管理
```bash
# 创建站点数据库和用户
sudo ./manage-mysql.sh create mysite mypassword

# 列出所有站点
sudo ./manage-mysql.sh list

# 备份站点数据库
sudo ./manage-mysql.sh backup mysite

# 删除站点
sudo ./manage-mysql.sh delete mysite
```

### RabbitMQ 管理
```bash
# 创建站点用户和虚拟主机
sudo ./manage-rabbitmq.sh create mysite mypassword

# 列出所有站点
sudo ./manage-rabbitmq.sh list

# 设置用户权限
sudo ./manage-rabbitmq.sh set-permissions mysite mysite

# 删除站点
sudo ./manage-rabbitmq.sh delete mysite
```

### Nginx 管理
```bash
# 创建站点配置
sudo ./manage-nginx.sh create mysite example.com

# 列出所有站点
sudo ./manage-nginx.sh list

# 添加 SSL 证书
sudo ./manage-nginx.sh add-ssl mysite example.com

# 删除站点
sudo ./manage-nginx.sh delete mysite
```

## 目录结构

```
saltgoat/
├── README.md              # 项目说明
├── saltgoat               # SaltGoat 主安装脚本
├── manage-mysql.sh        # MySQL 多站点管理
├── manage-rabbitmq.sh     # RabbitMQ 多站点管理
├── manage-nginx.sh        # Nginx 多站点管理
├── salt/
│   ├── top.sls           # Salt 主配置文件
│   ├── pillar/
│   │   └── lemp.sls      # Pillar 数据配置
│   └── states/
│       ├── core/         # 核心组件 states
│       ├── optional/     # 可选组件 states
│       └── common/       # 通用 states
├── SALT_NATIVE.md         # Salt 原生功能说明
├── SIMPLE_GUIDE.md        # 简化使用指南
└── PROJECT_SUMMARY.md     # 项目总结
```

## Magento 2.4.8 优化支持

SaltGoat 完全支持 Magento 2.4.8 的官方推荐配置优化，基于 Salt States 实现：

### Magento 环境优化

```bash
# 使用 Salt 原生方式优化（推荐）
sudo ./saltgoat optimize magento
```

**特点：**
- ✅ 与 SaltGoat 项目架构完全一致
- ✅ 利用 Salt 的状态管理和幂等性
- ✅ 支持自动内存检测和动态配置
- ✅ 配置变更可被 Salt 跟踪
- ✅ 集成内存监控和自动清理

### Magento 官方推荐配置

- **PHP 8.3**: 2G 内存限制，OPcache 512M
- **MySQL 8.4**: 2G InnoDB 缓冲池，500 最大连接
- **Valkey 8**: 1GB 内存，allkeys-lru 策略
- **OpenSearch 2.19**: 30% 索引缓冲区，10% 查询缓存
- **RabbitMQ 4.1**: 60% 内存高水位，2.0 磁盘限制
- **Nginx 1.29.1**: 自动工作进程，2048 连接，Gzip 压缩

## 📊 智能配置示例

SaltGoat 支持自动检测服务器内存并调整配置：

| 你的服务器 | 自动检测结果 | 优化配置 |
|------------|--------------|----------|
| **64GB** | Medium 级别 | PHP 2G, MySQL 16G, Valkey 1GB, OpenSearch 8G, RabbitMQ 1G |
| **128GB** | High 级别 | PHP 3G, MySQL 32G, Valkey 2GB, OpenSearch 16G, RabbitMQ 2G |
| **256GB** | Enterprise 级别 | PHP 4G, MySQL 64G, Valkey 4GB, OpenSearch 32G, RabbitMQ 4G |

### 内存分配策略（优化后）

| 内存大小 | 配置级别 | PHP 内存 | MySQL 缓冲池 | Valkey 内存 | OpenSearch 堆内存 | RabbitMQ 内存 | 总使用率 |
|----------|----------|----------|--------------|-------------|------------------|---------------|----------|
| 256GB+   | Enterprise | 4G | 25% (64GB) | 4GB | 12.5% (32GB) | 4GB | ~40% |
| 128GB    | High | 3G | 25% (32GB) | 2GB | 12.5% (16GB) | 2GB | ~40% |
| 48GB+    | Medium | 2G | 25% (16GB) | 1GB | 12.5% (8GB) | 1GB | ~40% |
| 16GB+    | Standard | 1G | 20% (4GB) | 512MB | 12.5% (2GB) | 512MB | ~40% |
| <16GB    | Low | 512M | 15% (2GB) | 256MB | 12.5% (1GB) | 256MB | ~40% |

## 🌐 访问地址

| 服务 | 地址 | 说明 |
|------|------|------|
| 网站 | http://your-server-ip | 默认网站 |
| PHP 信息 | http://your-server-ip/info.php | PHP 配置信息 |
| phpMyAdmin | http://your-server-ip/phpmyadmin | MySQL 管理 |
| Webmin | https://your-server-ip:10000 | 系统管理 |
| RabbitMQ | http://your-server-ip:15672 | 消息队列管理 |
| OpenSearch | http://your-server-ip:9200 | 搜索引擎 |

## 🎉 项目优势

1. **完全自动化**: 无需手动配置，一键完成所有安装
2. **Salt 原生**: 使用 Salt 内置功能，无外部依赖
3. **智能检测**: 自动检测内存并优化配置
4. **安全优先**: 内置多种安全防护机制
5. **生产就绪**: 优化的配置和性能设置
6. **易于维护**: 完整的文档和工具支持
7. **多站点支持**: 专门的管理脚本支持多站点环境

## 📁 目录结构

```
saltgoat/
├── README.md              # 项目说明（本文档）
├── saltgoat               # SaltGoat 主安装脚本
├── manage-mysql.sh        # MySQL 多站点管理
├── manage-rabbitmq.sh     # RabbitMQ 多站点管理
├── manage-nginx.sh        # Nginx 多站点管理
├── salt/
│   ├── top.sls           # Salt 主配置文件
│   ├── pillar/
│   │   └── lemp.sls      # Pillar 数据配置
│   └── states/
│       ├── core/         # 核心组件 states
│       ├── optional/     # 可选组件 states
│       └── common/       # 通用 states
└── PROJECT_SUMMARY.md     # 项目总结
```

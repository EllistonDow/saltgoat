# SaltGoat - LEMP Stack Automation

**版本**: v0.6.1 | **状态**: ✅ 生产就绪

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
- **环境配置**：支持 .env 文件和命令行参数

### ✅ 模块化架构
- **核心模块**：系统安装和基础配置
- **服务模块**：Nginx、MySQL、Redis、RabbitMQ 等
- **监控模块**：系统监控和性能分析
- **维护模块**：系统更新、清理、健康检查
- **报告模块**：多格式报告生成
- **自动化模块**：脚本和任务管理

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

### 方式一：系统安装（推荐）

```bash
# 克隆项目
git clone https://github.com/EllistonDow/saltgoat.git
cd saltgoat

# 安装到系统路径（无需 ./ 和 sudo）
sudo ./saltgoat system install

# 重新加载环境
source ~/.bashrc

# 现在可以直接使用
saltgoat install all --mysql-password 'MyPass123!' --valkey-password 'Valkey123!' --rabbitmq-password 'RabbitMQ123!' --webmin-password 'Webmin123!' --phpmyadmin-password 'phpMyAdmin123!'

# SSH 端口检测（可选）
saltgoat system ssh-port
```

### 方式二：直接使用

```bash
# 克隆项目
git clone https://github.com/EllistonDow/saltgoat.git
cd saltgoat

# 直接运行（需要 ./ 和 sudo）
sudo ./saltgoat install all --mysql-password 'MyPass123!' --valkey-password 'Valkey123!' --rabbitmq-password 'RabbitMQ123!' --webmin-password 'Webmin123!' --phpmyadmin-password 'phpMyAdmin123!'
```

### 1. 基础安装（推荐方式）

#### 方式A：使用 .env 文件（推荐）
```bash
# 1. 创建环境配置文件
saltgoat env create

# 2. 编辑密码
nano .env

# 3. 安装所有组件
saltgoat install all
```

#### 方式B：命令行参数（传统方式）
```bash
# 设置密码并安装所有组件
saltgoat install all --mysql-password 'MyPass123!' --valkey-password 'Valkey123!' --rabbitmq-password 'RabbitMQ123!' --webmin-password 'Webmin123!' --phpmyadmin-password 'phpMyAdmin123!'

# 或者分步安装
saltgoat install core --mysql-password 'MyPass123!'
saltgoat install optional --valkey-password 'Valkey123!' --rabbitmq-password 'RabbitMQ123!'
```

#### 方式C：混合方式（最灵活）
```bash
# 使用 .env 文件 + 命令行参数覆盖
saltgoat install all --mysql-password 'NewPassword123!'
```

**安装方式对比：**

| 方式 | 优势 | 适用场景 |
|------|------|----------|
| **.env 文件** | ✅ 配置持久化<br>✅ 版本控制友好<br>✅ 密码安全 | 生产环境<br>团队协作<br>重复部署 |
| **命令行参数** | ✅ 一次性使用<br>✅ 脚本自动化<br>✅ 临时配置 | 测试环境<br>CI/CD<br>快速部署 |
| **混合方式** | ✅ 灵活性最高<br>✅ 配置覆盖<br>✅ 最佳实践 | 复杂环境<br>多环境部署 |

**优先级：** 命令行参数 > .env 文件 > 默认值

### 2. Magento 优化（智能检测）
```bash
# 使用 Salt 原生方式优化
saltgoat optimize magento
```

### 3. 环境配置管理
```bash
# 创建环境配置文件
saltgoat env create

# 查看当前环境配置
saltgoat env show

# 加载指定环境配置文件
saltgoat env load /path/to/custom.env
```

### 4. 服务状态检查
```bash
# 检查所有服务状态
saltgoat status

# 查看组件版本信息
saltgoat versions

# 查看配置的密码
saltgoat passwords
```

### 5. 别名设置（可选）

SaltGoat 支持设置别名，让您使用更简短的名字：

#### 快速设置（推荐）
```bash
# 运行快速别名设置脚本
./scripts/quick-alias.sh
```

#### 手动设置
```bash
# 临时别名（当前会话有效）
alias sg='saltgoat'
alias goat='saltgoat'

# 永久别名（添加到 ~/.bashrc）
echo "alias sg='/usr/local/bin/saltgoat'" >> ~/.bashrc
echo "alias goat='/usr/local/bin/saltgoat'" >> ~/.bashrc
source ~/.bashrc
```

#### 高级别名管理
```bash
# 使用别名管理脚本
./scripts/setup-aliases.sh --add sg
./scripts/setup-aliases.sh --add goat
./scripts/setup-aliases.sh --list
./scripts/setup-aliases.sh --remove sg
```

**常用别名建议：**
- `sg` - 短别名
- `goat` - 动物别名
- `salt` - Salt 别名
- `lemp` - LEMP 别名

**使用方法：**
```bash
sg help
goat status
salt versions
lemp install all
```

**⚠️ 注意事项：**
- 避免使用与系统用户名相同的别名（如 `doge`）
- 避免使用系统命令名作为别名
- 别名管理脚本会自动检测冲突并提供建议

### 6. SaltGUI Web 界面

SaltGoat 支持 SaltGUI Web 界面，让您通过浏览器管理 SaltStack：

#### 安装和配置
```bash
# 安装 SaltGUI
saltgoat saltgui install

# 启动 SaltGUI
saltgoat saltgui start

# 检查状态
saltgoat saltgui status
```

#### 访问 SaltGUI
- **访问地址**: http://localhost:3333
- **配置文件**: /etc/saltgui/config.json
- **日志文件**: /var/log/saltgui/saltgui.log

#### SaltGUI 功能
- ✅ **可视化状态管理**：查看所有 minion 状态
- ✅ **远程命令执行**：通过 Web 界面执行 Salt 命令
- ✅ **实时监控**：监控系统状态和性能
- ✅ **日志查看**：查看 Salt 执行日志
- ✅ **配置管理**：管理 Salt 配置文件

#### 管理命令
```bash
saltgoat saltgui install    # 安装 SaltGUI
saltgoat saltgui start      # 启动 SaltGUI
saltgoat saltgui stop       # 停止 SaltGUI
saltgoat saltgui restart    # 重启 SaltGUI
saltgoat saltgui status     # 检查状态
saltgoat saltgui uninstall  # 卸载 SaltGUI
```

### 7. 多站点管理
```bash
# 创建新站点数据库
saltgoat mysql create hawkmage hawk 'hawk.2010'

# 创建新站点 Nginx 配置（推荐使用 /var/www）
saltgoat nginx create mysite example.com

# 创建新站点 RabbitMQ 用户
saltgoat rabbitmq create mysite mypassword

# 站点权限管理（迁移站点必备）
saltgoat permissions detect /var/www/mysite
saltgoat permissions set /var/www/mysite magento
```

### 5. 定时任务管理
```bash
# 启用 SaltGoat 定时任务（推荐）
saltgoat schedule enable

# 查看定时任务状态
saltgoat schedule status

# 列出所有定时任务
saltgoat schedule list

# 测试定时任务配置
saltgoat schedule test
```

## 🔒 SSH 端口安全检测

SaltGoat 内置智能 SSH 端口检测功能，确保防火墙配置不会意外锁定 SSH 连接：

### 自动检测
安装过程中会自动检测当前 SSH 端口并添加到 UFW 规则中：
- 支持自定义 SSH 端口（如 18712）
- 自动添加到防火墙允许列表
- 防止安装后无法 SSH 连接

### 手动检测
```bash
# 检测当前 SSH 端口和 UFW 状态
saltgoat system ssh-port
```

### 检测方法
1. **ss 命令**: 检测当前监听的 SSH 端口
2. **netstat 命令**: 备用检测方法
3. **配置文件**: 读取 `/etc/ssh/sshd_config`
4. **默认端口**: 如果无法检测，使用默认端口 22

### 安全提示
- 安装前建议先检测 SSH 端口
- 确保当前 SSH 连接不会被中断
- 支持 IPv4 和 IPv6 双栈

## 🆕 新功能模块

### Magento工具集
```bash
# 安装Magento开发工具
saltgoat magetools install n98-magerun2
saltgoat magetools install phpunit
saltgoat magetools install xdebug

# 缓存管理
saltgoat magetools cache clear
saltgoat magetools cache status

# 索引管理
saltgoat magetools index reindex

# 性能分析
saltgoat magetools performance

# 查看帮助
saltgoat magetools help
```

### 系统维护模块
```bash
# 系统更新管理
saltgoat maintenance update check
saltgoat maintenance update upgrade

# 服务管理
saltgoat maintenance service restart nginx
saltgoat maintenance service status mysql

# 系统清理
saltgoat maintenance cleanup all
saltgoat maintenance cleanup logs

# 磁盘管理
saltgoat maintenance disk usage
saltgoat maintenance disk find-large 100M

# 系统健康检查
saltgoat maintenance health
```

### 报告生成模块
```bash
# 生成系统健康报告
saltgoat reports system text
saltgoat reports system json
saltgoat reports system html

# 生成性能分析报告
saltgoat reports performance text

# 生成安全评估报告
saltgoat reports security text

# 报告管理
saltgoat reports list all
saltgoat reports cleanup 30
```

### 自动化任务管理
```bash
# 脚本管理
saltgoat automation script create my-script
saltgoat automation script list
saltgoat automation script run my-script

# 任务调度
saltgoat automation job create my-job "0 2 * * *" my-script
saltgoat automation job enable my-job
saltgoat automation job list

# 预设模板
saltgoat automation templates system-update
saltgoat automation templates backup-cleanup
saltgoat automation templates log-rotation
saltgoat automation templates security-scan

# 日志管理
saltgoat automation logs list
saltgoat automation logs view my-script_20251020.log
```

### 数据库管理优化
```bash
# MySQL 便捷功能（Salt 原生）
saltgoat database mysql create testdb testuser 'testpass123'
saltgoat database mysql list
saltgoat database mysql backup testdb
saltgoat database mysql delete testdb

# 通用数据库功能
saltgoat database status mysql
saltgoat database test-connection mysql
saltgoat database performance mysql
saltgoat database user mysql create testuser password123
```

## Salt Schedule 定时任务

SaltGoat 使用 Salt 的 Schedule 功能替代传统的 crontab，提供更强大的定时任务管理：

### 优势对比

| 特性 | Crontab | Salt Schedule |
|------|---------|---------------|
| **集中管理** | ❌ 分散 | ✅ 统一 |
| **版本控制** | ❌ 困难 | ✅ Git 友好 |
| **幂等性** | ❌ 无 | ✅ 内置 |
| **状态跟踪** | ❌ 无 | ✅ 完整 |
| **依赖管理** | ❌ 无 | ✅ 支持 |
| **随机延迟** | ❌ 无 | ✅ splay 支持 |
| **条件执行** | ❌ 有限 | ✅ 丰富 |
| **失败重试** | ❌ 无 | ✅ 支持 |

### 内置定时任务

- **内存监控**: 每5分钟检查系统内存使用
- **系统更新**: 每周日凌晨3点自动更新
- **日志清理**: 每周日凌晨1点清理旧日志
- **数据库备份**: 每天凌晨2点备份数据库
- **服务健康检查**: 每10分钟检查服务状态
- **磁盘空间检查**: 每6小时检查磁盘使用
- **安全更新检查**: 每周一凌晨4点检查安全更新

## 多站点管理

SaltGoat 支持多站点环境，提供专门的管理脚本：

### 数据库管理
```bash
# 创建站点数据库和用户
saltgoat mysql create hawkmage hawk 'hawk.2010'

# 列出所有站点
saltgoat mysql list

# 备份站点数据库
saltgoat mysql backup hawkmage

# 删除站点
saltgoat mysql delete hawkmage
```

### RabbitMQ 管理
```bash
# 创建站点用户和虚拟主机
saltgoat rabbitmq create mysite mypassword

# 列出所有站点
saltgoat rabbitmq list

# 设置用户权限
saltgoat rabbitmq set-permissions mysite mysite

# 删除站点
saltgoat rabbitmq delete mysite
```

### Nginx 管理
```bash
# 创建站点配置（推荐使用 /var/www，自动支持双域名）
saltgoat nginx create mysite example.com

# 创建站点到自定义路径
saltgoat nginx create mysite example.com /home/user/mysite

# 列出所有站点
saltgoat nginx list

# 添加 SSL 证书（自动支持双域名）
saltgoat nginx add-ssl mysite example.com

# 删除站点
saltgoat nginx delete mysite
```

#### 双域名支持

SaltGoat 自动支持双域名配置：
- **主域名**：`example.com`
- **WWW 域名**：`www.example.com`
- **自动重定向**：`example.com` → `https://www.example.com`
- **SSL 证书**：同时支持两个域名的 SSL 证书

**访问流程**：
1. `http://example.com` → `https://www.example.com`
2. `http://www.example.com` → `https://www.example.com`
3. `https://example.com` → `https://www.example.com`
4. `https://www.example.com` → 正常访问

### 站点权限管理
```bash
# 检测站点类型（自动识别 Magento/WordPress/通用）
saltgoat permissions detect /var/www/mysite

# 设置站点权限（自动检测类型）
saltgoat permissions set /var/www/mysite

# 手动指定站点类型
saltgoat permissions set /var/www/mysite magento
saltgoat permissions set /var/www/mysite wordpress
saltgoat permissions set /var/www/mysite generic
```

#### 权限管理说明

**推荐使用 `/var/www` 目录**：
- ✅ 标准位置，权限简单
- ✅ `www-data:www-data` 所有权
- ✅ 无用户隔离问题
- ✅ 安全性好，维护方便

**支持的站点类型**：
- **Magento 2**：自动设置 `var/`, `pub/media/`, `pub/static/`, `generated/`, `app/etc/` 等目录的写入权限
- **WordPress**：自动设置 `wp-content/uploads/`, `wp-content/cache/` 等目录权限
- **通用站点**：设置标准 Web 服务器权限，支持 `uploads/`, `files/`, `media/` 等上传目录

**迁移站点流程**：
1. 将站点文件复制到 `/var/www/sitename/`
2. `saltgoat permissions detect /var/www/sitename` - 检测类型
3. `saltgoat permissions set /var/www/sitename` - 设置权限
4. `saltgoat nginx create sitename domain.com` - 创建 Nginx 配置

## 目录结构

```
saltgoat/
├── README.md              # 项目说明
├── saltgoat               # SaltGoat 一体化管理脚本
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
saltgoat optimize magento
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
| **Prometheus** | **http://your-server-ip:9090** | **监控数据收集** |
| **Grafana** | **http://your-server-ip:3000** | **监控仪表板** |
| **Node Exporter** | **http://your-server-ip:9100/metrics** | **系统指标** |

## 🆕 v0.5.0 新功能

### 📊 监控集成系统
```bash
# 安装Prometheus监控
saltgoat monitoring prometheus

# 安装Grafana仪表板
saltgoat monitoring grafana

# 查看监控集成帮助
saltgoat help monitoring
```

### 🛡️ 防火墙自动配置
- 自动检测UFW、Firewalld、iptables
- 智能放行监控服务端口
- 跨平台防火墙兼容

### 📋 状态管理
```bash
# 查看所有可用状态
saltgoat state list

# 应用特定状态
saltgoat state apply nginx

# 回滚状态
saltgoat state rollback nginx
```

### 🔍 代码质量工具
```bash
# 代码检查
saltgoat lint [file]

# 代码格式化
saltgoat format [file]

# 安全扫描
saltgoat security-scan
```

## 🎉 项目优势

1. **完全自动化**: 无需手动配置，一键完成所有安装
2. **Salt 原生**: 使用 Salt 内置功能，无外部依赖
3. **智能检测**: 自动检测内存并优化配置
4. **安全优先**: 内置多种安全防护机制
5. **生产就绪**: 优化的配置和性能设置
6. **易于维护**: 完整的文档和工具支持
7. **多站点支持**: 专门的管理脚本支持多站点环境
8. **监控集成**: 完整的Prometheus+Grafana监控方案
9. **防火墙管理**: 智能防火墙配置和状态检查

## 📁 目录结构

```
saltgoat/
├── README.md              # 项目说明（本文档）
├── saltgoat               # SaltGoat 主入口脚本（模块化）
├── lib/                   # 公共库
│   ├── logger.sh         # 日志函数库
│   ├── utils.sh          # 工具函数库
│   └── config.sh         # 配置管理库
├── core/                  # 核心功能模块
│   ├── install.sh        # 安装管理
│   ├── system.sh         # 系统管理
│   └── optimize.sh       # 优化功能
├── services/              # 服务管理模块
│   ├── mysql.sh          # MySQL 管理
│   ├── nginx.sh          # Nginx 管理
│   └── rabbitmq.sh       # RabbitMQ 管理
├── monitoring/            # 监控功能模块
│   ├── memory.sh         # 内存监控
│   └── schedule.sh       # 定时任务
├── salt/                  # Salt 配置文件
│   ├── top.sls           # Salt 主配置文件
│   ├── pillar/
│   │   └── lemp.sls      # Pillar 数据配置
│   └── states/
│       ├── core/         # 核心组件 states
│       ├── optional/     # 可选组件 states
│       └── common/       # 通用 states
└── templates/             # 模板文件（待扩展）
```

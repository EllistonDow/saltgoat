# SaltGoat 安装指南

## 🎯 跨服务器一致性安装

SaltGoat 设计为具备跨服务器一致性，确保在不同服务器上安装后配置完全相同。

### 📋 安装前准备

#### 1. 系统要求
- **操作系统**: Ubuntu 24.04 LTS
- **架构**: x86_64
- **内存**: 最少 2GB，推荐 4GB+
- **磁盘**: 最少 20GB 可用空间
- **网络**: 需要互联网连接

#### 2. 用户权限
```bash
# 确保有sudo权限
sudo -l
```

### 🚀 标准安装流程

#### 1. 克隆项目
```bash
# 克隆到任意目录（推荐 /opt/saltgoat）
sudo git clone https://github.com/EllistonDow/saltgoat.git /opt/saltgoat
cd /opt/saltgoat
```

#### 2. 配置 Pillar（推荐）
```bash
# 生成默认模板（包含随机密码，执行前可确认/覆盖）
saltgoat pillar init

# 注意：模板中的随机密码仅供首次安装使用，请按照安全要求修改并妥善保存。

# 或手动编辑 Pillar 文件
nano salt/pillar/saltgoat.sls

# 保存后刷新 Pillar（Salt 会在安装过程中自动刷新，此步骤可选）
saltgoat pillar refresh
```

#### Pillar 管理命令
- `saltgoat pillar init`：生成 `salt/pillar/saltgoat.sls` 模板，自动写入随机密码与默认通知邮箱。
- `saltgoat pillar show`：以只读方式输出当前 Pillar 内容，便于安装前核对。
- `saltgoat pillar refresh`：执行 `saltutil.refresh_pillar` 立即刷新缓存，确保后续 `saltgoat install` 使用最新值。

> Pillar 文件默认权限为 `600`（root 所有），请在编辑后保持该权限；如需自定义其他机密信息，可在同目录新增 `*.sls` 并在 `salt/pillar/top.sls` 中引用。

#### 3. 系统安装
```bash
# 安装SaltGoat到系统
sudo ./saltgoat system install

# 安装所有组件
sudo saltgoat install all

# 可选：安装完成后自动执行 Magento 优化
sudo saltgoat install all --optimize-magento
sudo saltgoat install all --optimize-magento-profile high --optimize-magento-site mystore
```

### 🔧 一致性保证机制

#### 1. 自动路径检测
SaltGoat 会自动检测以下路径：
- **Nginx**: `/etc/nginx/nginx.conf`
- **PHP**: 自动检测版本 (8.3, 8.2, 8.1, 8.0, 7.4)
- **MySQL**: `/etc/mysql/mysql.conf.d/lemp.cnf` 或 `/etc/mysql/my.cnf`
- **Valkey**: `/etc/valkey/valkey.conf`

#### 2. 环境检测
- **防火墙**: 自动检测 UFW、Firewalld、iptables
- **系统资源**: 自动检测内存、CPU、磁盘
- **网络配置**: 自动获取服务器IP地址

#### 3. 配置管理
- **Pillar 文件**: 通过 `salt/pillar/*.sls` 管理凭据与区域设置
- **命令行覆盖**: 安装命令支持 `--mysql-password` 等参数临时覆盖
- **Salt 状态**: 使用 Salt 状态文件确保一致性

### 📊 验证安装一致性

#### 运行一致性测试
```bash
# 运行完整一致性测试
sudo saltgoat test consistency

# 或直接运行测试脚本
bash tests/consistency-test.sh
```

#### 测试结果示例
```
SaltGoat 配置一致性测试
==========================================
1. 路径检测测试:
----------------------------------------
  Nginx: /etc/nginx/nginx.conf ✅
  PHP: 8.3 (/etc/php/8.3/fpm/php.ini) ✅
  MySQL: /etc/mysql/mysql.conf.d/lemp.cnf ✅

2. 防火墙检测测试:
----------------------------------------
  UFW: 已安装 ✅
  状态: Status: active

3. 系统资源检测测试:
----------------------------------------
  总内存: 8GB
  CPU核心: 4个
  根分区使用率: 25%
  服务器IP: 192.168.1.100

4. 服务检测测试:
----------------------------------------
  nginx: 运行中 ✅
  mysql: 运行中 ✅
  php8.3-fpm: 运行中 ✅
  valkey: 运行中 ✅
  opensearch: 运行中 ✅
  rabbitmq: 运行中 ✅

5. 配置一致性测试:
----------------------------------------
  SaltGoat版本: 0.5.1 ✅
  nginx.conf: 644 (root:root) ✅
  php.ini: 644 (root:root) ✅
  lemp.cnf: 644 (root:root) ✅
  valkey.conf: 644 (valkey:valkey) ✅
```

### 🌐 访问地址

安装完成后，以下服务将自动配置：

| 服务 | 地址 | 说明 |
|------|------|------|
| 网站 | http://your-server-ip | 默认网站 |
| PHP 信息 | http://your-server-ip/info.php | PHP 配置信息 |
| phpMyAdmin | http://your-server-ip:8080 | MySQL 管理 |
| Webmin | https://your-server-ip:10000 | 系统管理 |
| RabbitMQ | http://your-server-ip:15672 | 消息队列管理 |
| OpenSearch | http://your-server-ip:9200 | 搜索引擎 |
| Prometheus | http://your-server-ip:9090 | 监控数据收集 |
| Grafana | http://your-server-ip:3000 | 监控仪表板 |
| Node Exporter | http://your-server-ip:9100/metrics | 系统指标 |
| Cockpit | https://your-server-ip:9091 | 系统管理面板 |
| Adminer | http://your-server-ip:8081 | 数据库管理面板 |
| Uptime Kuma | http://your-server-ip:3001 | 服务监控面板 |

### 🔒 安全配置

#### 密码管理
- `saltgoat passwords`：读取 Pillar 与实际配置，汇总 MySQL、Valkey、RabbitMQ、Webmin、phpMyAdmin 的当前密码。
- `saltgoat passwords --refresh`：在编辑 Pillar 后刷新缓存并重新应用核心服务状态，确保新密码立即生效。
- 安装完成的摘要同样会提示 `versions`、`status`、`passwords` 三个常用命令，建议记录初始输出。

```bash
# 查看当前凭据
saltgoat passwords

# 编辑 pillar 后重新渲染密码相关状态
saltgoat passwords --refresh
```

#### 修改密码
```bash
# 修改 MySQL 密码（交互式）
saltgoat database mysql password

# 其他服务推荐在 Pillar 中编辑后执行 --refresh
nano salt/pillar/saltgoat.sls
saltgoat passwords --refresh
```

### 🎛️ 管理面板安装

SaltGoat 支持多种管理面板，可以根据需要选择安装：

#### Cockpit 系统管理面板
```bash
# 安装 Cockpit
saltgoat cockpit install

# 查看状态
saltgoat cockpit status

# 配置防火墙
saltgoat cockpit config firewall
```

#### Adminer 数据库管理面板
```bash
# 安装 Adminer
saltgoat adminer install

# 查看状态
saltgoat adminer status

# 配置安全设置
saltgoat adminer security
```

#### Uptime Kuma 监控面板
```bash
# 安装 Uptime Kuma
saltgoat uptime-kuma install

# 查看状态
saltgoat uptime-kuma status

# 配置 SaltGoat 服务监控
saltgoat uptime-kuma monitor
```

### 🚨 故障排除

#### 1. 权限问题
```bash
# 检查sudo权限
sudo -l

# 重新安装系统权限
sudo saltgoat system install
```

#### 2. 服务状态检查
```bash
# 检查所有服务状态
saltgoat status

# 重启服务
sudo systemctl restart nginx mysql php8.3-fpm
```

#### 3. 配置验证
```bash
# 验证Nginx配置
sudo nginx -t

# 验证PHP配置
php -m

# 验证MySQL配置
sudo mysql -e "SELECT VERSION();"
```

### 📝 注意事项

1. **路径一致性**: SaltGoat使用动态路径检测，确保在不同安装位置都能正常工作
2. **配置模板**: 所有配置文件都使用模板化设计，确保一致性
3. **版本控制**: 使用Git标签管理版本，确保安装的是稳定版本
4. **环境隔离**: 每个服务器都有独立的环境配置

### 🎯 总结

SaltGoat 通过以下机制确保跨服务器一致性：

- ✅ **动态路径检测**: 自动适应不同的安装路径
- ✅ **环境变量管理**: 统一的配置管理机制
- ✅ **Salt状态文件**: 声明式配置确保一致性
- ✅ **自动检测**: 智能检测系统环境和资源
- ✅ **版本控制**: Git标签确保版本一致性

**无论在哪台服务器上安装，SaltGoat都会提供完全一致的LEMP环境！** 🎉

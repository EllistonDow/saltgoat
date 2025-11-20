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
sudo saltgoat pillar init

# 注意：模板中的随机密码仅供首次安装使用，请按照安全要求修改并妥善保存。

# 或手动编辑 Pillar 文件
nano salt/pillar/saltgoat.sls

# 保存后刷新 Pillar（Salt 会在安装过程中自动刷新，此步骤可选）
sudo saltgoat pillar refresh
```

> 💡 **自动兜底**：若跳过 `pillar init/refresh`，`sudo saltgoat install all` 会在首次运行时生成 `salt/pillar/secret/saltgoat.sls`（以及其他 `secret/*.sls`），写入随机强密码并自动刷新 Pillar。

#### Pillar 管理命令
- `sudo saltgoat pillar init`：生成 `salt/pillar/saltgoat.sls` 模板，自动写入随机密码与默认通知邮箱。
- `sudo saltgoat pillar show`：以只读方式输出当前 Pillar 内容，便于安装前核对。
- `sudo saltgoat pillar refresh`：执行 `saltutil.refresh_pillar` 立即刷新缓存，确保后续 `saltgoat install` 使用最新值。

> Pillar 文件默认权限为 `600`（root 所有），请在编辑后保持该权限；如需自定义其他机密信息，可在同目录新增 `*.sls` 并在 `salt/pillar/top.sls` 中引用。

#### 3. 系统安装
```bash
# 安装SaltGoat到系统
sudo saltgoat system install

# 安装所有组件
sudo saltgoat install all

# 可选：安装完成后自动执行 Magento 优化
sudo saltgoat install all --optimize-magento
sudo saltgoat install all --optimize-magento-profile high --optimize-magento-site mystore
```

安装流程会自动执行以下任务：

- 通过 Salt 官方 bootstrap 安装 `salt-master`/`salt-minion`（版本 3007.8），并写入 `file_client: local`、`state_queue: True` 等基础配置。
- 生成/更新 `salt/pillar/secret/*.sls` 并填入随机强密码，随后刷新 Pillar 缓存。
- 安装 Restic 0.16.3、Percona XtraBackup 8.4，启用 `saltgoat-restic-backup.timer` 与 `saltgoat-mysql-backup.timer`。
- 安装 `python3-pymysql` / `python3-mysqldb`，保证 Salt MySQL execution module 与 `saltgoat magetools mysql` 开箱即用。
- 应用 `optional.salt-beacons`/`optional.salt-reactor`，默认启用 CSP Level 3 与 ModSecurity Level 5。
- 自动执行 `saltgoat magetools schedule auto`、`saltgoat monitor auto-sites` 与 `saltgoat monitor enable-beacons`，并同步 Telegram 话题。

#### 4. （可选）重新应用事件驱动组件

`sudo saltgoat install all` 已自动安装/启用 Salt Master & Minion，并在收尾阶段执行了 `saltgoat monitor enable-beacons`。若后续修改 Pillar、需要重新下发 Beacon/Reactors 或在集中式 master 上部署，可手动重复以下命令：

```bash
sudo saltgoat monitor enable-beacons
sudo saltgoat monitor beacons-status
```

> **提示**：若在集中式环境运行多台 minion，可使用相同仓库在 master 上运行 `salt-run saltgoat.enable_beacons` 进行远程收敛；若缺少 Salt 服务，相关计划任务会直接报错以提示处理，而不再写入 Cron。

### 🛠 自动化脚本与计划任务

- `sudo saltgoat automation script <create|list|edit|run|delete>`：生成带日志模板的 Bash 脚本，默认写入 `/srv/saltgoat/automation/scripts/`。
- `sudo saltgoat automation job <create|list|enable|disable|run|delete>`：注册 Salt Schedule 任务（需 `salt-minion` 运行）；命令会在缺失 Minion 时立即报错，避免静默降级。
- `sudo saltgoat automation logs <list|view|tail|cleanup>`：查看与维护 `/srv/saltgoat/automation/logs/`。

命令执行前会自动调用 `saltutil.sync_modules`/`saltutil.sync_runners`，确保 `salt/_modules/saltgoat.py` 与 `salt/states/optional/automation/` 的最新逻辑立即生效。需要集中式下发时，可在 Salt Master 上使用 `salt-run saltgoat.automation_job_create tgt='minion-id' ...` 将同样的自动化策略推广到多台主机。

### 📈 部署 Matomo 分析平台

SaltGoat 自带 `analyse` 模块，用于快速部署 Matomo：

```bash
# 仅预览（test=True），不会改动系统
bash tests/test_analyse_state.sh

# 使用默认设置安装 Matomo，并创建数据库/用户
sudo saltgoat analyse install matomo --with-db

# 指定域名、数据库与管理员账户
sudo saltgoat analyse install matomo --with-db \
  --domain analytics.example.com \
  --db-name matomo_prod --db-user matomo_prod \
  --db-password 'StrongPass123!' \
  --db-provider existing

# 复用既有数据库管理员凭据
sudo saltgoat analyse install matomo --with-db \
  --db-admin-user saltuser --db-admin-password 'YourRootPass'
```

- 常用参数补充：
  - `--install-dir /path/to/matomo`：覆盖安装目录（同时写入 Pillar `matomo:install_dir`）。
  - `--php-socket /run/php/php8.3-fpm.sock`：指定 PHP-FPM 套接字。
  - `--owner www-data --group www-data`：自定义站点文件属主/属组。
  - `--db-provider existing|mariadb`：`existing` 复用当前 MySQL/Percona，`mariadb` 将尝试安装 MariaDB（若检测到已有 MySQL/Percona 会直接报错）。

- 若系统存在 `/etc/salt/mysql_saltuser.cnf`，CLI 会自动复用 `saltuser` 凭据。
- CLI 支持 `--domain`、`--install-dir`、`--with-db`、`--db-provider (existing|mariadb|percona)`、`--db-*` 系列参数，所有值都可以在 Pillar 中覆盖。
- 需要自定义管理账户时，请补充 `--db-admin-user/--db-admin-password`，并在 `salt/pillar/saltgoat.sls` 中持久化 `matomo:db.*` 配置。
- 部署完成后访问 `http://<域名>/` 完成 Matomo Web 安装；如需 HTTPS，可执行 `sudo saltgoat nginx add-ssl <域名> <email>`。
- 若自动生成数据库密码，会写入 `/var/lib/saltgoat/reports/matomo-db-password.txt`，请尽快同步到 Pillar 后删除该文件。

#### Matomo Pillar 示例

```yaml
matomo:
  install_dir: /var/www/matomo
  domain: analytics.example.com
  php_fpm_socket: /run/php/php8.3-fpm.sock
  owner: www-data
  group: www-data
  db:
    enabled: true
    provider: existing        # 可选：mariadb/percona
    name: matomo_prod
    user: matomo_prod
    password: 'ChangeMe!'
    host: localhost
    socket: /var/run/mysqld/mysqld.sock
    admin_user: saltuser
    admin_password: 'RootOrSaltUserPass'
```

保存后执行 `sudo saltgoat pillar refresh`，再运行 `sudo saltgoat analyse install matomo` 即可引用 Pillar 参数。

#### Magento 优化站点检测
- 运行 `sudo saltgoat optimize magento` 时，CLI 会在 `/var/www`、`/srv`、`/opt/magento` 下自动查找 `app/etc/env.php`，以推断站点根目录。
- 如果存在多个站点，需要使用 `--site <站点名称|绝对路径|env.php>` 明确指定目标，避免误修改配置。
- 自动检测结果会写入 `salt/pillar/magento-optimize.sls`，后续 Salt state 会根据 `detection_status` 决定是否继续执行或提示用户。

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

#### 自动化验证脚本
- `bash tests/test_analyse_state.sh`：对 `optional.analyse` 状态执行 `test=True` 渲染，验证 Matomo 相关 Pillar 是否有效。
- `bash tests/test_git_release.sh`：dry-run `saltgoat git push` 并确保不会修改版本文件或生成实际提交。
- `bash tests/test_salt_versions.sh`：收集 `salt-call test.versions_report` 与 `state.show_lowstate optional.analyse`，快速确认 Salt 运行环境。

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
- `sudo saltgoat passwords`：读取 Pillar 与实际配置，汇总 MySQL、Valkey、RabbitMQ、Webmin、phpMyAdmin 的当前密码。
- `sudo saltgoat passwords --refresh`：在编辑 Pillar 后刷新缓存并重新应用核心服务状态，确保新密码立即生效。
- 安装完成的摘要同样会提示 `versions`、`status`、`passwords` 三个常用命令，建议记录初始输出。

```bash
# 查看当前凭据
sudo saltgoat passwords

# 编辑 pillar 后重新渲染密码相关状态
sudo saltgoat passwords --refresh
```

### 🚀 Git 发布流程

SaltGoat 提供快捷发布命令，帮助保持版本与 Changelog 一致：

```bash
# 预览（不会修改仓库）
saltgoat git push --dry-run "准备发布摘要"

# 正式发布（默认补丁号 +0.0.1）
saltgoat git push "演进说明"

# 指定版本号
saltgoat git push 0.10.0 "Release notes"
```

- Dry-run 会显示预期版本、提交信息与当前差异，便于检查。
- 未提供版本号时会自动把 `SCRIPT_VERSION` 的补丁号 +1；传入版本号会进行 tag 冲突检查并在重复时提示退出。
- 未提供摘要时，命令会根据 `git diff --name-only` 自动生成“修改 N 个文件...”的说明，可用自定义文本覆盖。
- 发布失败时，可执行 `git tag -d vX.Y.Z && git reset --hard HEAD~1` 回滚标签与提交。

#### 修改密码
```bash
# 建议通过 Pillar 统一管理密码
nano salt/pillar/saltgoat.sls
sudo saltgoat passwords --refresh
```

### 🎛️ 管理面板安装

SaltGoat 支持多种管理面板，可以根据需要选择安装：

#### Cockpit 系统管理面板
```bash
# 安装 Cockpit
sudo saltgoat cockpit install

# 查看状态
sudo saltgoat cockpit status

# 配置防火墙
sudo saltgoat cockpit config firewall
```

#### Adminer 数据库管理面板
```bash
# 安装 Adminer
sudo saltgoat adminer install

# 查看状态
sudo saltgoat adminer status

# 配置安全设置
sudo saltgoat adminer security
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
sudo saltgoat status

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

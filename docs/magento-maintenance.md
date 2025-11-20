# SaltGoat Magento 2 维护系统文档

## 概述

SaltGoat Magento 2 维护系统提供了完整的自动化维护解决方案，包括日常维护、定时任务管理、健康检查等功能。系统采用 Salt 原生实现，完全符合 SaltGoat 的设计理念。

## 快速开始

```bash
# 安装 / 更新 Salt Schedule
sudo saltgoat magetools cron <site> install

# 检查计划任务与 Salt Minion 状态
sudo saltgoat magetools cron <site> status

# 立即触发一次例行维护，用于验证
sudo saltgoat magetools cron <site> test
```

> `salt-minion` 是 Salt Schedule 的唯一依赖：执行 `install` 前请确保 `systemctl is-active salt-minion` 返回 `active`，否则任务将无法下发。

## 功能特性

### 🔧 维护管理
- **维护模式控制** - 启用/禁用维护模式
- **日常维护** - 缓存清理、索引重建、会话清理、日志清理
- **每周维护** - 备份、日志轮换、Valkey 清空（可选）、性能检查
- **每月维护** - 完整部署流程（维护模式→清理→升级→编译→部署→索引→禁用维护→清理缓存）
- **健康检查** - Magento状态、数据库连接、缓存状态、索引状态

### ⏰ 定时任务管理
- **Salt Schedule** - 使用 Salt 原生状态管理计划任务，是唯一受支持的下发方式
- **智能检测** - 自动检测数据库架构更新并执行相应操作

### 📊 监控与日志
- **统一日志格式** - 使用 SaltGoat 的统一日志格式
- **详细状态报告** - 提供系统各组件状态信息
- **错误处理** - 智能错误检测和处理

## 使用方法

### 基本语法
```bash
sudo saltgoat magetools maintenance <site> <action>
sudo saltgoat magetools cron <site> <action>
```

> 若已启用 Telegram ChatOps（`salt/pillar/chatops.sls.sample`），可在授权聊天中发送 `/saltgoat maintenance weekly <site>`、`/saltgoat cache clean <site>` 等命令；需要审批的操作会生成一次性 Token，需管理员 `/saltgoat approve <token>` 后才会真正执行。

> **提示**：`sudo saltgoat magetools cron` 仅负责封装 Salt Schedule，若 `salt-minion` 未运行会直接报错，请先恢复服务再执行该命令。

### 维护管理命令

#### 维护状态检查
```bash
# 检查维护状态
sudo saltgoat magetools maintenance tank status
```

#### 维护模式控制
```bash
# 启用维护模式
sudo saltgoat magetools maintenance tank enable

# 禁用维护模式
sudo saltgoat magetools maintenance tank disable
```

#### 维护任务执行
```bash
# 执行每日维护任务
sudo saltgoat magetools maintenance tank daily

# 执行每周维护任务
sudo saltgoat magetools maintenance tank weekly

# 执行每月维护任务（完整部署流程）
sudo saltgoat magetools maintenance tank monthly

# 执行健康检查
sudo saltgoat magetools maintenance tank health

# 创建备份
sudo saltgoat magetools maintenance tank backup

# 清理日志和缓存
sudo saltgoat magetools maintenance tank cleanup

# 完整部署流程
sudo saltgoat magetools maintenance tank deploy

# 示例：每周任务同时刷新 Valkey 并触发 Restic
sudo saltgoat magetools maintenance tank weekly --allow-valkey-flush --trigger-restic
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
| `--trigger-restic` | 若已为站点配置 Restic，联动触发一次快照 |
| `--restic-site NAME` | 触发 Restic 时仅备份指定站点（传递给 `backup restic run --site`） |
| `--restic-backup-dir PATH` | 覆盖 Restic 仓库（如 `/home/Dropbox/<site>/snapshots`） |
| `--restic-extra-path PATH` | Restic 额外路径，可多次使用或改用 `--restic-extra-paths "p1,p2"` |
| `--static-langs \"en_US zh_CN\"` | 静态资源部署语言列表 |
| `--static-jobs N` | 静态资源部署线程数（默认 4） |

> 提示：`--restic-*` 参数会透传给 `sudo saltgoat magetools backup restic run`。请先使用 `sudo saltgoat magetools backup restic install --site <name>` 为目标站点生成配置；若只需一次性备份，可在维护任务外单独运行 `sudo saltgoat magetools backup restic run --paths ...` 搭配 `--backup-dir` 等参数。

### 定时任务管理

#### Salt Schedule（推荐）
```bash
# 安装 Salt Schedule 任务
sudo saltgoat magetools cron tank install

# 查看状态
sudo saltgoat magetools cron tank status

# 测试功能
sudo saltgoat magetools cron tank test

# 查看日志
sudo saltgoat magetools cron tank logs

# 卸载任务
sudo saltgoat magetools cron tank uninstall
```

> `sudo saltgoat magetools cron` 现在基于 Salt Schedule 管理所有维护计划，无需再手动编辑 crontab。

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
- **推荐组合**：使用 Restic（`sudo saltgoat magetools backup restic install/run`）搭配 XtraBackup 物理备份，满足长期和快速恢复需求。
- **单库导出**：`sudo saltgoat magetools xtrabackup mysql dump` 面向站点迁移/调试场景，命令会输出备份文件大小，通过 Salt event 与 Telegram 双管齐下记录结果。
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
建议复制 `salt/pillar/magento-schedule.sls.sample` 为实际文件后再写入上述配置；执行 `sudo saltgoat magetools cron <site> install` 后会生成对应的 Salt Schedule。每次导出仍会触发 Salt event 与 Telegram 通知，便于追踪。日常也可以直接运行 `sudo saltgoat magetools schedule auto`，脚本会自动发现 `/var/www/*` 下所有 Magento 站点并调用 `magento_schedule_install`，缺失任务将补齐，已存在的任务会做幂等校验。若 Pillar 未声明 `mysql_dump_jobs` / `api_watchers` / `stats_jobs`，工具会按默认策略回填：数据库 `<site>mage` 每小时导出到 `/var/backups/saltgoat/<site>`（若检测到 `~/Dropbox/<site>/databases` 则优先使用）、API Watch 以 `*/5 * * * *` 轮询订单与会员、统计任务在 06:00 附近错峰生成日/周/月报，周报默认不推送 Telegram，可在 Pillar 中覆盖。

### 业务事件通知（API Watchers）
SaltGoat 现在可以轮询 Magento REST API，将“新订单 / 新用户”推送到 Telegram。

1. **配置凭据**：在 `salt/pillar/secret/magento_api.sls` 填写各站点的 API 基础信息（示例见 `.example` 文件）：
   ```yaml
   secrets:
     magento_api:
       bank:
         base_url: "https://bank.example.com"
         token: "<integration_token>"          # 默认 Bearer，推荐使用 Integration Access Token
        tank:
          base_url: "https://tank.example.com"
          auth_mode: oauth1
          consumer_key: "<oauth_consumer_key>"
          consumer_secret: "<oauth_consumer_secret>"
          access_token: "<oauth_access_token>"
          access_token_secret: "<oauth_access_token_secret>"
   ```
   > `auth_mode` 默认为 `bearer`。如果需要兼容历史 OAuth1 凭据（Magento Admin → System → Integrations → Activate），可按上例提供 `consumer_*` 与 `access_token*` 字段；脚本会自动检测并按需签名。模板文件 `magento_api.sls.example` 已更新为上述格式。

2. **启用 Salt Schedule**：在 `magento_schedule.api_watchers` 中声明需要轮询的站点与频率：
   ```yaml
   magento_schedule:
     api_watchers:
       - name: bank-api-orders
         cron: '*/5 * * * *'
         site: bank
         kinds:
           - orders
           - customers
   ```
   执行 `sudo saltgoat magetools cron bank install` 后，Salt Schedule 会创建 `sudo saltgoat magetools api watch --site bank --kinds orders,customers` 任务。

3. **首次运行**：若无历史记录，脚本会将最新 `entity_id` 作为基线（不推送历史订单/用户）。后续只要发现新的 ID，就会：
   - 发送 `saltgoat/business/order` 或 `saltgoat/business/customer` 事件；
   - 写入 `/var/log/saltgoat/alerts.log`；
   - 通过 `/opt/saltgoat-reactor` 直接广播 Telegram（默认发送到所有启用的 profile）。

4. **手动触发**：可用 `sudo saltgoat magetools api watch --site bank --kinds orders` 验证。首次运行若想立即收到通知，可先删除状态文件 `/var/lib/saltgoat/magento-watcher/bank/*`。如需强制指定认证方式，可追加 `--auth-mode bearer|oauth1`。

> 如需更细颗粒控制，可将 `kinds` 限制为 `orders` 或 `customers`，并复制多条 watcher 分别推送到不同 Telegram profile。

### Varnish 加速

SaltGoat 提供 `sudo saltgoat magetools varnish enable|disable <site>`，用于在几秒内切换以下拓扑：

```
访客 HTTPS 请求
        │
        ▼
前端 Nginx (TLS 终止，绑定 80/443)
        │  proxy_pass 127.0.0.1:6081
        ▼
Varnish (HTTP 缓存层)
        │  backend 127.0.0.1:8080
        ▼
Nginx backend (监听 127.0.0.1:8080，加载站点原始 nginx.conf.sample)
        │  FastCGI
        ▼
PHP-FPM (php8.3-fpm/www-data)
```

主要行为与注意事项如下：

- **TLS 不变**：HTTPS/Certbot 仍由前端 Nginx 处理，`.well-known/acme-challenge` 被写入到站点 `pub/`，因此证书申请/续期不受影响。
- **缓存策略**：`salt/states/optional/varnish.vcl` 仅缓存无 Cookie 的 GET/HEAD 静态资源与 HTML 页面；后台路径、`/customer/section`、`/rest/`、`/graphql/`、`/page_cache/`、`/checkout/*` 等接口都会直接回源 8080，保证功能正确。
- **后台适配**：脚本会自动读取 `app/etc/env.php` 的 `backend.frontName`，生成对应的 `/etc/nginx/snippets/varnish-frontend-<site>.conf`，并放大缓存缓冲区 (`proxy_buffers 64 256k` 等)，同时隐藏上游的 CSP 头并注入 `https://assets.adobedtm.com` 白名单，避免 Magento 2 后台弹出 “Attention” 脚本错误。
- **多域名兼容**：生成 backend 配置时会提取原站点 `server_name`，并补充 Magento 中各 store 的 Base URL 域名，确保多语言/多商店不会误路由到其它站点（避免此前出现的 bank↔tank 交叉跳转）。
- **版本管理**：`optional.varnish` 会自动添加官方 packagecloud 仓库并安装 Varnish 7.6，与 Magento 2.4.8 的推荐版本保持一致；多站点仅需运行 enable/disable 命令即可复用同一套依赖。
- **回滚安全**：`disable` 命令会恢复原 `/etc/nginx/sites-available/<site>`、删除临时 snippet/backend 并将 FPC 切回内置缓存，确保可以无损返回原状。
- **服务管理**：禁用单个站点时不会停止全局 varnish 服务，避免其它仍在使用缓存的站点出现 502；若需要完全停用，可手动执行 `sudo systemctl stop varnish`。
- **Pillar/State 一致性**：上述配置都写入仓库（`modules/magetools/varnish.sh`、`salt/states/optional/varnish.vcl`、`app/etc/csp_whitelist.xml`），因此 `git clone` + SaltGoat 安装后会得到完全一致的行为，不需要额外手工修改。
- **快速体检**：使用 `sudo saltgoat magetools varnish diagnose <site>` 可只读检查 snippet 是否透传 `X-Magento-Vary`、VCL 是否包含 Vary 缓存键、Magento FPC 是否设为 Varnish、offloader header 是否正确等，便于排查菜单丢失等常见问题。

> 若希望扩展缓存命中率，可在 `salt/states/optional/varnish.vcl` 中按需加入其他允许缓存的接口；测试通过后再执行 `sudo salt-call --local state.apply optional.varnish` 下发即可。

### 业务汇总报表（Stats Jobs）
配合 `saltgoat magetools stats`，可以自动生成每日/每周/每月的订单与新注册统计，并写入 `/var/log/saltgoat/alerts.log`（可选推送 Telegram）。

1. **配置 Pillar**：在 `magento_schedule.stats_jobs` 中声明报表任务与执行频率：
   ```yaml
   magento_schedule:
     stats_jobs:
       - name: bank-stats-daily
         cron: '5 6 * * *'        # 每天 06:05
         site: bank
         period: daily
       - name: bank-stats-weekly
         cron: '15 6 * * 1'       # 每周一 06:15
         site: bank
         period: weekly
         no_telegram: true        # 仅写日志，不推送 Telegram
       - name: tank-stats-monthly
         cron: '25 6 1 * *'       # 每月 1 日 06:25
         site: tank
         period: monthly
         page_size: 500           # 可选：自定义分页
         telegram_thread: 3       # 可选：自定义 Telegram 线程
   ```
   支持 `site` 或 `sites` 字段筛选多个站点；`period` 可选 `daily` / `weekly` / `monthly`；`page_size`、`telegram_thread`、`no_telegram`、`quiet`、`extra_args` 均为可选参数。

2. **安装计划**：执行 `sudo saltgoat magetools cron <site> install`，新任务会与维护/备份计划一起下发到 Salt Schedule。

3. **查看结果**：报表运行成功后会在 Telegram (如启用) 和 `/var/log/saltgoat/alerts.log` 中生成 `[SUMMARY]` 记录；如需临时运行，可执行 `sudo saltgoat magetools stats --period daily --site <site> --no-telegram --quiet`。

> 提示：在 mysqldump 和 stats 任务中使用 `site` / `sites` 字段，可让多站点主机按需启用或停用指定任务。

## 定时任务配置

### Salt Schedule 配置
Salt Schedule 通过 Salt Minion 内置计划任务管理维护流程。执行以下命令可以查看当前配置：

```bash
sudo salt-call --local schedule.list --out=yaml | grep -A3 'magento-'
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

> 若 `salt-minion` 当前不可用，上述命令会返回空列表；请先恢复 `salt-minion` 服务后再执行 `install`，系统不再自动写入 `/etc/cron.d/` 兜底。

### Salt Beacons 与 Reactor
SaltGoat 提供事件驱动的维护能力，推荐通过以下命令启用并检查状态：

```bash
# 配置服务/资源 Beacon，并启用 Reactor 自动化
sudo saltgoat monitor enable-beacons

# 查看当前 Beacon 与 Schedule 状态
sudo saltgoat monitor beacons-status
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
- `salt/states/optional/magento-schedule.sls` - 定时任务配置（完全基于 Salt Schedule，不再回退 Cron）
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
sudo saltgoat magetools permissions fix /var/www/tank
```

#### 2. 数据库连接问题
```bash
# 检查数据库状态
sudo saltgoat magetools maintenance tank health
```

#### 3. 缓存问题
```bash
# 清理缓存
sudo saltgoat magetools maintenance tank cleanup
```

#### 4. 定时任务不执行
```bash
# 检查定时任务状态
sudo saltgoat magetools cron tank status
```

### 日志分析
```bash
# 查看维护日志
sudo saltgoat magetools cron tank logs

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

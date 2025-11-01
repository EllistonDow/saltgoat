# SaltGoat 更新日志

## [1.2.6] - 2025-11-01

### Changes
- 修改 9 个文件: README.md, modules/monitoring/__pycache__/resource_alert.cpython-312.pyc, modules/monitoring/resource_alert.py, modules/pwa/install.sh, modules/pwa/overrides/packages/venia-concept/local-intercept.js 等


## [1.2.5] - 2025-10-31

### Changes
- 修改 11 个文件: README.md, docs/CHANGELOG.md, docs/MAGENTO_PWA.md, docs/pwa-todo.md, lib/help.sh 等


## [1.2.4] - 2025-10-31

### Changes
- 修改 7 个文件: docs/MAGENTO_PWA.md, modules/magetools/permissions.sh, modules/pwa/install.sh, modules/pwa/overrides/productDetailFragment.gql.js, modules/pwa/overrides/useProductFullDetail.js 等


## [1.2.3] - 2025-10-31

### Changes
- 修改 13 个文件: .gitignore, README.md, docs/MAGENTO_PWA.md, lib/help.sh, modules/magetools/magetools.sh 等


## [1.2.2] - 2025-10-30

### Changes
- 修改 4 个文件: docs/MAGENTO_MAINTENANCE.md, lib/help.sh, modules/magetools/varnish.sh, salt/states/optional/varnish.vcl


## [1.2.1] - 2025-10-30

### Changes
- 修改 2 个文件: modules/git/git.sh, saltgoat


## [1.1.12] - 2025-10-30

### Changes
- 修改 1 个文件: modules/magetools/varnish.sh


## [1.2.0] - 2025-10-30

### Changes
- 修改 7 个文件: core/install.sh, docs/MAGENTO_MAINTENANCE.md, modules/magetools/varnish.sh, salt/pillar/saltgoat.sls, salt/states/optional/varnish.sls 等


## [1.1.11] - 2025-10-30

### Changes
- 修改 11 个文件: docs/CHANGELOG.md, docs/MAGENTO_MAINTENANCE.md, docs/SECRET_MANAGEMENT.md, lib/help.sh, modules/magetools/README.md 等


## [1.1.10] - 2025-10-30

### Changes
- 修改 3 个文件: docs/CHANGELOG.md, modules/monitoring/resource_alert.py, monitoring/README.md


## [1.1.9] - 2025-10-30

### Changes
- 修改 7 个文件: README.md, docs/CHANGELOG.md, docs/MAGENTO_MAINTENANCE.md, salt/_modules/saltgoat.py, salt/pillar/magento-schedule.sls 等


## [1.0.9] - 2025-10-30

### Changes
- 修改 27 个文件: AGENTS.md, README.md, docs/BACKUP_RESTIC.md, docs/CHANGELOG.md, docs/INSTALL.md 等
- `magento_schedule.stats_jobs` 支持为每站点定时运行 `saltgoat magetools stats`，自动生成每日/每周/每月业务汇总。
- `saltgoat monitor alert resources` 告警信息新增“Triggered: Load/Memory/Disk”等字段，并输出命中阈值详情；可通过 Pillar `saltgoat:monitor:thresholds` 自定义阈值。
- 新增 `saltgoat magetools varnish enable|disable <site>`，一键切换 Nginx(TLS) → Varnish → backend Nginx/PHP，停用时自动恢复原配置。


> **权限说明（自 v1.0.9 起）**：除 `help`/`git`/`lint`/`format` 等只读命令外，SaltGoat CLI 默认需使用 `sudo saltgoat ...` 执行以读取 Pillar、`/etc` 及 Salt 组件。以下历史记录保留当时的命令写法，如需照搬请按照新版策略补上 `sudo`。

## [1.1.8] - 2025-10-30

### Changes
- 修改 7 个文件: README.md, lib/help.sh, lib/utils.sh, modules/magetools/__pycache__/magento_api_watch.cpython-312.pyc, modules/magetools/magento_api_watch.py 等


## [1.1.7] - 2025-10-30

### Changes
- 修改 34 个文件: README.md, docs/MAGENTO_MAINTENANCE.md, docs/SECRET_MANAGEMENT.md, docs/TELEGRAM_TOPICS.md, modules/magetools/backup-restic.sh 等


## [1.1.6] - 2025-10-30

### Changes
- 修改 9 个文件: README.md, docs/MAGENTO_MAINTENANCE.md, modules/magetools/__pycache__/magento_api_watch.cpython-312.pyc, modules/magetools/magento_api_watch.py, modules/magetools/magetools.sh 等


## [1.1.5] - 2025-10-29

### Changes
- 修改 1 个文件: todo/telegram_bot_todo.md


## [1.1.4] - 2025-10-29

### Changes
- 修改 1 个文件: docs/BACKUP_RESTIC.md


## [1.1.3] - 2025-10-29

### Changes
- 修改 2 个文件: modules/magetools/backup-restic.sh, salt/states/templates/restic-backup.sh.jinja


## [1.1.2] - 2025-10-29

### Changes
- 修改 9 个文件: README.md, docs/BACKUP_RESTIC.md, docs/MAGENTO_MAINTENANCE.md, docs/MYSQL_BACKUP.md, modules/magetools/backup-restic.sh 等


## [1.1.1] - 2025-10-29

### Changes
- 修改 15 个文件: README.md, docs/MAGENTO_MAINTENANCE.md, docs/MYSQL_BACKUP.md, salt/pillar/backup-restic.sls, salt/pillar/backup-restic.sls.sample 等


## [1.1.0] - 2025-10-29

### Changes
- 修改 5 个文件: docs/MAGENTO_MAINTENANCE.md, docs/MYSQL_BACKUP.md, salt/_modules/saltgoat.py, salt/pillar/magento-schedule.sls, salt/states/optional/magento-schedule.sls


## [1.0.13] - 2025-10-29

### Changes
- 修改 6 个文件: docs/BACKUP_RESTIC.md, docs/MAGENTO_MAINTENANCE.md, docs/MYSQL_BACKUP.md, salt/pillar/magento-optimize.sls, salt/pillar/magento-schedule.sls 等


## [1.0.12] - 2025-10-29

### Changes
- 修改 4 个文件: docs/MYSQL_BACKUP.md, modules/magetools/magento-cron.sh, salt/pillar/magento-optimize.sls, salt/pillar/top.sls


## [1.0.11] - 2025-10-29

### Changes
- 修改 6 个文件: README.md, docs/BACKUP_RESTIC.md, docs/MYSQL_BACKUP.md, docs/POSTFIX_SMTP.md, docs/SECRET_MANAGEMENT.md 等


## [1.0.10] - 2025-10-29

### Changes
- 修改 17 个文件: .gitignore, docs/BACKUP_RESTIC.md, docs/MYSQL_BACKUP.md, docs/POSTFIX_SMTP.md, lib/utils.sh 等


## [1.0.9] - 2025-10-29

### Changes
- 修改 5 个文件: modules/git/git.sh, saltgoat, scripts/release.sh, tests/consistency-test.sh, tests/test_git_release.sh


## [1.0.8] - 2025-10-29

### Changes
- 修改 1 个文件: saltgoat


## [1.0.7] - 2025-10-29

### Changes
- 修改 9 个文件: README.md, docs/MAGENTO_MAINTENANCE.md, docs/MAGENTO_MAINTENANCE_QUICK_REFERENCE.md, modules/magetools/magento-cron.sh, salt/states/optional/magento-maintenance/daily.sls 等


## [1.0.6] - 2025-10-29

### Changes
- 修改 3 个文件: modules/magetools/README.md, modules/magetools/mysql-backup.sh, salt/states/reactor/backup_notification.sls


## [1.0.5] - 2025-10-29

### Changes
- 修改 36 个文件: core/system.sh, docs/POSTFIX_SMTP.md, lib/help.sh, modules/git/git.sh, modules/magetools/backup-restic.sh 等


## [1.0.4] - 2025-10-27

### Changes
- 修改 4 个文件: monitoring/system.sh, salt/pillar/magento-optimize.sls, salt/pillar/saltgoat.sls, saltgoat


## [1.0.3] - 2025-10-27

### Changes
- 修改 16 个文件: docs/MAGENTO_PERMISSIONS.md, docs/MYSQL_BACKUP.md, lib/help.sh, modules/git/help.sh, modules/magetools/README.md 等


## [1.0.2] - 2025-10-27

### Changes
- 修改 45 个文件: README.md, bank, docs/BACKUP_RESTIC.md, docs/INSTALL.md, docs/MAGENTO_MAINTENANCE.md 等


## [1.0.1] - 2025-10-26

### Changes
- 修改 9 个文件: bank, modules/magetools/README.md, modules/magetools/rabbitmq-salt.sh, modules/magetools/rabbitmq.sh, salt/states/optional/magento-rabbitmq-check.sls 等


## [1.0.0] - 2025-10-26

### Changes
- 修改 7 个文件: docs/CHANGELOG.md, lib/help.sh, modules/git/git.sh, salt/pillar/nginx.sls, salt/states/optional/certbot.sls 等


## [0.9.17] - 2025-10-26

### Changes
- 修改 2 个文件: salt/pillar/nginx.sls, services/nginx.sh


## [0.9.16] - 2025-10-26

### Changes
- 修改 68 个文件: README.md, docs/CHANGELOG.md, docs/INSTALL.md, docs/MAGENTO_MAINTENANCE.md, docs/MAGENTO_MAINTENANCE_QUICK_REFERENCE.md 等


## [0.9.15] - 2025-10-25

### Changes
- 修改 18 个文件: README.md, docs/CHANGELOG.md, docs/INSTALL.md, modules/analyse/analyse.sh, modules/git/git.sh 等


## [Unreleased]

### ✨ 新功能
- `saltgoat analyse install matomo` 支持自定义域名与数据库管理账号，默认复用 `/etc/salt/mysql_saltuser.cnf`，并新增 `tests/test_analyse_state.sh` 干跑测试。
- `saltgoat git push` 新增 `--dry-run` 模式、推送失败回滚提示与辅助信息，同时提供 `tests/test_git_release.sh` 做回归验证。
- Matomo 安装流程新增 `--install-dir/--php-socket/--owner/--group` 覆盖参数，随机生成的数据库密码写入 `/var/lib/saltgoat/reports/matomo-db-password.txt`，并在检测到现有 MySQL/Percona 时阻止 MariaDB 冲突；底层 Salt 状态改用 `mysql_user.present`/`mysql_grants.present` 保证幂等。
- `saltgoat magetools api watch` 自动识别 Bearer/OAuth1 凭据，支持多页增量抓取并在 backlog 超量时跳过历史推送；新增 `tests/test_magento_api_watch.py` 覆盖核心逻辑。
- `saltgoat magetools varnish enable|disable` 更新为启用大头部缓冲、无损回滚配置，解决启用后站点出现 `502 Bad Gateway` 的问题。

### 📚 文档
- `docs/INSTALL.md` 补充 Matomo 快速部署与 Git 发布流程说明。
- 帮助菜单更新，指引 Dry-run 用法与回滚指令。


## [0.9.11] - 2025-10-25

### 🧭 CLI 导航
- `saltgoat help install|pillar|optimize|speedtest` 全面升级为彩色分组布局，快速区分常用动作、进阶参数与示例流程。
- 每个子菜单新增场景化提示与 NOTE，引导用户结合 Pillar、报告目录等关键路径操作。

### 🛡️ Shell 合规
- 为全仓库 60+ Shell 脚本补充安全赋值、变量引用与 `cd` 回退逻辑，`bash scripts/code-review.sh -a` 现默认零警告通过。
- `services/database/state/performance`、`monitoring/*`、`scripts/*` 等模块统一引用 Pillar 凭据并加强错误输出，提升可维护性。

### 🛠️ 服务操作体验
- SaltGUI、Nginx、Salt state 相关脚本新增原子目录切换、重载回退与日志定位提示，避免部分环境下的未捕获异常。
- `tests/test_rabbitmq_check.sh` 与维护类脚本同步采用新的日志工具，确保安装后验证流程更直观。

### 📊 分析平台
- 新增 `saltgoat analyse install matomo`，通过 Salt 状态一次性安装 Matomo、Nginx 站点与定时任务，支持 Pillar 覆盖安装目录与域名。
- `optional.analyse` state 提供默认依赖、权限和 Nginx 模板，安装完成后输出访问与后续操作指引。
- Pillar 现在支持 `matomo:db.*` 开关与凭据，State 可自动创建数据库/用户；CLI 增加 `--with-db`、`--db-*`、`--db-provider`、`--db-admin-*` 及 `--init-pillar` 选项，用于引导 Pillar 并传入运行时覆盖，默认会读取 `/etc/salt/mysql_saltuser.cnf` 的 saltuser 账户作为管理凭据。

### 🔁 Git 发布助手
- `saltgoat git push [version] [note]` 默认补丁号 +0.0.1，亦可指定自定义版本；自动检测重复版本/tag 后再发布。
- 未填写 note 时根据当前 diff 生成摘要并写入 changelog 与提交信息，仅收集已跟踪文件，若需纳入新文件请先手动 `git add`。

## [0.9.9] - 2025-10-25

### 🖥️ CLI 体验
- 重写 `saltgoat help` 主菜单与各子菜单，统一使用彩色标题、命令行对齐布局，并补充 Nginx、监控、诊断、面板等详细指令说明，帮助新人快速上手。

### 🧩 Salt 服务
- 新增 `services.nginx` 状态模块，使用包管理器部署 Nginx，并通过 Pillar (`salt/pillar/nginx.sls`) 管理站点映射与模板；`core.nginx` 现在仅聚合服务状态。
- 引入 RabbitMQ/Valkey Salt 原生脚本（`saltgoat magetools rabbitmq-salt|valkey-setup|valkey-check`）及对应状态，支持 Pillar 驱动的消息队列/缓存配置与检测。

### 🛠️ Magento 调优
- `optional.magento-optimization` State 不再使用易匹配过多的 `file.line`，改用安全的 `file.replace` / `file.managed` 操作，Salt 3000 系列及 dry-run 全部通过测试。
- `tests/test_magento_optimization.sh` 干跑验证已更新逻辑，确保模板在 CI 与本地均可渲染。
- CLI 现在自动探测 `/var/www`、`/srv`、`/opt/magento` 下的 Magento 站点，并在 `--site` 未指定时填充 Pillar；若检测失败或出现多站冲突，Salt state 会提示或直接中止，避免误改配置。

### 📘 文档
- `docs/INSTALL.md` 增补 Pillar 初始化 / 查看 / 刷新的操作说明，并记录 `saltgoat passwords --refresh` 的最佳实践流程。

## [0.9.8] - 2025-10-25

### ⚙️ 配置管理
- **Pillar 优先**：移除 `.env` 流程，新增 `saltgoat pillar init/show/refresh`，脚本会安全写入 `salt/pillar/saltgoat.sls` 并自动刷新 Pillar。
- **快速同步密码**：`saltgoat passwords --refresh` 会刷新 Pillar 并重新应用核心服务状态，`saltgoat install all` 结束后直接输出版本、状态与密码。
- **文档更新**：README/INSTALL 指南改为 Pillar-first，强调默认密码需立即替换。

### 🧰 Magento 优化
- **兼容旧版 Salt**：优化 state 不再依赖 `combine/merge` 过滤器，同时保留 overrides 能力并输出结构化报告。
- **可选执行**：安装流程仅在传入 `--optimize-magento` 时才执行调优，避免自动失败阻塞安装。
- **CI 保障**：新增 `tests/test_magento_optimization.sh` 并在 GitHub Actions 运行 dry-run，及早发现模板回归。

## [0.9.7] - 2025-10-24

### 🛠️ Valkey 稳定性补丁
- **修复 Salt 渲染错误**：`optional.magento-valkey` 使用 Heredoc 传递 JSON 时现在保持缩进，避免出现 “could not find expected ':'” 并导致 env.php 写入失败。
- **多实例健康检查**：`optional.magento-valkey-check` 在 PING 时使用每个缓存区的独立主机/端口/密码，正确支持分离式 Valkey 拓扑并提供更准确的诊断。

## [0.9.6] - 2025-10-24

### 🧪 Magento Valkey 检测与健壮性
- **新增 `valkey-check`**：提供 Salt 原生检测流程，逐项校验 env.php 配置、Valkey 连接、权限与密码一致性，命令为 `saltgoat magetools valkey-check <site>`.
- **稳定写入配置**：`optional.magento-valkey` 现在直接使用 pillar 数据渲染，避免 `sudo` 环境变量丢失导致的空值写入。
- **更安全的数据库分配**：`valkey-setup` 默认复用既有 DB 编号，仅在变更时清理旧库，并会跳过其他站点正在使用的数据库。

## [0.9.4] - 2025-01-27

### 🔧 **CSP 管理系统重构**
- **单一来源**：`saltgoat nginx csp level <0-5>` 仅写入 Pillar 并触发 `core.nginx`，配置改动都能回溯
- **Salt 状态渲染**：`core.nginx` 根据 Pillar 渲染 `/etc/nginx/conf.d/csp.conf`，禁用时自动清理
- **状态洞察**：`saltgoat nginx csp status` 输出 Pillar 中的当前等级与策略摘要
- **兼容旧配置**：等级 0 自动禁用并移除残留 CSP 片段
- **ModSecurity 按需装配**：切换等级会自动安装 `libnginx-mod-http-modsecurity` 并写入 `load_module`，失败会回滚 Pillar
- **后台路径探测**：未显式指定后台路径时，自动从 Magento `app/etc/env.php` 读取 `frontName`，找不到则回退 `/admin_tattoo`
- **自动证书**：`saltgoat nginx add-ssl <site> [domain] [email] [-dry-on]` 自动申请/续期 Let's Encrypt 证书，并在成功后追加 443 监听与 HTTP→HTTPS 重定向

### 📋 **可用命令**
```bash
saltgoat nginx csp status      # 检查 CSP 状态
saltgoat nginx csp level 3     # 设置 CSP 等级
saltgoat nginx csp level 0     # 禁用 CSP
```

## [0.9.3] - 2025-10-23

### 🔒 **CSP 等级配置系统**
- **5 个安全等级**：从开发环境（等级 1）到严格生产环境（等级 5）
- **命令即配置**：命令行更新 Pillar，Salt 自动渲染站点，避免手工编辑
- **快速回滚**：等级 0 直接禁用并撤销配置文件
- **策略可见**：所有策略内容都保存在 Pillar，版本可追踪

### 📋 **使用示例**
```bash
# 设置 CSP 等级
saltgoat nginx csp level 3

# 检查 CSP 状态
saltgoat nginx csp status

# 禁用 CSP
saltgoat nginx csp disable

# 启用 CSP（默认等级 3）
saltgoat nginx csp level 3
```

### 🎯 **解决的问题**
- ✅ Magento 2 后台 Knockout.js 兼容性问题
- ✅ CSP 策略过于严格导致功能异常
- ✅ 不同环境需要不同安全等级的需求
- ✅ CSP 配置管理复杂的问题

### 🔧 **技术特性**
- **Pillar 优先**：所有等级、策略文本均存储在 Pillar
- **幂等状态**：Salt 负责渲染/清理 `conf.d/csp.conf`
- **统一入口**：CLI 修改后自动触发 `core.nginx`，保证配置生效
- **等级映射**：1-5 档位直接对应默认策略模板，可按需扩展

## [0.9.2] - 2025-10-23

### 🔧 **Valkey 脚本重大改进**
- **智能站点检测**：自动识别全新站点 vs 迁移站点
- **全新站点支持**：为没有 Valkey 配置的站点添加完整配置
- **迁移站点优化**：安全更新现有 Valkey 配置
- **多站点安全清理**：只清理当前站点的旧数据库，保护其他站点数据
- **权限修复**：所有 Magento CLI 命令使用 `sudo -u www-data` 权限

### 🛡️ **安全清理机制**
- **三重安全检查**：跳过当前使用、其他站点使用、无站点前缀的数据库
- **站点隔离**：基于缓存前缀 (`site_cache_`, `site_session_`) 识别站点数据
- **精确清理**：只清理包含当前站点前缀的键
- **多站点保护**：绝不误删其他站点的数据库

### 📋 **使用示例**
```bash
# 全新站点：自动添加 Valkey 配置
saltgoat magetools valkey-renew newsite

# 迁移站点：安全更新配置并清理旧数据
saltgoat magetools valkey-renew migratedsite

# 脚本会自动：
# 1. 检测站点类型（全新/迁移）
# 2. 分配不冲突的数据库编号
# 3. 安全清理当前站点的旧数据库
# 4. 保护其他站点的数据
```

### 🎯 **解决的问题**
- ✅ 全新站点无法使用 `valkey-renew` 的问题
- ✅ 多次 renew 产生大量弃用数据库的问题
- ✅ 多站点环境下误删其他站点数据的安全风险
- ✅ Magento CLI 命令权限不足的问题

## [0.9.1] - 2025-10-23

### 🔧 **Nginx 管理功能完善**
- **删除站点优化**：完整清理 SSL 证书、日志文件和配置文件
- **路径统一**：修复 Nginx 路径不一致问题（统一使用 `/etc/nginx/`）
- **新增功能**：添加 `enable`、`disable`、`reload`、`test` 命令
- **多域名支持**：`create` 和 `add-ssl` 命令支持多个域名输入
- **SSL 邮箱处理**：未配置邮箱时提示用户输入，支持邮箱格式验证

### 🛠️ **Magento 2 站点模板**
- **新增 `--magento`**：`saltgoat nginx create` 增加 `--magento` 选项，一次性写入 Magento 官方推荐配置
- **upstream 优化**：统一在全局 `fastcgi_backend`，站点模板中自动引用 `nginx.conf.sample`
- **重用原配置**：保留 SSL / 多域名 / 日志设置，仅替换为 Magento 站点结构
- **安全回滚**：仍保留自动备份，配置失败时即时恢复

### 🐛 **Bug 修复**
- **SSL 备份位置**：修复备份文件保存到错误位置的问题
- **配置冲突**：解决 Nginx 配置冲突警告问题
- **错误处理**：改进各种操作的错误处理和用户反馈

### 📋 **使用示例**
```bash
# 多域名站点创建
saltgoat nginx create mysite "example.com www.example.com"

# SSL 证书添加（支持多域名）
saltgoat nginx add-ssl mysite "example.com www.example.com"

# 站点管理
saltgoat nginx enable mysite    # 启用站点
saltgoat nginx disable mysite   # 禁用站点
saltgoat nginx reload           # 重新加载配置
saltgoat nginx test             # 测试配置

# Magento 2 模板建站
saltgoat nginx create mysite "example.com www.example.com" --magento
```

## [0.9.0] - 2025-10-23

### 🔒 **ModSecurity 等级配置系统**
- **10 级安全等级**：从开发环境（等级1）到军事级安全（等级10）
- **智能配置**：针对 Magento 2 特殊路径（admin、setup）优化
- **渐进式安全**：适应不同环境需求，从宽松到严格
- **自动备份**：每次配置更改自动备份原配置
- **配置验证**：自动测试 Nginx 配置，失败时恢复备份

### 🛡️ **安全检测规则**
- **SQL 注入检测**：`@detectSQLi` 规则
- **XSS 攻击检测**：`@detectXSS` 规则
- **路径遍历检测**：`@detectPathTraversal` 规则
- **命令注入检测**：`@detectCmdInjection` 规则
- **文件上传限制**：危险文件类型检测
- **异常请求检测**：HTTP 方法、头部验证

### 🎯 **等级设计**
- **等级 1-2**：开发/测试环境，宽松配置
- **等级 3-4**：预生产环境，中等配置
- **等级 5-6**：生产环境，标准到严格配置（推荐）
- **等级 7-8**：高安全环境，企业级到金融级安全
- **等级 9-10**：最高安全环境，政府级到军事级安全

### 🚀 **新增命令**
- `saltgoat nginx modsecurity level [1-10]` - 设置 ModSecurity 等级
- `saltgoat nginx modsecurity status` - 检查 ModSecurity 状态
- `saltgoat nginx modsecurity disable` - 禁用 ModSecurity
- `saltgoat nginx modsecurity enable` - 启用 ModSecurity
- `saltgoat nginx help` - 显示 Nginx 帮助信息

### 📚 **文档更新**
- **帮助系统**：更新 Nginx 帮助信息，包含 ModSecurity 命令
- **模块集成**：ModSecurity 模块完全集成到主系统
- **错误处理**：完善的错误处理和配置恢复机制

## [0.8.3] - 2025-10-23

### 🔄 **Magento 2 模板改进**
- **命令整合**：统一由 `saltgoat nginx create <site> "<dom1 dom2>" --magento` 完成建站
- **自动检测**：保留原站点 SSL / 日志，可重复执行并安全回滚
- **兼容本地/生产**：结合 `nginx.conf.sample`，自动加载官方优化规则

### 🛠️ **脚本修复**
- **nginx 测试命令**：修复 `nginx -t` 使用错误配置文件路径的问题
- **备份管理**：备份文件保存到 `sites-available` 目录，避免冲突
- **错误恢复**：配置测试失败时自动恢复备份配置
- **帮助信息**：更新帮助文档，反映新的简化用法

### 📋 **使用改进**
- **示例**：`saltgoat nginx create shop "shop.com www.shop.com" --magento`
- **自动路径**：站点名称默认映射 `/var/www/<site>`，可通过 `--root` 覆盖
- **重复执行**：命令可重复运行，确保配置收敛

## [0.8.2] - 2025-10-22

### 🌐 **Nginx 配置优化**
- **简化配置策略**：采用 Magento 官方推荐的简单 Nginx 配置方式
- **upstream 优化**：将 `fastcgi_backend` 定义移到站点配置中，避免全局冲突
- **配置统一**：移除复杂的自定义配置，直接使用 `nginx.conf.sample`
- **网站修复**：解决 `tank` 网站 502 错误和 `upstream sent too big header` 问题

### 🔧 **系统服务优化**
- **Nginx 服务**：修复 systemd 服务文件，确保使用正确的配置文件路径
- **配置文件清理**：删除多余的 `/etc/nginx/conf/nginx.conf` 文件
- **路径标准化**：统一使用 `/etc/nginx` 作为标准配置目录

### 📚 **文档完善**
- **Magento 维护文档**：完善维护周期和最佳实践说明
- **配置说明**：更新 Nginx 配置策略说明，强调简单配置的优势

## [0.8.1] - 2025-10-22

### 🔧 **权限管理优化**
- **修复权限问题**：解决 `valkey-renew` 脚本中的权限问题
- **env.php 权限**：从 `660` 改为 `644`，确保 Magento CLI 可读取
- **generated 目录**：在 `valkey-renew` 中删除重建，确保权限正确
- **权限修复策略**：区分保守修复（permissions fix）和激进修复（valkey-renew）

### 🆕 **新增功能**
- **OpenSearch 认证配置**：新增 `saltgoat magetools opensearch <user>` 命令
- **一键配置**：自动安装 apache2-utils，创建密码文件，配置 Nginx 认证
- **智能命名**：用户名 + 2010 作为密码，端口 9210，配置文件自动命名

### 🐛 **Bug 修复**
- **Nginx 配置**：修复主配置文件缺少 `include /etc/nginx/sites-enabled/*;` 的问题
- **站点清理**：清理 sites-enabled 目录中的备份文件
- **权限脚本**：修复所有脚本中的 sudo 权限问题

### 📚 **文档更新**
- **权限管理指南**：更新 `docs/MAGENTO_PERMISSIONS.md` 中的权限设置
- **帮助信息**：添加 OpenSearch 认证管理到帮助菜单
- **最佳实践**：统一所有脚本的权限管理最佳实践提示

### 🧹 **代码清理**
- **移除 emoji**：将所有 emoji 图标替换为统一的日志格式
- **统一格式**：使用 `[INFO]` `[SUCCESS]` `[WARNING]` `[ERROR]` 格式

## [0.8.0] - 2025-10-22

### 🎯 **重大改进**
- **项目结构优化**
  - 创建 `docs/` 目录，统一管理文档文件
  - 创建 `tests/` 目录，统一管理测试文件
  - 清理根目录，提高项目可维护性

- **权限管理最佳实践**
  - 新增 `docs/MAGENTO_PERMISSIONS.md` 权限管理指南
  - 修复权限管理函数，支持路径参数
  - 更新帮助信息，添加最佳实践提示

### 🔧 **功能改进**
- **权限管理命令优化**
  - `permissions check [path]` - 支持指定路径检查
  - `permissions fix [path]` - 支持指定路径修复
  - `permissions reset [path]` - 支持指定路径重置
  - 所有权限命令都使用 `sudo -u www-data` 最佳实践

- **脚本权限修复**
  - 修复 `valkey-renew.sh` 中的 sudo 权限问题
  - 修复 `migrate-detect.sh` 中的 sudo 权限问题
  - 移除不必要的 sudo 调用，避免权限混乱

### 📚 **文档更新**
- **新增文档**
  - `docs/MAGENTO_PERMISSIONS.md` - Magento 2 权限管理完整指南
  - 包含最佳实践、故障排除、安全建议

- **帮助信息优化**
  - 更新权限管理帮助信息
  - 添加路径参数说明
  - 添加最佳实践提示

### 🧹 **代码清理**
- **移除临时文件**
  - 删除 `alertmanager-0.26.0.linux-amd64*` 临时下载文件
  - 清理根目录，保持项目整洁

- **文件组织**
  - 文档文件统一移至 `docs/` 目录
  - 测试文件统一移至 `tests/` 目录
  - 提高项目结构的可维护性

## [0.7.1] - 2025-10-22

### 新增功能
- **Valkey 自动续期功能** (`saltgoat magetools valkey-renew`)
  - 随机分配数据库编号（10-99范围），避免冲突
  - 自动获取 Valkey 密码并清空指定数据库
  - 支持 `--restart-valkey` 参数重启 Valkey 服务
  - 完整的 Magento 缓存清理和重新编译流程

### 改进
- **统一日志格式**
  - 移除所有 emoji 图标
  - 使用统一的 `[INFO]` `[SUCCESS]` `[WARNING]` `[ERROR]` `[HIGHLIGHT]` 格式
  - 加载项目的 `lib/logger.sh` 库

- **Magento 工具集优化**
  - 清理 magetools 菜单，只保留核心功能
  - 移除简单的功能（cache、index、deploy、backup、performance、security、update等）
  - 保留：工具安装、权限管理、站点转换、Valkey缓存管理

- **Valkey 配置优化**
  - 支持 100 个数据库（0-99 范围）
  - 更新安装脚本和 systemd 服务配置

### 修复
- **权限问题修复**
  - 使用 `sudo` 执行文件备份和修改操作
  - 修复 `Permission denied` 错误

- **Valkey 认证问题修复**
  - 添加密码获取逻辑
  - 修复 `NOAUTH Authentication required` 错误
  - 确保数据库清空功能正常工作

- **数据库编号范围问题修复**
  - 修复数据库编号超出范围的问题
  - 确保随机分配的数据库编号在有效范围内

### 文档更新
- 更新帮助菜单，添加 `valkey-renew` 命令说明
- 更新示例命令和使用方法
- 完善 magetools 功能说明

## [0.6.1] - 2025-10-21

### 新增功能
- **Magento工具集** (`saltgoat magetools`)
  - 添加N98 Magerun2安装和管理
  - 添加N98 Magerun (Magento 1)支持
  - 添加Magento Cloud CLI支持
  - 添加PHPUnit单元测试框架安装
  - 添加Xdebug调试工具安装
  - 智能PHP扩展检测和自动安装
  - 完整的缓存管理功能
  - 索引管理功能
  - 部署管理功能
  - 备份恢复功能
  - 性能分析功能
  - 安全扫描功能
  - 更新管理功能

### 改进
- 优化工具安装流程，自动检测依赖
- 增强PHPUnit安装，自动处理PHP扩展
- 完善帮助系统和文档

### 修复
- 修复PHPUnit安装时的扩展依赖问题
- 优化工具版本检测逻辑

## [0.6.0] - 2025-01-21

### 🔧 重要修复
- **Nginx状态检测修复**: 修复了源码编译Nginx显示为inactive的问题，现在能正确识别手动启动的Nginx进程
- **optimize命令语法错误修复**: 修复了内存使用率解析失败的问题，现在optimize命令正常工作
- **automation模块basename错误修复**: 修复了Salt YAML输出解析导致的basename参数错误
- **env status命令添加**: 新增`saltgoat env status`命令，完善环境配置管理

### 🆕 新功能
- **每日更新检测**: 新增`daily-update-check`自动化任务，每天上午8点自动检测系统更新
- **智能更新通知**: 更新检测脚本支持邮件通知和详细日志记录
- **模块化文档**: 为所有8个模块创建了完整的README文档
- **Help菜单完善**: 更新了主help菜单，添加了遗漏的功能分类

### 📚 文档完善
- **模块README**: 为diagnose、profile、version-lock、monitoring、maintenance、optimization、security、automation模块创建了详细文档
- **功能说明**: 每个模块都包含使用方法、示例、配置说明和注意事项
- **交叉引用**: 模块间功能的相关引用和链接

### 🔍 测试覆盖
- **全面命令测试**: 测试了26个主要命令，96.2%的命令正常工作
- **问题修复验证**: 验证了所有修复的功能都正常工作
- **自动化任务测试**: 测试了新增的每日更新检测功能

### 🎯 技术改进
- **状态检测优化**: 改进了服务状态检测逻辑，支持systemd和手动启动两种方式
- **错误处理增强**: 改进了Salt命令调用的错误处理和输出解析
- **代码质量提升**: 修复了ShellCheck警告，提高了代码质量

## [0.5.7] - 2025-01-21

### 🚨 故障诊断功能
- **智能诊断系统**: 新增 `saltgoat diagnose` 命令，支持nginx、mysql、php、system、network诊断
- **问题检测**: 自动检测服务状态、配置错误、端口冲突、权限问题等
- **修复建议**: 为每个发现的问题提供具体的修复建议和命令
- **完整诊断**: 支持 `saltgoat diagnose all` 进行完整系统诊断

### 🔒 版本锁定功能
- **核心软件锁定**: 新增 `saltgoat version-lock` 命令，锁定核心LEMP软件版本
- **智能锁定策略**: 锁定Nginx、Percona、PHP、RabbitMQ、OpenSearch、Valkey、Varnish、Composer
- **安全更新**: 允许系统内核和安全补丁正常更新
- **版本管理**: 支持锁定、解锁、查看锁定状态等操作

### 🔧 技术改进
- **诊断模块**: 完善的服务状态检查和配置验证
- **版本控制**: 使用apt-mark进行软件包版本锁定
- **智能建议**: 根据锁定状态提供不同的更新建议
- **配置管理**: 自动创建版本锁定配置文件

### 🐛 错误修复
- 修复PHP扩展检查中的包名匹配问题
- 修复诊断摘要显示格式问题
- 完善版本状态检查的准确性

## [0.5.6] - 2025-01-21

### 🐛 错误修复
- **修复help功能**: 修复主脚本中缺少`lib/help.sh`加载的问题
- **完善帮助系统**: 确保所有22个功能的帮助信息都能正常显示
- **功能验证**: 验证help、status等基础功能的完整性

### 🔧 技术改进
- **库文件加载**: 完善主脚本的库文件加载顺序
- **错误处理**: 改进脚本的错误处理和调试信息
- **功能测试**: 增强功能测试和验证机制

## [0.5.5] - 2025-01-21

### 🎯 SaltGUI集成完善
- **官方样板配置**: 采用SaltGUI官方推荐的Nginx配置模板
- **API路径优化**: 使用`/api/`路径代理Salt API，符合官方最佳实践
- **会话管理**: 完善SaltGUI的登录和会话管理功能
- **一致性保证**: 确保git clone后安装的配置完全一致

### 🔧 技术改进
- **Nginx配置**: 使用官方样板，简化配置结构
- **API代理**: 优化Salt API的代理配置
- **配置模板**: 自动配置SaltGUI的API_URL设置
- **服务管理**: 完善Salt Master和Salt API的配置

### 🐛 错误修复
- 修复SaltGUI登录后的会话管理问题
- 修复Salt API的netapi_enable_clients配置
- 修复Nginx配置中的location规则冲突
- 完善SaltGUI的安装脚本一致性

## [0.5.4] - 2025-01-21

### 📧 邮件配置功能增强
- **新增reload-env命令**: 添加 `saltgoat system reload-env` 命令，支持重新加载环境变量
- **自动Postfix配置**: 环境变量更新后自动重新配置Postfix SMTP设置
- **邮件配置诊断**: 显示当前邮件配置状态，便于问题排查
- **TLS安全增强**: 改进SMTP TLS配置，支持Microsoft 365和Gmail等主流邮件服务商

### 🔧 系统管理改进
- **环境变量管理（已废弃）**: 旧版本支持通过 `.env` 文件管理邮件配置
- **配置一致性**: 确保Postfix配置与环境变量保持同步
- **错误处理**: 改进邮件配置错误处理和诊断信息

### 🐛 错误修复
- 修复Postfix relayhost配置格式问题
- 修复邮件被当作本地邮件处理的问题
- 改进SMTP认证配置，支持多种邮件服务商

## [0.5.3] - 2025-01-21

### 📧 邮件配置一致性改进
- **跨服务器一致性**: 修复邮件配置硬编码问题，支持环境变量和Salt Pillar管理
- **环境变量支持**: 添加SMTP_HOST、SMTP_USER、SMTP_PASSWORD等环境变量
- **Salt Pillar集成**: 邮件配置通过Salt Pillar动态管理，确保配置一致性
- **多服务商支持**: 支持Gmail、Microsoft 365等主流邮件服务商
- **可选安装**: Postfix和邮件功能作为可选组件，不强制要求

### 🔧 配置改进
- **Postfix配置**: 使用Salt模板和Pillar数据，自动适应不同服务器环境
- **SASL认证**: 动态配置SMTP认证，支持TLS加密传输
- **Grafana集成**: 邮件通知配置支持环境变量，提升易用性
- **安装指南**: 更新INSTALL.md，添加邮件配置说明

### 🐛 错误修复
- 修复邮件配置硬编码问题
- 改进Postfix配置模板，支持条件配置
- 优化Grafana邮件配置功能，支持环境变量

## [0.5.2] - 2025-01-21

### 🔧 配置一致性改进
- **跨服务器一致性**: 修复硬编码路径问题，确保在不同服务器上安装后配置完全一致
- **动态路径检测**: 改进SaltGoat版本检测，支持任意安装路径
- **Salt Grain配置**: 添加动态项目目录设置，支持灵活的安装位置
- **安装指南**: 新增详细的跨服务器安装指南 (INSTALL.md)

### 🐛 错误修复
- 修复consistency-test.sh中硬编码 `/home/doge/saltgoat` 路径的问题
- 修复mysql.sls中硬编码pillar路径的问题
- 改进路径检测逻辑，支持系统安装和源码安装两种模式

### 📚 文档改进
- **新增INSTALL.md**: 详细的跨服务器安装指南
- **一致性测试**: 完善配置一致性验证机制
- **安装流程**: 标准化安装流程，确保一致性

## [0.5.1] - 2025-01-21

### 🔧 监控系统改进
- **自动依赖安装**: Prometheus安装时自动安装Node Exporter和Nginx Exporter
- **Nginx监控修复**: 修复Nginx Exporter安装和配置问题
- **端口检测修复**: 修复监控集成脚本中的端口检测逻辑
- **业务场景检测**: 优化智能监控的业务场景检测显示

### 🐛 错误修复
- 修复Prometheus端口检测使用netstat而非ss的问题
- 修复Nginx Exporter需要status模块的配置问题
- 修复智能监控检测结果显示格式问题
- 修复监控集成脚本中日志函数调用问题

### 📊 监控功能增强
- **完整监控链路**: Prometheus + Grafana + Node Exporter + Nginx Exporter
- **自动配置**: 监控组件自动安装和配置
- **状态检查**: 实时监控所有组件的运行状态
- **防火墙管理**: 自动配置监控端口防火墙规则

## [0.5.0] - 2025-01-21

### 🚀 重大功能更新
- **监控集成系统**: 新增完整的Prometheus和Grafana监控集成
- **防火墙自动配置**: 智能检测并配置UFW、Firewalld、iptables防火墙
- **状态管理系统**: 新增Salt状态管理功能，支持状态列表、应用和回滚
- **代码质量工具**: 集成shellcheck代码检查和shfmt代码格式化

### 🔧 监控集成功能
- **Prometheus集成**: `saltgoat monitoring prometheus` - 自动安装配置Prometheus
- **Grafana集成**: `saltgoat monitoring grafana` - 自动安装配置Grafana仪表板
- **Node Exporter**: 自动安装系统监控组件
- **智能端口配置**: 自动放行9090、3000、9100端口
- **IPv4地址显示**: 显示实际服务器IP而非localhost

### 🛡️ 防火墙管理
- **多防火墙支持**: 自动检测UFW、Firewalld、iptables
- **智能端口放行**: 自动配置监控服务端口
- **防火墙状态检查**: 实时检查端口放行状态
- **跨平台兼容**: 支持Ubuntu、CentOS、Debian等发行版

### 📊 状态管理
- **状态列表**: `saltgoat state list` - 查看所有可用状态
- **状态应用**: `saltgoat state apply <name>` - 应用特定状态
- **状态回滚**: `saltgoat state rollback <name>` - 回滚到之前状态
- **自动备份**: 应用状态前自动创建备份
- **状态检查**: 显示服务状态和配置文件状态

### 🔍 代码质量
- **代码检查**: `saltgoat lint [file]` - 使用shellcheck检查代码
- **代码格式化**: `saltgoat format [file]` - 使用shfmt格式化代码
- **安全扫描**: `saltgoat security-scan` - 完整的安全扫描分析

### 🎯 用户体验提升
- **智能帮助系统**: 新增监控集成帮助页面
- **配置一致性**: 增强跨服务器配置一致性
- **IPv4地址显示**: 所有访问地址显示实际IP
- **防火墙状态**: 实时显示防火墙配置状态

### 📋 技术改进
- **模块化设计**: 监控集成功能独立模块化
- **错误处理**: 增强错误处理和调试信息
- **路径检测**: 改进配置文件路径自动检测
- **服务检测**: 优化服务状态检测逻辑

### 🎉 新增访问地址
- **Prometheus**: http://your-server-ip:9090
- **Grafana**: http://your-server-ip:3000 (admin/admin)
- **Node Exporter**: http://your-server-ip:9100/metrics

### 📊 推荐仪表板
- Node Exporter: 1860
- Nginx: 12559
- MySQL: 7362
- Valkey: 11835

## [0.4.4] - 2025-01-21

### 🐛 重要修复
- **Nginx配置语法错误修复**: 修复了`optimize magento`功能中Nginx `gzip_types`指令的语法错误
- **智能配置检测**: 改进了对不完整Nginx配置的检测和修复逻辑
- **配置一致性增强**: 确保在不同Nginx安装环境下都能正确处理配置

### 🔧 技术改进
- **智能gzip_types处理**: 自动检测`gzip_types`是否完整，并智能修复不完整的配置
- **错误恢复机制**: 增强了配置备份和恢复功能
- **sed命令优化**: 改进了多行配置的处理逻辑，避免语法错误

### 📋 修复详情
- 修复了`nginx: [emerg] unknown directive "text/plain"`错误
- 修复了`gzip_types`指令被错误分割的问题
- 改进了配置检测逻辑，支持各种Nginx配置格式
- 增强了错误处理和调试信息

### 🎯 用户体验
- **更稳定的优化**: `saltgoat optimize magento`现在更加稳定可靠
- **更好的错误处理**: 提供更清晰的错误信息和恢复建议
- **跨平台兼容**: 支持各种Nginx安装方式和配置格式

## [0.4.3] - 2025-01-21

### 🚀 重大改进
- **Magento优化配置一致性**: 大幅改进了`optimize magento`功能的跨平台兼容性
- **自动路径检测**: 支持多种Nginx和PHP安装路径的自动检测
- **灵活配置匹配**: 使用正则表达式匹配各种配置值格式，适应不同系统环境

### 🔧 功能增强
- **Nginx配置优化**: 自动检测配置文件路径（支持`/etc/nginx/nginx.conf`）
- **PHP版本自动检测**: 支持PHP 8.3, 8.2, 8.1, 8.0, 7.4的自动检测和配置
- **服务名称自动识别**: 自动检测PHP-FPM服务名称和可执行文件路径
- **错误处理改进**: 提供更清晰的错误信息和调试输出

### 📋 用户体验提升
- **透明化操作**: 显示检测到的配置文件路径和服务信息
- **调试信息**: 提供详细的系统检测和配置过程信息
- **一致性保证**: 确保在不同服务器上获得相同的优化效果

### 🛠️ 技术改进
- 使用动态路径检测替代硬编码路径
- 改进的配置匹配算法，支持多种格式
- 增强的错误处理和用户反馈机制
- 更好的跨平台兼容性

## [0.4.2] - 2025-01-21

### 🔧 修复和改进
- **磁盘监控修复**: 修复了`du`命令在Salt调用中的参数解析问题，现在可以正确显示目录大小统计
- **SSL证书生成优化**: 改进了证书生成函数的错误处理和权限检查，提高稳定性
- **监控PID显示修复**: 修复了服务监控中PID获取和显示逻辑，现在可以正确显示进程信息
- **系统维护功能优化**: 将系统更新检查改为直接使用`apt`命令，避免Salt超时问题

### 🐛 错误修复
- 修复了磁盘监控中`du: invalid option -- 'r'`和`du: invalid option -- '1'`错误
- 修复了SSL证书生成时的权限和错误处理问题
- 修复了监控功能中`error: list of process IDs must follow -p`错误
- 修复了系统更新检查超时问题

### 📦 技术改进
- 将部分Salt调用改为直接系统命令，提高性能和稳定性
- 优化了错误处理机制，提供更好的用户体验
- 改进了命令参数解析，避免Shell解析问题

---

## [0.4.1] - 2025-10-21

### 🔧 修复和改进
- **templates文件夹**: 重新创建了templates文件夹，用于存放自动化任务模板
- **文档完善**: 添加了templates文件夹的详细说明文档
- **功能验证**: 确认templates功能正常工作

### 📦 新增内容
- templates/README.md - 模板文件说明文档
- 支持自动化任务模板管理
- 完善的项目结构

### 🐛 错误修复
- 修复了templates文件夹被误删的问题
- 确保所有功能模块完整

---

## [0.4.0] - 2025-10-20

### 🚀 主要更新
- **性能优化**: 大幅提升SaltGoat运行速度，减少Salt调用次数
- **警告消除**: 修复了所有Salt警告和DeprecationWarning消息
- **用户体验**: 改进了命令输出格式和错误处理

### 🔧 修复和改进
- **状态检查**: 使用`systemctl`直接检查服务状态，避免Salt调用
- **数据库管理**: 优化MySQL数据库操作，使用直接命令替代Salt模块
- **服务管理**: 改进服务重启、启动、停止等操作
- **日志权限**: 修复Salt日志权限问题

### 📦 新增内容
- 支持Percona Server 8.4优化配置
- 改进的MySQL状态检查功能
- 优化的Valkey密码管理
- 完善的错误处理机制

### 🐛 错误修复
- 修复了Salt日志权限警告
- 修复了MySQL插件加载问题
- 修复了Valkey认证问题
- 修复了服务管理中的Salt警告

---

## [0.3.0] - 2025-10-19

### 🚀 主要更新
- **Web服务器**: 完整的Nginx 1.29.1 + ModSecurity v3编译安装
- **安全测试**: 全面的ModSecurity攻击测试和模拟器
- **Salt状态**: 完整的Salt状态文件管理

### 🔧 新增功能
- Nginx 1.29.1源码编译安装
- ModSecurity v3集成
- OWASP Core Rule Set (CRS)支持
- 完整的Web服务器Salt状态文件
- ModSecurity攻击测试脚本
- 安全威胁模拟器

### 📦 技术改进
- 支持动态模块加载
- 完整的SSL/TLS配置
- 优化的Nginx配置模板
- 系统服务管理

---

## [0.2.0] - 2025-10-18

### 🚀 主要更新
- **数据库管理**: 完整的MySQL/Percona支持
- **缓存系统**: Valkey (Redis兼容)集成
- **搜索引擎**: OpenSearch支持
- **消息队列**: RabbitMQ集成

### 🔧 新增功能
- MySQL/Percona数据库管理
- Valkey缓存系统
- OpenSearch搜索引擎
- RabbitMQ消息队列
- 数据库备份和恢复
- 性能监控

### 📦 技术改进
- 优化的数据库配置
- 完整的服务管理
- 监控和日志系统
- 自动化部署

---

## [0.1.0] - 2025-10-17

### 🚀 初始版本
- **基础框架**: SaltGoat核心功能
- **服务管理**: Nginx、PHP-FPM基础支持
- **Salt集成**: 完整的Salt状态管理
- **用户界面**: 命令行工具

### 🔧 核心功能
- Salt状态文件管理
- 基础服务安装和配置
- 命令行工具界面
- 日志和监控系统
- 配置文件管理

### 📦 技术特性
- 模块化设计
- Salt原生功能
- 自动化部署
- 错误处理机制
# [Unreleased]

### ⚙️ 配置管理
- 取消 `.env` 流程，统一通过 `salt/pillar/saltgoat.sls` 管理凭据
- 安装脚本安全写入 Pillar（无 `/tmp` 权限问题），安装总结直接展示版本/状态/密码
- 新增 `saltgoat pillar` 子命令（init/show/refresh）与 `saltgoat passwords --refresh` 辅助同步
- 更新维护脚本、RabbitMQ/Valkey 工具及文档以使用 Pillar 默认值
- 新增 `optional.salt-beacons` / `optional.salt-reactor` 状态与 `saltgoat monitor enable-beacons` 命令，实现服务/资源 Beacon 与自动恢复
- `optional.magento-schedule` 改为优先使用 Salt Schedule，缺少 `salt-minion` 时自动降级为 `/etc/cron.d/magento-maintenance`

### 🧪 验证
- 新增 `tests/test_magento_optimization.sh` 并在 CI 执行 Dry-run，确保 Magento 优化 State 可渲染

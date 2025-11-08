# Operations Tooling

SaltGoat 现在自带几套易用的小工具，方便在排障或上线演练时快速验证环境。本篇记录它们的用法。

## Varnish 回归验证
- **脚本**：`tests/test_varnish_regression.sh`
- **用途**：对指定站点依次执行 `varnish enable/disable`，每个阶段都会 `curl -I` 校验 200 响应，并在结束后将站点恢复为最初的状态。
- **示例**：
  ```bash
  sudo tests/test_varnish_regression.sh bank tank
  ```
- **注意**：脚本会调用 `saltgoat magetools varnish`，请确保目标站点允许被短暂切换缓存拓扑。

## 健康面板
- **脚本**：`scripts/health-panel.sh`
- **用途**：输出常用 systemd 单元状态、站点 HTTP 探活、以及 `/var/www`、`/var/log` 等磁盘占用。
- **示例**：
  ```bash
  scripts/health-panel.sh bank tank
  ```
- **延伸**：`saltgoat fun status` 会自动调用此脚本，适合随手查看。

## Magento CLI 预检
- **脚本**：`tests/test_magento_cli_suite.sh`
- **用途**：以 `www-data` 身份顺序执行 `cache:status`、`app:config:status`、`indexer:info`、`setup:db:status` 等只读命令，验证 CLI 是否健康。
- **示例**：
  ```bash
  sudo tests/test_magento_cli_suite.sh /var/www/tank
  ```

## Fail2ban Watcher
- **脚本**：`modules/security/fail2ban_watch.py`
- **部署**：`optional.fail2ban-watch` 状态会将脚本安装至 `/opt/saltgoat-security/`，并创建 `saltgoat-fail2ban-watch.service` + `.timer`（默认每 5 分钟运行一次）。
- **功能**：记录每个 jail 的被封禁 IP，如出现新增 IP 会通过 Telegram 通知（沿用 `notifications.telegram` Pillar 配置）。
- **手动运行**：
  ```bash
  sudo /usr/bin/python3 /opt/saltgoat-security/fail2ban_watch.py --state /var/log/saltgoat/fail2ban-state.json
  ```

## SaltGoat Fun 命令
- **入口**：`saltgoat fun <action>`
- **子命令**：
  - `status [sites...]`：调用健康面板输出服务状态。
  - `joke`：随机输出山羊主题冷笑话。
  - `ascii`：打印 ASCII 山羊与提示。
  - `tip`：随机输出一个运维小贴士（会提示上述脚本的价值）。
  - `fortune`：输出 Goat Fortune（日志风格建议 + 推荐操作）。
  - **帮助**：`saltgoat fun help`

## Goat Pulse 仪表盘
- **脚本**：`scripts/goat_pulse.py`
- **用途**：以 ASCII TUI 连续展示 systemd 服务状态、站点 HTTP 探活、Varnish 命中率和 Fail2ban 当前封禁，可同步产出 Prometheus textfile 指标。
- **示例**：
-  ```bash
-  python3 scripts/goat_pulse.py        # 5 秒刷新一次
-  python3 scripts/goat_pulse.py --once # 输出一次后退出
-  python3 scripts/goat_pulse.py -i 2   # 自定义刷新间隔
-  python3 scripts/goat_pulse.py --metrics-file /var/lib/node_exporter/textfile/saltgoat.prom
-  python3 scripts/goat_pulse.py --once --plain > /tmp/goat-pulse.txt
-  ```
- **提示**：默认输出包含 ANSI 清屏控制符，需落盘/嵌入其他脚本时可追加 `--plain`；`--metrics-file` 会同步写入 Prometheus textfile 指标（配合 node_exporter textfile collector），一次命令即可兼顾终端巡检与监控采集。
- **自动化**：`sudo salt-call state.apply optional.goat-pulse` 会安装 `/opt/saltgoat-monitoring/goat_pulse.py` 与 `saltgoat-goatpulse.service/timer`，每小时将 `--plain --telegram` 摘要推送到 Telegram 并维护 `/var/lib/saltgoat/goat-pulse.prom` 指标文件。

## 快速自检（Verify / Doctor）
- **`saltgoat verify` / `scripts/verify.sh`**：一次性运行 `bash scripts/code-review.sh -a` 与 `python3 -m unittest`，在提交前或 CI 流水线中快速确认 Shell 风格与 Python 单元测试通过。
- **`saltgoat doctor` / `scripts/doctor.sh`**：调用 Goat Pulse（自动加 `--plain --once`）、磁盘/进程摘要、最近 `alerts.log`，并支持 `--format text|json|markdown`，用于粘贴、自动化采集或生成富文本报告。
- **`saltgoat smoke-suite` / `scripts/smoke-suite.sh`**：一次性执行 `verify`、`monitor auto-sites --dry-run`、`monitor quick-check` 与 `doctor --format markdown`，并将体检报告保存到 `/tmp/saltgoat-doctor-*.md`，适合上线前的人工冒烟。
- **示例**：
  ```bash
  sudo saltgoat verify
  sudo saltgoat doctor --format markdown > /tmp/doctor.md
  ```
- **提示**：可以在两个脚本中追加自定义检查（例如 `saltgoat monitor auto-sites --dry-run`）以适配团队流程；Doctor 的 Markdown/JSON 输出也适合粘贴到飞书/Slack/工单系统。

## GitOps Watch
- **脚本**：`scripts/gitops-watch.sh`
- **入口**：`saltgoat gitops-watch`
- **用途**：串行执行 `saltgoat verify` 与 `saltgoat monitor auto-sites --dry-run`，最后调用 `modules/lib/gitops.py` 检查 Git 配置漂移，确保 Shell/Python 测试通过、站点探测 Pillar 可成功生成且工作区保持与上游一致。
- **推荐场景**：作为 Git pre-push 钩子或 CI 步骤，及时发现 Pillar 缺失、站点配置错误等问题。
- **示例**：
  ```bash
  sudo saltgoat gitops-watch
  ```
- **输出示例**：
  ```text
  [2025-11-05T04:50:12+00:00] Running saltgoat verify -- dry-run
  ...
  [2025-11-05T04:52:31+00:00] Checking GitOps drift
  Branch: master
  Upstream: origin/master
  Ahead: 0
  Behind: 2
  Working tree changes:
    M docs/ops-tooling.md
  ```
- **处理建议**：若 `Behind > 0` 先 `git pull --rebase origin master`，`Ahead > 0` 时与团队确认再推送；如列表出现 `__pycache__/` 或 `*.pyc`，执行 `git rm --cached <file>`（脚本已自动阻断后续发布）。

## Pillar / Event Helper
- `modules/lib/monitor_auto_sites.py`：独立执行站点探测与 `salt/pillar/monitoring.sls` 生成任务，支持 `--site-root`、`--nginx-dir`、`--monitor-file`、`--skip-systemctl` 等参数；CLI `saltgoat monitor auto-sites` 正是调用此脚本完成检测。
- `modules/lib/nginx_context.py site-metadata`：统一输出站点元数据（root/server_name/Varnish/HTTPS/run context），现已被 `monitor auto-sites` 与 `magetools varnish` 消费，也方便第三方脚本直接解析。
- `modules/lib/nginx_pillar.py`：纯 Python CLI 管理 `salt/pillar/nginx.sls`（`create/delete/enable/disable/ssl/csp-level/modsecurity-level/list`），供 `saltgoat nginx` 及外部自动化共用。示例：
  ```bash
  python3 modules/lib/nginx_pillar.py --pillar salt/pillar/nginx.sls create \
    --site bank --domains bank.example.com tank.example.com --root /var/www/bank --magento
  python3 modules/lib/nginx_pillar.py --pillar salt/pillar/nginx.sls ssl \
    --site bank --domain bank.example.com --email admin@bank.example.com
  python3 modules/lib/nginx_pillar.py --pillar salt/pillar/nginx.sls modsecurity-level \
    --level 5 --enabled 1 --admin-path /admin_tattoo
  ```
- `modules/lib/pwa_helpers.py`：除 package.json 操作外，提供 `load-config`（解析 `magento-pwa.sls`）、`ensure-env-default`、`patch-product-fragment`、`sanitize-checkout`、`remove-line`、`add-guard`、`tune-webpack`、`check-react`、`validate-graphql` 等子命令，统一替换 `modules/pwa/install.sh` 中的内嵌 Python。常用示例：
  ```bash
  python3 modules/lib/pwa_helpers.py load-config --config salt/pillar/magento-pwa.sls --site bank
  python3 modules/lib/pwa_helpers.py ensure-env-default --file /var/www/bank/pwa-studio/.env --key MAGENTO_BACKEND_EDITION --value MOS
  python3 modules/lib/pwa_helpers.py patch-product-fragment --file packages/peregrine/lib/talons/RootComponents/Product/productDetailFragment.gql.js
  python3 modules/lib/pwa_helpers.py check-react --dir /var/www/bank/pwa-studio
  python3 modules/lib/pwa_helpers.py validate-graphql --payload '{"data":{"storeConfig":{"store_name":"Demo"}}}'
  ```
- `notifications.webhook` Pillar 字段允许声明 `endpoints: [{name,url,headers}]`，Pipe 会在 `magento_api_watch`、`magento_summary`、`resource_alert`、`backup_notify`、每日巡检等动作触发时，同步向 HTTP Endpoint POST JSON（与 Telegram 内容一致）。
- `modules/lib/salt_event.py`：`send` 子命令优先通过 `salt.client.Caller` 发送事件，失败时会将 JSON payload 写到 STDOUT 并以退出码 `2` 提示 shell 走 `salt-call event.send` 兜底；`format` 子命令可单独渲染 JSON。
- `modules/lib/maintenance_pillar.py`：将 `saltgoat magetools maintenance` 的环境变量转换成 Pillar JSON，方便调试或直接喂给 `salt-call`. 示例：`SITE_NAME=bank SITE_PATH=/var/www/bank python3 modules/lib/maintenance_pillar.py`.
- `modules/lib/automation_helpers.py`：统一解析 `saltgoat automation_*` 返回的 JSON，提供 `render-basic`（输出 comment 并携带退出码）、`extract-field <name>`、`parse-paths` 三个子命令，在 shell 脚本中可复用与 Salt CLI 相同的解析逻辑。
- `notifications.webhook` Pillar 字段允许声明 `endpoints: [{name,url,headers}]`。启用后，每条通知（订单/客户、备份、resource_alert、daily_summary 等）都会在 Telegram 之外 POST 一份 JSON 到目标系统（Mattermost、Slack、ntfy 等）。调试时可运行：
  ```bash
  sudo python3 modules/lib/backup_notify.py mysql --status success --database demo --site bank --path /tmp/demo.sql.gz --size 10M
  sudo python3 modules/magetools/magento_summary.py --site bank --period daily --no-telegram
  ```
  然后在 Webhook 目标内确认是否收到相应事件。
- 也可以使用 `scripts/notification-test.py` 快速发一条人工消息，无需触发真实任务：
  ```bash
  python3 scripts/notification-test.py \
    --tag saltgoat/test/ping \
    --severity INFO \
    --text "Webhook diagnostics from $(hostname -f)" \
    --webhook-only
  ```
  默认读取 `salt/pillar/notifications.sls`（或通过环境变量 `SALTGOAT_NOTIFICATIONS_FILE` 指定），便于在 CI/本地没有 Salt Caller 时也能测试。

## Runtime 自愈配置
- `/etc/saltgoat/runtime/mysql-autotune.json`：`resource_alert.py` 检测到 `Threads_connected / max_connections` 超过 95% 时提升 `max_connections`，写入该文件并触发 `optional.magento-optimization`，随后由 Salt 调整 MySQL/Percona 配置。
- `/etc/saltgoat/runtime/valkey-autotune.json`：当 Valkey `used_memory / maxmemory` > 93% 时自动放大 `maxmemory`（上限为物理内存的 75%），同时即时执行 `CONFIG SET maxmemory ...`，并在下一次优化 State 中持久化。
- `/etc/saltgoat/runtime/opensearch-autotune.json`：新增的 OpenSearch 缓存控制。当 JVM heap > 85% 时等比例收紧 `indices.memory.index_buffer_size`、`queries.cache.size`、`fielddata.cache.size`；当 heap < 55% 且较为闲置时会逐步放宽缓存，提升搜索吞吐。所有动作都会写入 alerts.log、Telegram autoscale 话题，并自动重跑 `optional.magento-optimization` 以重新渲染 `/etc/opensearch/opensearch.yml`。
- `/etc/saltgoat/runtime/php-fpm-pools.json`：记录自动扩容的 `pm.max_children`/`spare_servers`，避免在下一次 `state.apply core.php` 时被覆盖。

## 自动化路线图（草案）
- **对象存储模块**：封装 MinIO/兼容 S3 的部署与备份策略，配合现有备份通知。
- **Telegram 话题过滤**：在 `setup-telegram-topics.py` 中过滤隐藏目录（如 `.cache/`）、支持按站点显式列表，避免噪音话题。
- **Shell → Python 拆分**：持续清理剩余 `here-doc`（例如 `modules/pwa/install.sh` 中针对 SQL/配置的片段、`modules/analyse` 里的 inline Python），避免费力逻辑散落在 Bash 中，确保所有复杂操作集中在 `modules/lib/*.py` 并覆盖单测。
- **扩展监控自愈**：评估扩展到对象存储、Varnish 状态、MinIO 容量告警等场景，与现有 `resource_alert` 协同。

## MinIO 对象存储（快速开始）
- Pillar：复制 `salt/pillar/minio.sls.sample` 为 `salt/pillar/minio.sls`，填入 `image`、`base_dir`、`data_dir`、`bind_host`、`api_port`、`console_port`、`root_credentials` 等信息；`extra_env` 可注入额外 `MINIO_*` 环境变量。
- 安装：`saltgoat minio apply` 渲染 `/opt/saltgoat/docker/minio/docker-compose.yml` 并启动容器，默认仅在宿主 `127.0.0.1:9000/9001` 暴露端口。建议通过 Traefik 或宿主 Nginx 自动生成透传配置并申请证书。
- 当 `traefik.api`/`traefik.console` 的 `tls.enabled` 为 false 时，会自动写入 `nginx:sites:minio-api|minio-console`、生成对应透传配置，并在证书缺失时调用 `saltgoat nginx add-ssl` 自动申请。
- 若 `traefik:api|console` 的 `tls.enabled` 为 false，State 会自动生成 `nginx:sites:minio-{api,console}`、渲染对应透传配置，并在证书缺失时调用 `saltgoat nginx add-ssl` 完成申请。
- 运维：`saltgoat minio status|logs|restart` 分别包装了 `docker compose ps/logs/up --force-recreate`，便于排查与滚动升级。
- 健康检查：`saltgoat minio health` 读取 Pillar 中的 `health.*` 设置访问 `/minio/health/live`，可写入 Salt Schedule / Cron。
- 后续规划详见 `docs/roadmap-object-storage.md`，包括与 Restic/通知集成、容量监控、自愈策略等。

## Docker + Traefik
- Pillar：依据 `salt/pillar/docker.sls.sample` 的 `docker:traefik` 节配置 `base_dir`、`image`、映射端口（默认 HTTP 18080、HTTPS 18443、Dashboard 19080）、ACME 参数、额外 `command`/`environment` 等。
- 安装：`saltgoat traefik install` 会依次套用 `optional.docker` 与 `optional.docker-traefik`，在 `/opt/saltgoat/docker/traefik` 渲染 docker-compose.yml 与 `config/traefik.yml`，并自动清理旧版 Nginx Proxy Manager 目录以及 `/etc/nginx/conf.d/proxy-*` 透传文件。
- 运行维护：
  1. `saltgoat traefik status|logs|restart|down`：分别查看 compose ps、最近日志、重启或停止容器。
  2. `saltgoat traefik config`：输出当前 `traefik.yml`（入口/ACME/Dashboard 配置），便于排查静态选项。
  3. `saltgoat traefik cleanup-legacy`：单独执行可再次移除遗留的 NPM 目录或宿主 Nginx 透传配置，确保环境干净。
- 域名暴露：Traefik 监听在 127.0.0.1:18080/18443，SaltGoat 的相关 CLI（如 Mattermost、MinIO 等）会自动生成宿主 Nginx server block，把公网 80/443 流量透传至 Traefik，并使用 `saltgoat nginx add-ssl` 申请证书。也可以在 Pillar 开启 ACME 支持，让 Traefik 直接处理 HTTP-01/TLS-ALPN/DNS-01 挑战。

## 服务总览工具
- `saltgoat services`：汇总已部署服务（MySQL、Valkey、RabbitMQ、MinIO、Webmin、Traefik、Cockpit 等），输出访问地址/端口及 Pillar 中配置的默认凭据，方便交接或巡检；支持 `--format json` 供脚本消费。执行时建议使用 `sudo` 以读取受限的 Pillar 文件。

## Mattermost 协作平台
- Pillar：复制 `salt/pillar/mattermost.sls.sample`，设置 `site_url`、`domain`、`http_port`、`admin.*`（首次启动管理员）与 `db.*`、`smtp.*` 等字段；`extra_env` 可追加任意 `MM_*` 环境变量，`file_store.type` 设为 `s3` 时可搭配 MinIO。`mattermost:traefik` 节可声明 router 名称、entrypoints、TLS 解析器与 `extra_labels`，Salt 会据此生成 Traefik labels。
- 部署：`saltgoat mattermost install` 会渲染 `/opt/saltgoat/docker/mattermost/docker-compose.yml` 与 `.env`，创建数据/日志/插件/Postgres 目录并执行 `docker compose up -d`。
- 管理：`saltgoat mattermost status|logs|restart|upgrade` 分别查看容器状态、尾日志（默认 200 行）、重启或拉取最新镜像。
- 暴露入口：搭配 `saltgoat traefik install` 部署统一入口后，可由相关 CLI 自动生成宿主 Nginx → Traefik 的透传配置并申请证书，或者在 Traefik Pillar 中启用 ACME，让其直接处理 HTTP-01/TLS-ALPN。
- 备份：Postgres 数据位于 `/opt/saltgoat/docker/mattermost/db`，应用文件/日志位于 `data|config|logs|plugins` 目录，可用现有备份脚本（如 Restic）纳入策略。

## Mastodon 多站点社交
- Pillar：复制 `salt/pillar/mastodon.sls.sample`，在 `mastodon.instances` 下为每个站点定义 `domain`、`base_dir`、`postgres.*`、`redis.*`、`smtp.*`、`storage.*` 与 `traefik.*`。未填写时会自动落到 `/opt/saltgoat/docker/mastodon-<site>`、`/srv/mastodon/<site>/uploads` 等默认目录。`traefik.aliases` 支持多域名，`extra_env` 可追加任何 Mastodon 运行时变量。
- 部署：`saltgoat mastodon install bank` 会同步 Pillar → `salt/pillar/nginx.sls`，渲染 `/opt/saltgoat/docker/mastodon-bank/docker-compose.yml`、`.env.production`、`.secrets.env` 并执行 `docker compose up -d`，同时运行 `bundle exec rake db:migrate`、`assets:precompile` 和 `tootctl domains add`。
- 管理：`saltgoat mastodon status|logs|restart|pull|upgrade <site>` 提供常规运维操作；`backup-db` 会触发容器内 `pg_dump`，通过管道写入 `storage.backups_dir` 下的时间戳文件（gzip 压缩），便于再配合 Restic/MinIO 同步。
- 证书：若 `traefik.tls.enabled=false`，CLI 会在部署后自动调用 `saltgoat nginx add-ssl mastodon-<site> <domain>`，沿用 Nginx + Let's Encrypt 的申请流程；也可在 Traefik Pillar 启用 ACME，让 Traefik 直接处理 TLS。
- 入口：默认通过 Traefik label 暴露，仍保留宿主 Nginx 透传能力（`optional.mastodon` state 会生成 `/etc/nginx/sites-available/mastodon-<site>`，将 80/443 流量转发至 Traefik HTTP 端口）。
- 储存：媒体文件持久化到 `storage.uploads_dir`，数据库与 Redis 数据分别挂载到 `base_dir/postgres`、`base_dir/redis`。可配合 Restic/MinIO 定制定时任务，同步媒体与数据库备份。

## Uptime Kuma 监控面板
- Pillar：复制 `salt/pillar/uptime_kuma.sls.sample` 为 `salt/pillar/uptime_kuma.sls`，可覆盖 `base_dir`、`bind_host`、`http_port`、镜像版本与额外环境变量；`traefik` 节支持声明域名、entrypoints、TLS 解析器和额外 label，方便自动挂到 Traefik。
- 部署：`saltgoat uptime-kuma install` 会清理旧版 systemd 安装（停止/移除 `/opt/uptime-kuma`），在 `/opt/saltgoat/docker/uptime-kuma` 渲染 docker-compose 并执行 `docker compose up -d`（默认监听 127.0.0.1:3001）。
- 运维：`saltgoat uptime-kuma status|logs|restart|down|pull` 分别查看容器状态、读取日志、重建/停止容器以及拉取最新镜像；升级流程推荐 `pull` 后紧接 `restart`。
- 证书与入口：结合 `saltgoat traefik install` 后，通过 Pillar 配置的 Traefik label 自动获得路由/TLS；也可保留监听 127.0.0.1，通过宿主 Nginx 透传。
- 若 `traefik.tls.enabled` 为 false，State 会自动写入 `nginx:sites:uptime-kuma`、生成透传配置并在证书缺失时调用 `saltgoat nginx add-ssl uptime-kuma <domain>`。
- 当 `traefik.tls.enabled` 为 false 时，State 自动生成宿主 Nginx 透传、补写 `nginx:sites:uptime-kuma`，并在证书缺失时调用 `saltgoat nginx add-ssl uptime-kuma <domain>`。

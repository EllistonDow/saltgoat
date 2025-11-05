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
    M docs/OPS_TOOLING.md
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

## 自动化路线图（草案）
- **对象存储模块**：封装 MinIO/兼容 S3 的部署与备份策略，配合现有备份通知。
- **Telegram 话题过滤**：在 `setup-telegram-topics.py` 中过滤隐藏目录（如 `.cache/`）、支持按站点显式列表，避免噪音话题。
- **Shell → Python 拆分**：持续清理剩余 `here-doc`（例如 `modules/pwa/install.sh` 中针对 SQL/配置的片段、`modules/analyse` 里的 inline Python），避免费力逻辑散落在 Bash 中，确保所有复杂操作集中在 `modules/lib/*.py` 并覆盖单测。
- **扩展监控自愈**：评估扩展到对象存储、Varnish 状态、MinIO 容量告警等场景，与现有 `resource_alert` 协同。

## MinIO 对象存储（快速开始）
- Pillar：复制 `salt/pillar/minio.sls.sample` 为 `salt/pillar/minio.sls`，补充 `listen_address`、`root_credentials`，如能提前拿到官方哈希可写入 `binary_hash`（支持 `sha256=<hash>` 格式）；`proxy.*` 字段控制 Nginx 反代域名、证书邮箱、ACME webroot 等。
- 安装：`saltgoat minio apply`（相当于 `state.apply optional.minio`）会创建用户/目录、生成 `.env`、下载并校验二进制、注册 `minio.service`。附带 `--domain minio.example.com [--console-domain console.example.com --ssl-email ops@example.com --no-console]` 时会自动写 Pillar、调用 `optional.certbot`、渲染 `/etc/nginx/sites-available/<site>` 与证书，完成 HTTPS 反代。
- 健康检查：`saltgoat minio health` 读取 Pillar 中的 `health.*` 设置调用 `/minio/health/live`，失败会返回非零退出码，适合写入 Salt Schedule / Cron。
- 资讯：`saltgoat minio info` 输出当前 Pillar 摘要（JSON），`saltgoat minio env` 可快速查看 `/etc/minio/minio.env`。
- 后续规划详见 `docs/ROADMAP_OBJECT_STORAGE.md`，包括与 Restic/通知集成、容量监控、自愈策略等。

## Docker + Nginx Proxy Manager
- Pillar：可选地依据 `salt/pillar/docker.sls.sample` 设置 `docker:npm`（安装路径、镜像版本、映射端口、数据库密码等）。
- 安装：`saltgoat proxy install` 会依次套用 `optional.docker`（Docker Engine + compose plugin）与 `optional.docker-npm`（在 `/opt/saltgoat/docker/npm` 渲染 docker-compose.yml 并执行 `docker compose up -d`）。默认端口：HTTP 8080、HTTPS 8443、面板 9181。
- 使用：
  1. 访问 https://<主机>:9181（初始账号 `admin@example.com / changeme`），修改密码后在 Proxy Hosts 中配置域名到实际服务。
  2. 运行 `saltgoat proxy add example.com` 生成 `/etc/nginx/conf.d/proxy-example.com.conf`，该 server block 自动包含 `/.well-known/acme-challenge/` 透传逻辑，让 Let’s Encrypt 校验直接落到 NPM (127.0.0.1:<http_port>)；NPM 内只需设置真实后端端口即可。
  3. 一旦证书在宿主 `/etc/letsencrypt/live/example.com/` 或 NPM 数据目录 `/opt/saltgoat/docker/npm/data/letsencrypt/live/<cert>/` 生成，重新执行 `saltgoat proxy add example.com`，脚本会自动引用 fullchain/privkey 并渲染 443 server。后续续期也只需在 NPM 中申请，宿主端重复运行 add 即可同步证书路径。
- 辅助命令：`saltgoat proxy remove <domain>`（同时清理旧目录遗留配置）、`saltgoat proxy list`、`saltgoat proxy status`（查看 docker compose ps）。适用于把 Goat Pulse、Fail2ban、MinIO Console、Mattermost 等零散服务统一纳管到 NPM，由其 UI/API 负责后端映射。

## 服务总览工具
- `saltgoat services`：汇总已部署服务（MySQL、Valkey、RabbitMQ、MinIO、Webmin、Nginx Proxy Manager、Cockpit 等），输出访问地址/端口及 Pillar 中配置的默认凭据，方便交接或巡检；支持 `--format json` 供脚本消费。执行时建议使用 `sudo` 以读取受限的 Pillar 文件。

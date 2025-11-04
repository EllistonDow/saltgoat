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
- **用途**：串行执行 `saltgoat verify` 与 `saltgoat monitor auto-sites --dry-run`，在提交/合并前确保 Shell/Python 测试通过且站点探测 Pillar 可成功生成。
- **推荐场景**：作为 Git pre-push 钩子或 CI 步骤，及时发现 Pillar 缺失、站点配置错误等问题。
- **示例**：
  ```bash
  sudo saltgoat gitops-watch
  ```

## Pillar / Event Helper
- `modules/lib/monitor_auto_sites.py`：独立执行站点探测与 `salt/pillar/monitoring.sls` 生成任务，支持 `--site-root`、`--nginx-dir`、`--monitor-file`、`--skip-systemctl` 等参数；CLI `saltgoat monitor auto-sites` 正是调用此脚本完成检测。
- `modules/lib/nginx_context.py site-metadata`：统一输出站点元数据（root/server_name/Varnish/HTTPS/run context），现已被 `monitor auto-sites` 与 `magetools varnish` 消费，也方便第三方脚本直接解析。
- `notifications.webhook` Pillar 字段允许声明 `endpoints: [{name,url,headers}]`，Pipe 会在 `magento_api_watch`、`magento_summary`、`resource_alert`、`backup_notify`、每日巡检等动作触发时，同步向 HTTP Endpoint POST JSON（与 Telegram 内容一致）。
- `modules/lib/salt_event.py`：`send` 子命令优先通过 `salt.client.Caller` 发送事件，失败时会将 JSON payload 写到 STDOUT 并以退出码 `2` 提示 shell 走 `salt-call event.send` 兜底；`format` 子命令可单独渲染 JSON。
- `modules/lib/maintenance_pillar.py`：将 `saltgoat magetools maintenance` 的环境变量转换成 Pillar JSON，方便调试或直接喂给 `salt-call`. 示例：`SITE_NAME=bank SITE_PATH=/var/www/bank python3 modules/lib/maintenance_pillar.py`.
- `modules/lib/automation_helpers.py`：统一解析 `saltgoat automation_*` 返回的 JSON，提供 `render-basic`（输出 comment 并携带退出码）、`extract-field <name>`、`parse-paths` 三个子命令，在 shell 脚本中可复用与 Salt CLI 相同的解析逻辑。

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
- **用途**：以 ASCII TUI 连续展示 systemd 服务状态、站点 HTTP 探活、Varnish 命中率和 Fail2ban 当前封禁。
- **示例**：
  ```bash
  python3 scripts/goat_pulse.py        # 5 秒刷新一次
  python3 scripts/goat_pulse.py --once # 输出一次后退出，便于采集
  python3 scripts/goat_pulse.py -i 2   # 自定义刷新间隔
  ```
- **提示**：输出包含 ANSI 清屏控制符，如需把结果转存成日志，可加 `--once` 并重定向到文件。

## Pillar / Event Helper
- `modules/lib/monitor_auto_sites.py`：独立执行站点探测与 `salt/pillar/monitoring.sls` 生成任务，支持 `--site-root`、`--nginx-dir`、`--monitor-file`、`--skip-systemctl` 等参数；CLI `saltgoat monitor auto-sites` 正是调用此脚本完成检测。
- `modules/lib/salt_event.py`：`send` 子命令优先通过 `salt.client.Caller` 发送事件，失败时会将 JSON payload 写到 STDOUT 并以退出码 `2` 提示 shell 走 `salt-call event.send` 兜底；`format` 子命令可单独渲染 JSON。
- `modules/lib/maintenance_pillar.py`：将 `saltgoat magetools maintenance` 的环境变量转换成 Pillar JSON，方便调试或直接喂给 `salt-call`. 示例：`SITE_NAME=bank SITE_PATH=/var/www/bank python3 modules/lib/maintenance_pillar.py`.
- `modules/lib/automation_helpers.py`：统一解析 `saltgoat automation_*` 返回的 JSON，提供 `render-basic`（输出 comment 并携带退出码）、`extract-field <name>`、`parse-paths` 三个子命令，在 shell 脚本中可复用与 Salt CLI 相同的解析逻辑。

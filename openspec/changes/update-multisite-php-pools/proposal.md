## Summary
Automate PHP-FPM pool sizing whenever Magento multisite helper creates or removes store views. The multisite CLI should recalculate per-site weights, update the Pillar driving `core.php-fpm-pools`, trigger the Salt state so new limits take effect, and publish an autoscale notification. This keeps bank-like multi-domain installations (duobank/treebank) from saturating the pool after each new store view.

## Motivation
- Bank 实例新增多个 store view（duobank, treebank）后，`magento-bank` 池仍保持旧的 `max_children`, 导致 `resource_alert` 频繁触发 CRITICAL 并重启 php-fpm。
- 目前 `salt/pillar/magento-optimize.sls` 的 `php_pool.weight` 只能人工调整，自动化缺口影响扩展体验。
- 我们已有一键多站点工具（`saltgoat magetools multisite`），是最佳挂钩点，可确保“新增/回滚 store view → FPM 池容量”形成闭环，并把动作写入通知日志。

## Goals
1. `saltgoat magetools multisite create|rollback` 在成功执行后自动更新对应站点的 PHP-FPM 池权重，并可根据 store view 数量计算合适的 `pm.max_children`。
2. 自动更新 Pillar（`magento_optimize:sites.<site>.php_pool.weight` 等），随后触发一次 `salt-call --local state.apply core.php` 让变更落地 `/etc/php/8.3/fpm/pool.d/` 与 `/etc/saltgoat/runtime/php-fpm-pools.json`。
3. 记录并广播此次自动调整（写 `/var/log/saltgoat/alerts.log` + 发送 `saltgoat/autoscale/<host>` 事件），包含旧/新权重、store 列表，方便追溯。
4. 通过 CLI 参数允许跳过或强制指定权重，兼容 `--dry-run`。

## Non-Goals
- 不实现完全基于实时流量的动态权重（此次只关注 store view 数量 / CLI 覆盖）。
- 不调整其他服务（MySQL、Valkey）容量。
- 不解决现有 `resource_alert` 中 `state.apply core.php` 失败的问题（但实现后应减少频繁 autoscale）。

## Impact
- **CLI**：`modules/magetools/multisite.sh` 增加新选项（默认启用自动调整）。
- **Helpers**：新增 `modules/lib/php_pool_helper.py`（示例）负责读取 store 列表、更新 Pillar、输出 JSON 供日志/通知使用。
- **Docs**：更新 `README.md` / `docs/monitoring-playbook.md` 说明多站点扩容会自动同步 PHP 池。
- **Specs**：新增 “magetools-multisite” 能力，描述 store view 扩容需触发 PHP 池权重计算与通知。

## Risks & Mitigations
- **Pillar 写入失败**：helper 应支持 `--dry-run` 和完整回滚提示，并在失败时阻止继续执行 state。
- **用户自定义权重**：提供 `--pool-weight` 参数；若检测到 Pillar 中已有显式 `max_children`，记录 warning 并仅通知不覆盖。
- **性能**：store list 通过一次 `php bin/magento store:list --format=json` 获取，避免多次 CLI 负载。

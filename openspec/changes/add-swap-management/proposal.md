## Summary
Introduce a first-class `saltgoat swap` command group to inspect, tune, and repair swap usage. The CLI will cover status output, interactive menu actions, swapfile create/resize/remove, kernel parameter tuning, and an "ensure" subcommand that other automation (e.g. resource_alert) can call for self-healing.

## Motivation
- 当前主机仅有 1 GiB swap，极易被被动换出填满，引发 `resource_alert` 持续告警。手工扩容需要多步命令（fallocate/mkswap/chmod/fstab/sysctl），对值班人员不友好。
- 缺少统一的 swap 状态面板与建议，无法快速判断 si/so、当前 swappiness、是否需要扩容。
- 没有 CLI 钩子让监控脚本自动尝试扩容或降低 swappiness，自愈只剩下“重启 php-fpm”这一种方式。
- 需要一个“菜单式”入口，把常见 swap 运维动作（查看/扩容/降级/禁用）集中起来，避免误操作。

## Goals
1. `saltgoat swap status` 输出 swap 设备列表、使用率、`vm.swappiness`、`vm.vfs_cache_pressure`、si/so 指标、建议值。
2. `saltgoat swap ensure --min-size 8G [--max-size 16G]`：若 swap 总容量不足就自动创建/扩容 swapfile（支持自定义路径/优先级），并保证 `/etc/fstab` 与权限正确；可供自愈脚本调用。
3. `saltgoat swap create|resize|disable|purge`：显式管理 swapfile，支持 dry-run，提示用户确认。
4. `saltgoat swap tune --swappiness <n> [--vfs-cache-pressure <m>]`：写入 `/etc/sysctl.d/` 并立即生效。
5. `saltgoat swap menu`：交互式菜单列出常用操作（status/ensure/resize/tune/disable），主机上运行时给出上下文建议。
6. 为监控脚本提供自愈钩子：`resource_alert.py` 或其它任务可执行 `saltgoat swap ensure --min-size 8G --quiet`，在 swap 逼近阈值时尝试扩容并把结果写入 alerts.log。

## Non-Goals
- 不实现复杂的多分区布局（保留对现有 swap 分区的检测，但不负责分区 repartition）。
- 不涉及 zram/zswap 配置（后续可扩展）。
- 不自动修改现有 swap 分区大小（只针对 swapfile）。

## Impact
- 新增 CLI 模块（Bash 脚本 + helper）负责 swap 相关命令。
- 自愈脚本（`resource_alert.py`）需要可选地调用 `saltgoat swap ensure`，并在失败时记录日志。
- 文档：README + ops/monitoring 指南要更新，展示如何使用 swap CLI、推荐的最小值。
- 测试：增添单元测试覆盖 helper 逻辑（计算需扩容的大小、sysctl 写入等），以及 CLI 帮助输出。

## Risks & Mitigations
- 操作 swapfile 需要慎重，脚本必须确认路径权限、可用空间、以及 `swapoff` 影响；通过 dry-run + double confirmation + backup 当前 `/etc/fstab` 降低风险。
- 自动扩容若磁盘空间不足可能导致失败；需提前检查 `df` 并友好提示。
- 生产环境同时拥有 swap 分区和 swapfile，需正确处理优先级和多 swap 状态，保证 `ensure` 不会反复添加重复条目。

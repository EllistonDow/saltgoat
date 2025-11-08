# Magento 优化任务清单

## ✅ 已完成
- [x] 为 `sudo saltgoat optimize magento` 增加 profile/site/dry-run/report 支持，并将配置写入 `salt/pillar/magento-optimize.sls`。
- [x] 将内存档位映射与配置值提取到 `map.jinja`，根据 Pillar/Profile 生成调优参数。
- [x] 使用 Salt 原生 `file.*` / `ini.options_present` 重写 Nginx、PHP、MySQL、Valkey、OpenSearch、RabbitMQ 的优化逻辑，淘汰 `cmd.run + sed`。
- [x] 引入站点级配置检测（校验 `env.php` 与站点目录）。
- [x] 状态执行结束生成结构化报告（YAML/JSON）并支持 `--show-results`。
- [x] 安装流程提供 `--optimize-magento*` 选项，引导首轮安装后自动调优。
- [x] 增补自动化测试（`salt-call ... test=True`）并纳入 CI。

## ⏳ 待办 / Backlog
- [ ] 暂无新的优化需求；如需新增调优策略或平台支持，请在下一轮迭代补充到本清单。

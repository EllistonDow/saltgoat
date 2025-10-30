# Magento 优化任务清单

- [x] 为 `sudo saltgoat optimize magento` 增加参数支持（profile/site/dry-run/report），并将配置写入 `salt/pillar/magento-optimize.sls`
- [x] 将内存档位映射与配置值提取到 Jinja `map.jinja`，根据 pillar/profile 生成具体调优参数
- [x] 用 Salt 原生 `file.*` / `ini.options_present` 等模块重写 Nginx/PHP/MySQL/Valkey/OpenSearch/RabbitMQ 优化逻辑，消除 `cmd.run + sed`
- [x] 引入按站点粒度的 Magento 配置检测（校验 `env.php` / 站点目录存在）
- [x] 在状态执行结束生成结构化报告（YAML/JSON）并提供 `--show-results` 读取
- [x] 在安装流程中提供 `--optimize-magento` 选项或提示，引导安装后自动执行优化
- [x] 为优化流程补充自动化测试（`salt-call ... test=True`）并加入 CI

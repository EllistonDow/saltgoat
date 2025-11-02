# Magento 2 多站点自动化脚本预案

## 1. 背景与动机
- 当前 `magetools` 能覆盖权限、定时任务、Varnish 等运维操作，但缺少 “一键创建/回滚 Magento 多站点” 的统一脚本。
- 计划以现有 `bank` 站点为试点，新增域名 `duobank.magento.tattoogoat.com`，复用相同代码根目录并启用多商店模式。
- 引入多站点后，Nginx、Varnish、Salt Pillar 及 Magento 配置需要同步调整，回滚流程也要保证幂等与安全。

## 2. 目标与交付物
1. 设计 `saltgoat magetools multisite` 子命令，包含 `create`/`rollback`/`status`/`--dry-run` 功能。
2. 编写脚本，实现 Magento store 创建、Nginx/Varnish 配置更新、Pillar 变更与回滚。
3. 输出配套文档（流程说明、风险提示、验证步骤），并纳入仓库版本控制。

## 3. 前置条件
- 具备 `bank` 环境操作权限，可执行 `sudo saltgoat ...`、`salt-call state.apply`。
- 数据库/配置已备份或可随时做快照。
- 确认 `optional.varnish` Salt state 正常、`magetools varnish diagnose bank` 结果健康。
- Git 工作区可提交新增脚本与文档。

## 4. 现状评估摘要
- `modules/magetools/magetools.sh`：集中路由子命令，易于挂载新脚本。
- `modules/magetools/varnish.sh`：已能检测 store Base URL 并生成 backend 配置，但缺少状态判断与多站差异化处理。
- `modules/magetools/magento-schedule.py`：按站点目录管理 Schedule；共享代码根的多 store 不会新增任务，可保持不变。
- Salt Pillar (`salt/pillar/nginx.sls`, `magento-pwa.sls`, `magento-schedule.sls`, `monitoring.sls` 等) 使用单站点配置，需要扩展数据模型以支持额外域名。

## 5. 风险与缓解
| 风险 | 影响 | 缓解策略 |
| --- | --- | --- |
| Magento CLI 操作幂等性不足 | 重复执行可能创建重复网站/商店 | 先查询现有 store，存在则中止或走 idempotent 分支 |
| Nginx/Varnish 与 Pillar 不一致 | `state.apply` 覆盖手动改动，或流量异常 | 所有配置改动统一通过 Pillar + Salt；脚本仅生成/更新 Pillar 并触发 state |
| 回滚遗漏 | 残留 store/域名/证书，产生 404 或缓存污染 | 在创建前自动生成数据库/配置备份；回滚严格按逆序恢复 |
| Varnish 缓存错配 | 多域混淆导致内容串站 | 自动更新 snippet + backend server_name；回滚时调用 `diagnose` 验证 |
| 测试覆盖不足 | 生产切换风险高 | 先在 staging 演练，编写 `tests/` 下的验证脚本，记录验证命令 |

## 6. TODO 列表
- [ ] 需求细化：确认 `duobank` store 的根分类、语言、货币、主题设置。（已约定使用默认配置，可视为通过）
- [ ] Pillar 扩展方案：设计 `nginx.sites.duobank`、证书、监控/通知等字段。
- [ ] 脚本接口定义：`saltgoat magetools multisite` 参数、帮助、日志输出。
- [ ] 创建流程实现：
  - [ ] Magento CLI 操作封装（website/group/store 创建、base URL 配置、静态资源部署）。
  - [ ] 配置备份与 `app/etc/config.php` dump/restore。
  - [x] 通过 `saltgoat nginx create/add-ssl` 调用现有自动化（仍需后续验证 Varnish/监控）。
- [ ] 回滚流程实现：
  - [ ] Magento store 删除与配置清理。
  - [x] 使用 `saltgoat nginx delete` 清理由脚本生成的虚拟主机；证书/监控/通知仍需人工复核。
  - [ ] 触发 Varnish disable（或 update）。
- [ ] 自动诊断命令：`status` 输出 store 列表、Nginx server、Varnish snippet/back-end 状态。
- [ ] 测试与验证：编写 staging 演练步骤、回滚演练脚本。
- [ ] 文档补充：更新 README 或新增操作手册，写明限制与常见问题。

## 7. 脚本总体设计
### 7.1 CLI 入口
```
saltgoat magetools multisite <action> --site <root_site> --code <store_code> \
    --domain <fqdn> [--store-name <name>] [--lang en_US] [--currency USD] \
    [--dry-run] [--skip-varnish] [--skip-nginx] [--skip-ssl] [--ssl-email <mail>] [--nginx-site <name>]
```
- `create`：创建或更新多站点配置。
- `rollback`：删除 store 并恢复单站点状态。
- `status`：诊断当前站点是否存在指定 store/domain。
- `--dry-run`：输出将执行的步骤但不落地。

### 7.2 关键模块
- **检测逻辑**：调用 `bin/magento store:list` / `config:show`，读取 `app/etc/env.php` 判断 store 是否已存在。
- **备份逻辑**：执行 `mysqldump`（或调用已存在的备份脚本）、备份 `app/etc/env.php`、`config.php` 至 `/var/backups/saltgoat/<timestamp>/`.
- **Nginx/证书**：复用 `saltgoat nginx create` / `add-ssl` CLI，自动写入 Pillar 并申请证书，可通过 `--skip-nginx/--skip-ssl` 关闭。
- **Magento 实体创建**：优先使用 `bin/magento store:*:create`，若命令缺失（如 Magento 2.4.8）则通过 PHP API 创建/同步 Website、Store Group、Store 并设置默认值。
- **Varnish 集成**：根据新域名调用 `magetools varnish enable/diagnose` 或扩展 `varnish.sh` 以支持追加/移除单个域名。
- **日志与幂等**：每个阶段检查前置条件，如已存在则跳过并记录；失败时提供回滚建议。

## 8. 详细流程
### 8.1 创建流程（bank → duobank）
1. **预检**：确认 `/var/www/bank` 与 `bin/magento` 可用；`magento store:list` 不包含 `duobank`.
2. **备份**：触发数据库快照、拷贝 `app/etc/env.php` 与 `config.php`.
3. **Magento CLI**：创建 website/group/store，设置 base URL（http/https）、语言、货币、缓存设置，必要时部署静态资源。
4. **配置持久化**：执行 `bin/magento app:config:dump scopes themes`（按需），保证 `config.php` 更新。
5. **Nginx/证书**：执行 `saltgoat nginx create duobank "duobank.magento.tattoogoat.com" --root /var/www/bank/pub --magento`，随后 `saltgoat nginx add-ssl duobank duobank.magento.tattoogoat.com [email]`，确保虚拟主机与证书就绪。
6. **Varnish**：如 `diagnose` 显示已启用，重新执行 `varnish enable bank` 或提供只追加域名的流程。
7. **验证**：`curl -I https://duobank...`、`bin/magento config:show`、`magetools varnish diagnose bank`。

### 8.2 回滚流程
1. **确认目标**：检查 store 是否存在；提示回滚将删除相关数据。
2. **备份**：再做一次 DB/配置备份，以防回滚失败。
3. **Magento CLI**：删除 store/group/website，清理 `core_config_data`（或 `config:set ""`），刷新缓存。
4. **Nginx/证书恢复**：执行 `saltgoat nginx delete duobank`；若曾跳过自动化，则手动移除 Pillar/证书。
5. **Varnish**：执行 `magetools varnish disable bank` 或更新 snippet/back-end 排除域名。
6. **证书/监控清理**：撤销 `certbot` 条目、监控 URL、通知 topic。
7. **验证**：确认 `curl` 仅响应原域名、`store:list` 不含 `duobank`、`magetools varnish diagnose` 通过。

## 9. 测试与验证计划
- **Staging 演练**：在非生产环境完整执行 `create`→业务验证→`rollback`，记录命令与产出。
- **自动化测试**：编写 `tests/test_multisite_duobank.sh`（模拟 store 创建/删除的幂等）以及 Varnish snippet 单元测试。
- **监控检查**：确保 Prometheus/Grafana 针对新域名的监控项追加并生效。

## 10. 文档与运维交付
- 更新 `modules/magetools/README.md`，新增多站点章节。
- 在 `docs/` 下补充操作手册（部署、回滚、常见问题、故障排查）。
- 记录重试/回滚剧本与沟通流程（告警、变更窗口、执行者/审核者）。

## 11. 下一步行动
1. 与业务/前端确认 `duobank` 站点需求（主题、分类、语言）。
2. 准备 staging 环境与备份策略。
3. 根据本文档 TODO 列表逐项推进，完成后再更新进展并进入脚本开发阶段。

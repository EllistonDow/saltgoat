# PWA 推进路线图 / TODO 列表

## ✅ 已完成
- [x] **PWA Studio 分支固定**：脚本默认使用 `release/14.3.1`，与 Magento 2.4.8-p3 (MOS) 匹配，避免安装到不兼容的开发分支。
- [x] **高速权限修复**：`fast_fix_magento_permissions_local` 抽象后被 RabbitMQ、PWA 安装脚本共用，权限收敛耗时由分钟级降到秒级。
- [x] **GraphQL MOS 兼容补丁**：从构建流程中剔除 `is_confirmed`、`ProductAttributeMetadata`、`custom_attributes` 等 Commerce 专属字段，保持变体选择、迷你购物车正常工作。
- [x] **Checkout 支付 GraphQL 修正**：自动改写 `selected_payment_method`、`available_payment_methods` 片段，仅保留 MOS 可用字段，避免 “There was an error loading payments” 提示。
- [x] **PWA 环境默认值**：自动写入 `MAGENTO_BACKEND_EDITION=MOS`、`MAGENTO_EXPERIENCE_PLATFORM_ENABLED=false`、`MAGENTO_LIVE_SEARCH_ENABLED=false`，并同步 `.env` 至 `packages/venia-concept/.env`。
- [x] **系统服务自动化**：创建 `pwa-frontend-<site>.service` 并启停 `yarn buildpack serve`，集成到安装流程中。
- [x] **inotify 看门狗提升**：构建前自动将 `fs.inotify.max_user_watches` 提升至 524288，并写入 `/etc/sysctl.d/99-saltgoat-pwa.conf`，避免 Yarn watch 超出文件监控上限。
- [x] **覆盖脚本持久化**：`modules/pwa/overrides/` 中维护官方文件替换版，防止 `saltgoat pwa install` 还原 Commerce 逻辑。
- [x] **CLI 重构补强**：`saltgoat pwa status` 支持 `--json/--check/--no-graphql/--no-react`，`saltgoat pwa doctor` 输出 GraphQL/React/端口/日志报告，便于自动化与巡检。

## 🚧 进行中 / 待跟进
- [ ] **稳定性验证**：对不同 Magento 站点执行安装，观察脚本在多站点/多节点环境下的行为，补齐幂等性保护。
- [ ] **缓存刷新策略**：梳理 Nginx / Varnish / Service Worker 的缓存交互，形成可自动化的刷新脚本。
- [ ] **CI 保障**：补充最小化集成测试（容器内 `yarn build` + 变体 smoke test），防止升级破坏 MOS 兼容性。
- [ ] **UI 交付路线**：固化首页、分类、列表、详情页的设计稿与组件抽象，明确 Venia 模块的取舍。
- [ ] **Page Builder 使用文档**：输出 block 到前端的映射、缓存刷新与排错指南。
- [ ] **PWA 内容隔离深化**：`pwa_home` 自动创建已就绪，但模板内容、多 Store View 策略仍待完善。
- [ ] **PWA CLI 模块化**：继续增强 `remove/sync-content/status` 的日志、提示与兜底脚本。
- [ ] **模板资产沉淀**：将 Venia 覆盖与 Page Builder 模板整理到 `modules/pwa/templates/` 并做版本管理。
- [ ] **依赖治理**：统一在 `@saltgoat/venia-extension` workspace 维护依赖，持续检测 React 单版本与 `yarn list --pattern react` Guard。
- [ ] **React 单实例校验**：扩展 `window.__PWA_REACT_VERSION__` 自检并在 CLI 中提供指引，排查 Invalid hook call。
- [ ] **文档维护**：每次 PWA 变更后同步更新 [`docs/pwa-project-guide.md`](../docs/pwa-project-guide.md) 与本清单。

## 🔜 待实现 / Backlog
- [ ] **多版本适配**：按 Magento 补丁挑选 PWA Studio 版本，并允许 CLI/Pillar 自定义分支或标签。
- [ ] **错误收集与监控**：接入 Sentry/自建日志，收敛 `pwa-frontend-*.service` 状态，扩展 `saltgoat pwa status` 的 React/GraphQL 健康检查。
- [ ] **部署流程标准化**：沉淀 Dev→Test→Prod 推广 checklist，补充回滚/重建文档。
- [ ] **后台管理面板探索**：基于 Supabase / Salt API 打造运行状态看板与实时日志。
- [ ] **体验优化**：优化 Service Worker、图片/性能插件配置，降低首屏延时。
- [ ] **扩展功能**：评估 MOS 环境下的 Live Search/Experience Platform 替代方案，引入 Core Web Vitals/转化指标。
- [ ] **前端主题落地**：完成品牌化设计系统、组件库，并输出 Storybook。
- [ ] **内容团队指南**：形成 Page Builder 操作手册、图像规范、CDN/缓存 SOP。

> 注意事项：当前脚本密切依赖 SaltGoat 的 Pillar、Salt State 以及 `www-data` 用户。若要在外部纯净环境使用，需要先抽象出这些依赖点并提供可配置的参数。

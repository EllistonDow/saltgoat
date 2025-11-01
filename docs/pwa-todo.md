# PWA 推进路线图 / TODO 列表

## ✅ 已完成
- **PWA Studio 分支固定**：脚本默认使用 `release/14.3.1`，与 Magento 2.4.8-p3 (MOS) 匹配，避免安装到不兼容的开发分支。
- **高速权限修复**：`fast_fix_magento_permissions_local` 抽象后被 RabbitMQ、PWA 安装脚本共用，权限收敛耗时由分钟级降到秒级。
- **GraphQL MOS 兼容补丁**：从构建流程中剔除 `is_confirmed`、`ProductAttributeMetadata`、`custom_attributes` 等 Commerce 专属字段，保持变体选择、迷你购物车正常工作。
- **PWA 环境默认值**：自动写入 `MAGENTO_BACKEND_EDITION=MOS`、`MAGENTO_EXPERIENCE_PLATFORM_ENABLED=false`、`MAGENTO_LIVE_SEARCH_ENABLED=false`，并同步 `.env` 至 `packages/venia-concept/.env`。
- **系统服务自动化**：创建 `pwa-frontend-<site>.service` 并启停 `yarn buildpack serve`，集成到安装流程中。
- **覆盖脚本持久化**：`modules/pwa/overrides/` 中维护官方文件替换版，防止 `saltgoat pwa install` 还原 Commerce 逻辑。

## 🚧 进行中 / 待跟进
- **稳定性验证**：对不同 Magento 站点执行安装，观察安装脚本在多站点/多节点环境下的行为，补齐必要的幂等性保护。
- **缓存刷新策略**：梳理 Nginx / Varnish / Service Worker 的缓存交互，形成可操作的刷新脚本。
- **CI 保障**：补充最低限度的集成测试（例如在容器内跑 `yarn build` + 变体切换 smoke test），避免后续升级破坏 MOS 兼容性。
- **UI 交付路线**：确定首页、分类页、列表页、详情页的设计稿，梳理组件和主题定制范围，明确 Venia 主题里哪些模块需要取舍/重写。
- **Page Builder 使用文档**：整理后台搭建内容的最佳实践，记录 block/section 到 PWA 前端的映射、缓存刷新、常见故障排查。
- **CLI 重构**：完善 `saltgoat pwa` 命名空间，拆分 install/status/sync/remove，自动同步自定义 workspace（进行中：健康检查/依赖检测待补齐）。
- **PWA 内容隔离**：在 Magento 内建立专用 Page Builder 页面（如 `pwa_home`、`pwa_category` 等），安装脚本需自动生成/同步并在 PWA 前端默认引用，避免与传统 Luma 前端互相覆盖。（已完成：缺页时自动 `cms:page:create` 创建 `pwa_home` 占位，待完成：模板内容与多 Store View 策略）
- **PWA CLI 模块化**：为 `saltgoat pwa` 增加 `remove`、`sync-content`、`status` 等子命令，支持独立安装/卸载/重同步覆盖文件，并输出运营提示。
- **模板资产沉淀**：把自研的 Venia 覆盖、首页/分类 Page Builder 模板整理到 `modules/pwa/templates/`，安装流程按站点选择推送，形成可复用的“样板库”。
- **依赖治理**：统一使用 Yarn workspace（`@saltgoat/venia-extension`），清除 `package-lock.json` / sample 扩展，加入 React 单版本检查（`yarn list --pattern react`）和构建 guard（进行中）。
- **文档维护**：每次调整 PWA 脚本或模板时，更新 [`docs/PWA_PROJECT_GUIDE.md`](PWA_PROJECT_GUIDE.md)，保持方案与实现同步。

## 🔜 待实现 / Backlog
1. **多版本适配**
   - 根据不同 Magento 补丁级别挑选兼容的 PWA Studio 版本。
   - 增加 CLI 参数或 Pillar 配置允许自定义分支/标签。
2. **错误收集与监控**
   - 引入 Sentry 或自建日志聚合，捕获前端错误（包含 GraphQL 细节）。
   - 系统化记录 `pwa-frontend-*.service` 状态，提供重启/回滚工具。
   - 将 React/GraphQL 健康检查集成到 `saltgoat pwa status`（校验单实例 React、GraphQL ping）。
3. **部署流程标准化**
   - 输出“开发—测试—生产”推广步骤与 checklist。
   - 补充回滚/重建说明文档。
4. **后台管理面板探索**
   - 结合 Supabase / Salt API 设计运行状态看板。
   - 提供任务列表、执行记录、实时日志等可视化。
5. **体验优化**
   - 调整 Service Worker 策略，减少首次加载等待并确保热更新。
   - 评估是否开启 PWA Studio 的性能插件、图片优化等功能。
6. **扩展功能**
   - 研究 Live Search / Experience Platform 在 MOS 环境的替代方案或可选插件。
   - 集成线上指标（Core Web Vitals、转化漏斗）监控。
7. **前端主题落地**
   - 量身定制 Venia 主题：设计系统、色板、字体、图标、组件库与我们品牌一致。
   - 构建首页/分类/搜索/购物车等核心页面，沉淀 Storybook 或组件文档。
   - 对接营销内容（Banner、推荐位、SEO 元标签等）。
8. **内容团队指南**
    - 编写 Page Builder 详细操作手册（模块选型、布局模板、发布流程、环境差异）。
    - 约定图像规范、CDN 策略、缓存刷新 SOP。

> 注意事项：当前脚本密切依赖 SaltGoat 的 Pillar、Salt State 以及 `www-data` 用户。若要在外部纯净环境使用，需要先抽象出这些依赖点并提供可配置的参数。

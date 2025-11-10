# SaltGoat PWA 项目手册

> 本文档是 PWA 项目的权威手册；每当新增或调整 `modules/pwa/` 相关功能时，务必同步更新此文档，保持与代码行为一致。

## 1. 项目目标与范围
- 为 Magento 2 (MOS) 提供官方 PWA Studio（Venia）的一键部署、覆盖补丁与运维脚本。
- 让 PWA 前端与传统 Luma 前端共享后台设施但保持内容隔离，可独立安装、同步、卸载。
- 沉淀我们自研的 Page Builder 模板、GraphQL 补丁、服务脚本，使多站点复用变得简单且可靠。

## 2. 仓库结构速览
- `modules/pwa/install.sh`：核心安装/同步/卸载逻辑。
- `modules/pwa/pwa.sh`：`saltgoat pwa` 子命令入口。
- `modules/pwa/overrides/`：对 PWA Studio 官方文件的长期覆盖。
- `modules/pwa/templates/cms/`：CMS 页面模板（如 `pwa_home.html`），用于自动创建/更新 Page Builder 基础内容。
- `modules/pwa/workspaces/`：自定义 Yarn workspace 模板，安装时同步至 PWA Studio（如 `saltgoat-venia-extension`）。
- `todo/pwa.md`：路线图与未完成事项。
- `salt/pillar/magento-pwa.sls`：站点参数（根路径、数据库、PWA Studio 配置等）。

> 计划新增的 Page Builder 模板库将放在 `modules/pwa/templates/`，上线时请更新本节。

## 3. CLI 使用说明
所有命令需在仓库根目录或已安装 `saltgoat` 的环境下运行，建议加 `sudo`。

### 3.1 `saltgoat pwa install <site> [--with-pwa|--no-pwa]`
- 读取 `salt/pillar/magento-pwa.sls` 中的 `<site>` 配置，安装 Magento 基础、初始化数据库与管理员账号。
- 依据 Pillar 或 `--with-pwa` 开关决定是否部署 PWA Studio。
- 自动套用 overrides、生成 `.env`、构建前端并创建 `pwa-frontend-<site>.service`。

### 3.2 `saltgoat pwa status <site>`
- 汇总站点目录、PWA Studio 目录/环境文件是否存在。
- 检查 systemd 服务是否存在、是否启用、当前运行状态。
- 给出下一步建议（如缺少仓库可执行 `sync-content --pull`）。

### 3.3 `saltgoat pwa sync-content <site> [--pull] [--rebuild]`
- 默认重新应用 overrides、刷新 `.env`、确保 systemd 服务配置。
- `--pull`：强制拉取/克隆 PWA Studio 仓库。
- `--rebuild`：在环境变量齐全时执行 `yarn install` + `yarn build`。
- 后续接入 Page Builder 模板同步逻辑时，也会在此命令中处理。

### 3.4 `saltgoat pwa remove <site> [--purge]`
- 停止并禁用 `pwa-frontend-<site>.service`，删除 systemd 单元文件。
- `--purge`：额外删除 PWA Studio 目录；不带该参数则保留源码供调试。

> CLI 新增参数或交互流程时，请在每个子命令的说明后补充示例和注意事项。

### 3.5 自定义 Workspace (`@saltgoat/venia-extension`)
- `modules/pwa/workspaces/saltgoat-venia-extension/` 保存了所有自研 React 组件（例如新的 `HomeContent`、自定义 talon 等）。
- `sync-content` 会自动将该目录同步到 PWA Studio 的 `packages/saltgoat-venia-extension/` 并写入 `package.json` 的 `workspaces` 与 `dependencies`。
- 同步脚本同时会在 `packages/venia-ui/package.json` 与 `packages/venia-concept/package.json` 中写入 `@saltgoat/venia-extension` 依赖（以 `link:../saltgoat-venia-extension` 形式），确保 intercept 注入的 `import` 可被 Yarn 解析。
- 新增组件流程：
  1. 在 workspace 下的 `src` 中编写组件并从 `src/index.js` 导出；
  2. 在 intercept 中引用（示例：`modules/pwa/overrides/.../local-intercept.js` wrap 到 `@saltgoat/venia-extension/src/...`）；
  3. 如需额外依赖，通过该 workspace 的 `peerDependencies` 声明，确保与 Venia React 版本兼容；
  4. 运行 `sudo saltgoat pwa sync-content <site> --rebuild`，查看是否编译通过。
- **禁止** 直接修改 PWA Studio 仓库原始文件（例如 `packages/venia-ui`），所有自定义都应集中在此 workspace，便于升级和回滚。

### 3.6 健康检查与常规自查
- `saltgoat pwa status` 会输出当前 CMS Identifier、模板路径、PWA service 状态，并在后续版本加入 React 版本/GraphQL ping 结果提醒。
- 推荐每次同步后手动验证：
  - `curl https://<domain>/graphql` 查询 `storeConfig`；
  - `curl https://<domain>/client.*.js` 检查返回的 bundle 名称是否最新；
- 浏览器控制台执行 `window.__PWA_REACT_VERSION__`（由 `HomeContent` workspace 注入）确认只有一份 React，若需进一步排查可查看 `window.__PWA_REACT_DEBUG__`（包含版本号、与 `window.React` 的一致性以及时间戳）。

## 4. 内容隔离与 Page Builder 策略

### 4.1 核心思路
- 目标：PWA 使用独立的 CMS/Page Builder 页面，不再与传统前端共享 `home`、`category` 等标识。
- 推荐命名：`pwa_home`、`pwa_category_<id>`、`pwa_footer` 等，方便脚本和运营团队识别。
- `MAGENTO_PWA_HOME_IDENTIFIER` 环境变量用于告诉前端读取哪个 CMS Page，默认值为 `home`，可在 Pillar 的 `env_overrides` 中改为 `pwa_home`。
- Pillar 支持通过 `cms.home` 段落自定义标题、Store View、模板：
  ```yaml
  cms:
    home:
      identifier: pwa_home
      title: "PWA Home"
      store_ids: [0]
      template: modules/pwa/templates/cms/pwa_home.html
  ```
  > `template` 支持相对仓库根目录或绝对路径；`store_ids` 可传数组或单个值，默认包含 `0`（All Store Views）。

### 4.2 后台操作步骤
1. 登录 Magento Admin → `Content > Pages`，点击 “Add New Page”。
2. 设置 Page Title（例如 “PWA Home”）、URL Key（如 `pwa-home`），并在 “Page Builder” 中搭建首页内容。
3. 在 “Search Engine Optimization” 中，将 “URL Key” 与页面目的保持一致，便于后续追踪。
4. 在 “Page in Websites” 选择需要的 Store View。
5. 在 “Design” → “Layout Update XML” 中如需自定义布局，可直接保存 PWA 专用片段。
6. 将 “Identifier” 设置为 `pwa_home`，保存并发布。

### 4.3 与 CLI 的协作
- `saltgoat pwa install/sync-content` 会保证 `.env` 内含 `MAGENTO_PWA_HOME_IDENTIFIER`，默认写入 `home`。若 Pillar `cms.home.identifier` 提供值（如 `pwa_home`），脚本会自动写入该标识；如需覆盖，也可在 `env_overrides` 中显式设置。
- 自定义组件统一放在 `@saltgoat/venia-extension` Workspace（模板位于 `modules/pwa/workspaces/saltgoat-venia-extension`），同步时会自动写入 `packages/saltgoat-venia-extension` 并在 intercept 中引用，避免直接改动官方源码。
- 当 `MAGENTO_PWA_HOME_IDENTIFIER` ≠ `home` 且数据库中不存在对应 CMS 页面时，脚本会自动通过 `bin/magento cms:page:create` 创建一个启用状态的占位页面（Store ID=0，布局 `1column`），并提醒运营在 Page Builder 中编辑内容。
- 若 `modules/pwa/templates/cms/<identifier>.html` 存在（例如默认提供的 `pwa_home.html`），安装或同步时会自动将其内容下发到页面；也可在 Pillar `cms.home.template` 指向自定义 HTML。
- 后续计划：
  - 追加 `modules/pwa/templates/` 中的 Page Builder JSON 作为示例，必要时自动覆盖默认内容。

### 4.4 Showcase 兜底配置
- 当 `MAGENTO_PWA_HOME_IDENTIFIER` 指向的 CMS 页面缺失或内容为空时，前端会回退到 `Showcase` 组件（位于 `modules/pwa/workspaces/saltgoat-venia-extension/src/components/HomeContent/Showcase.js`）。
- 兜底数据可通过两种方式覆盖：
  1. **构建期**：在 `pwa_studio.env_overrides` 写入 `SALTGOAT_PWA_SHOWCASE='{"hero":{"title":"..."}}'`（JSON 字符串），脚本会注入到 PWA `.env`；
  2. **运行期**：在 `app/design` 或额外脚本中设置 `window.__SALTGOAT_PWA_SHOWCASE__ = { ... }`，支持 A/B 测试或按 Store View 注入。
- 支持的字段：
  ```json
  {
    "hero": {
      "badge": "Venia Hyper Surface",
      "title": "立体化 PWA 首屏，\\n让用户一眼爱上",
      "description": "段落说明",
      "ctas": [
        {"label": "立即选购", "href": "/collections/new", "variant": "primary"},
        {"label": "布局指南", "href": "/page-builder", "variant": "secondary"}
      ],
      "trendTags": ["渐变玻璃拟物", "Live Commerce"],
      "stats": [{"label": "实时响应", "value": "180ms", "detail": "GraphQL Cache"}],
      "floatingMetric": {"label": "GraphQL Edge", "value": "180 ms"}
    },
    "heroScene": {
      "label": "Live Dashboard",
      "title": "Saltgoat Pulse",
      "metrics": [{"label": "转化率", "value": "+38%"}]
    },
    "spotlightCollections": [{"title": "立体新品矩阵", "subtitle": "Holographic", "href": "/collections/holo", "image": "https://..."}],
    "serviceHighlights": [{"title": "Page Builder 即时同步", "description": "内容团队发布后 60 秒内同步", "accent": "内容"}],
    "realtimeSignals": [{"type": "订单", "message": "#1045 付款完成", "time": "2 分钟前", "delta": "+¥1,280"}],
    "timeline": {"label": "实时脉搏", "title": "订单、库存、运维事件统一面板", "cta": {"label": "查看监控", "href": "/monitor/live"}}
  }
  ```
- 未提供的字段会退回默认值；数组为空时对应模块会自动隐藏，避免渲染占位文本。
- `MAGENTO_PWA_SHOWCASE_CATEGORY_IDS`（逗号分隔）用于指定要从 GraphQL 拉取的“沉浸式系列”分类 ID，默认 `3,4,5`；查询结果会自动填充卡片标题/链接/图片。
- 默认值与自定义 JSON 中的字符串支持 `{{store_name}}` 占位符，前端会在拿到 `storeConfig` 后自动替换为真实门店名称。

### 4.5 常见问题
- **新页面未生效**：确认 `MAGENTO_PWA_HOME_IDENTIFIER` 是否与 CMS 页面 Identifier 完全一致，以及 `sync-content` 是否已经运行。
- **仍显示 Luma 首页**：清理 Service Worker 缓存（浏览器应用程序 → Service Worker）并重启 `pwa-frontend-<site>` 服务。
- **运营误删 PWA 页面**：可以在 Magento Admin 中重新创建同名页面，或从计划中的模板库恢复；同步完成后重跑 `saltgoat pwa sync-content <site> --rebuild`。

## 5. 覆盖与模板管理
- 对官方源码的替换仅保留必要的 intercept、GraphQL 片段（位于 `modules/pwa/overrides/`）。组件级别的扩展统一放在 `@saltgoat/venia-extension` workspace。
- 安装流程会自动裁剪 checkout `selected_payment_method` / `available_payment_methods` GraphQL 片段，只保留 MOS 可用字段，防止支付方式接口报错。
- 新增覆盖时：
  1. 优先考虑在 workspace 内编写组件/Hook，通过 intercept 注入；
  2. 若必须直接 patch 官方源码，放在 `modules/pwa/overrides`，并在 `apply_mos_graphql_fixes` 中写明操作逻辑；
  3. 在本文档记录覆盖动机和目标版本，方便后续升级核对。
- Page Builder 模板保持在 `modules/pwa/templates/`，同步逻辑由 CLI 负责。带版本的模板需注明适用的 Magento/PWA Studio 版本。

## 6. 运维与日常流程
1. **首装**：`sudo saltgoat pwa install <site> --with-pwa`
   - 完成后执行 `saltgoat pwa status` 验证服务，按需在 Magento 后台发布 PWA 专属页面。
2. **日常同步**：内容或覆盖有更新时运行 `saltgoat pwa sync-content <site> --pull --rebuild`。
   - 同步脚本会在构建前自动提升 `fs.inotify.max_user_watches` 至 524288，并在 `/etc/sysctl.d/99-saltgoat-pwa.conf` 记录，防止 Yarn watch 触发 “Too many open files”。
3. **升级验收**：每次升级 PWA Studio 版本或脚本逻辑，需在预生产环境完整跑一遍安装 → 同步 → 构建流程，并记录在发布说明中。
4. **回滚/卸载**：使用 `saltgoat pwa remove <site> --purge` 清理前端，必要时根据备份恢复 Page Builder 内容。
5. **React/依赖检查**：每次 `sync-content --rebuild` 后，可执行 `yarn list --pattern react` 与浏览器 `window.__PWA_REACT_VERSION__`，确认没有多余的 React 副本。
6. **监控挂钩**：`resource_alert.py` 会对 `pwa-frontend-<site>.service` 的自愈状态进行告警（后续版本会增加 GraphQL/PWA 健康检查入口）。

## 7. 更新准则
- **功能新增**：描述新增功能的使用场景、参数、与现有流程的关系。
- **行为调整**：说明兼容性影响、是否需要额外的 Pillar 或配置迁移。
- **文件结构变化**：更新仓库结构列表，告知模板/覆盖的存放位置。
- **待办同步**：若 Roadmap 有进展或新增任务，记得同步到 `todo/pwa.md` 并在本文相关章节注明状态。

保持本文档与实现同步，有助于 PWA 模块的可维护性与复用性。

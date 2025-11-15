# PWA Home Template Sync Fix

## 背景
`saltgoat pwa sync-content --home-id pwa_home_no_pb`（或 `pwa_home`）会把模板写入 `cms_page.content` 并刷新缓存。但 PWA 前端渲染 CMS 内容时会调用 `@magento/peregrine/lib/util/htmlStringImgUrlConverter`，内部使用 DOMPurify 严格白名单。默认情况下 `<style>` 会被剥离，所以每次同步后首页的样式都会消失，必须到 Magento 后台打开页面、随便修改再保存，TinyMCE 会把内容转成 Page Builder 标准结构（几乎无需 `<style>`），才能暂时恢复。无论是 `pwa_home_no_pb` 还是带 Page Builder 元素的 `pwa_home`，都会遇到同样的问题。

## 方案
1. **保留原始模板**：`modules/pwa/lib/cms_apply_page.php` 在 `page->save()` 之后，通过 `ResourceConnection` 直接把模板原样写回 `cms_page.content`（带 `<!-- sg-sync:xxxxx -->` 签名），再执行 `cache:clean block_html full_page graphql_query_resolver_result`。GraphQL 端可以拿到未经转义的纯 HTML（同时适用于 `pwa_home_no_pb` 和 `pwa_home`）。
2. **Peregrine 识别并跳过 DOMPurify**：新增 `modules/pwa/overrides/packages/peregrine/lib/util/htmlStringImgUrlConverter.js`。只要检测到模板含有 `<!-- sg-sync: -->` 签名，就绕过 DOMPurify，将 `<style>`/`<section>` 原样传给 `RichContent`。正常的后台编辑内容仍按官方流程 sanitize。
3. **HomeContent Hook（可选）**：`modules/pwa/workspaces/saltgoat-venia-extension/src/hooks/useRichContentHtml.js` 预留自定义入口，Home 页面可进一步控制是否跳过或后处理。

## 验证步骤
```bash
sudo saltgoat pwa sync-content pwas --home-id pwa_home_no_pb --pull --rebuild
sudo systemctl restart pwa-frontend-pwas.service
sudo systemctl status pwa-frontend-pwas.service --no-pager
```

- `curl https://pwas.magento.tattoogoat.com/graphql -d '{"query":"{ cmsPage(identifier:\"pwa_home_no_pb\") { content } }"}'` 必须返回 `<style>` 开头的 HTML。
- 浏览器强制刷新后即可看到 Nebula 样式，无需再手动“后台保存”。

## 注意事项
- DOMPurify 只对包含 `<!-- sg-sync:` 的模板放行，避免影响运营后台创建的其他页面。
- 切换到 Page Builder 模板时仍建议执行 `sync-content --home-id ...`，以确保缓存、GraphQL 和 systemd 服务同时收敛。

# Magento PWA 后端一键部署指南

SaltGoat 在 `v1.2.x` 起新增 `saltgoat magetools pwa install`，用于在全新目录中快速部署 Magento 2（作为 PWA 后端）并串联 Valkey / RabbitMQ / Cron 等现有自动化组件，可选同时拉取 Magento PWA Studio 并执行 Yarn 构建。

> ⚠️ 粗体步骤中涉及的密码、密钥请务必放在未纳入版本控制的 Pillar 文件中（如 `salt/pillar/magento-pwa.sls`）。示例 `.sample` 仅为说明用途，千万不要提交真实帐号。

## 1. 准备 Pillar

1. 复制样板：
   ```bash
   cp salt/pillar/magento-pwa.sls.sample salt/pillar/magento-pwa.sls
   ```
2. 根据实际情况修改 `pwa`（或自定义站点名）条目：
   - `root`：站点代码目录，例如 `/var/www/pwa`
   - `base_url` / `base_url_secure`：HTTP/HTTPS 域名
   - `admin.*`：后台管理员账号信息
   - `db.*`：数据库名称、用户与密码
   - `composer.repo_*`：Magento Marketplace 公钥/私钥
   - `opensearch.*`：OpenSearch 连接信息（可关闭 `enable_auth`）
   - `options`：是否在安装时启用 HTTPS/Rewrite/cleanup-database
   - `node`：是否自动安装/升级 Node、Yarn 及目标版本
   - `services`：是否自动安装 Cron、执行 `valkey-setup`、`rabbitmq-salt`
   - `pwa_studio`：如需同时检出并构建 PWA Studio，可设 `enable: true`
     - `serve_port`：本地 UPWARD 服务监听端口（默认 8082），Nginx 会通过反向代理暴露该端口
     - `env_overrides` 至少需提供 `MAGENTO_BACKEND_URL`（指向 Magento 后端）与 `CHECKOUT_BRAINTREE_TOKEN`（Braintree Tokenization Key，可填 sandbox key 测试）

> `salt/pillar/magento-pwa.sls` 默认为空，请确保该文件未被加入版本控制（例如在 `.gitignore` 中添加 `salt/pillar/magento-pwa.sls`），实际部署时从 `.sample` 拷贝并填写真实凭据。

## 2. 执行一键安装

```bash
sudo saltgoat magetools pwa install pwa --with-pwa
```

脚本将依次执行：

1. **检查/安装 Node.js & Yarn**（默认目标版本 18.x，可在配置中修改或关闭）
2. **创建站点目录**（`root`），并为 `www-data` 授权
3. 若目录为空，自动执行 `composer create-project` 下载 Magento 核心
4. **创建 MySQL 数据库与用户**（依赖 `salt/pillar/saltgoat.sls` 的 `mysql_password`）
5. 自动生成 crypt key（如未提供），调用 `bin/magento setup:install`
6. 写入 `setup:config:set --http-cache-hosts=127.0.0.1:6081`，重置权限
7. 根据配置调用：
   - `saltgoat magetools magento-cron.sh <site> install`
   - `saltgoat magetools valkey-setup <site> --no-reuse`
   - `saltgoat magetools rabbitmq-salt smart <site>`
8. 当 `pwa_studio.enable: true` 或 CLI 指定 `--with-pwa` 时，克隆 PWA Studio 仓库并依次执行 `PWA_STUDIO_INSTALL_COMMAND`（默认 `yarn install`）与 `PWA_STUDIO_BUILD_COMMAND`（默认 `yarn build`）；脚本会使用 `env_template` 生成 `<target_dir>/.env`，自动写入 `env_overrides`、补全 `MAGENTO_BACKEND_EDITION=MOS`、`MAGENTO_EXPERIENCE_PLATFORM_ENABLED=false` 与 `MAGENTO_LIVE_SEARCH_ENABLED=false`，同时同步到 `packages/venia-concept/.env`；并会提前移除 Commerce 专属 GraphQL 字段（例如 `is_confirmed`、`ProductAttributeMetadata`、`custom_attributes`），避免 MOS 环境出现对应的 GraphQL 报错。若缺少必填环境变量（如 `MAGENTO_BACKEND_URL`、`CHECKOUT_BRAINTREE_TOKEN`），脚本会提示缺失项并跳过构建，可在 Pillar 补齐后重新运行
9. 自动生成 systemd 单元 `pwa-frontend-<site>.service`（运行 `yarn buildpack serve .` 监听 `serve_port`，默认 8082），并将 Nginx 站点反向代理到该端口，最终暴露 `https://<pwa 域名>/`
10. 输出安装摘要（后台地址、数据库信息、后续建议等）

如需仅安装 Magento 后端，可省略 `--with-pwa`，或显式加入 `--no-pwa` 覆盖 Pillar 中的 `enable: true`。

## 3. 后续操作建议

- **申请 SSL** 并启用 Varnish：
  ```bash
  sudo saltgoat ssl issue pwa.magento.tattoogoat.com   # 如尚未申请证书
  sudo saltgoat magetools varnish enable pwa
  sudo saltgoat magetools varnish diagnose pwa        # 校验 X-Magento-Vary/ESI 配置
  ```
- **验证缓存与队列**：
  ```bash
  sudo saltgoat magetools valkey-check pwa
  sudo saltgoat magetools rabbitmq-salt check pwa
  ```
- **检查 cron / schedule**：
  ```bash
  sudo saltgoat magetools cron pwa status
  sudo saltgoat magetools salt-schedule pwa status
  ```
- **PWA Studio 前端**：根据 `docs/` 官方指引配置 `<target_dir>/.env` 与 GraphQL endpoint，然后在 `target_dir` 内运行 `yarn watch` 或 `yarn build`。
  - 安装脚本会使用 `pwa_studio.env_template`（默认 `packages/venia-concept/.env.dist`）生成 `<target_dir>/.env`，并按 `env_overrides` 写入额外键值且默认附加 `MAGENTO_BACKEND_EDITION=MOS`，随后同步至 `packages/venia-concept/.env` 以兼容旧脚本。
- **演示数据**：当前推荐沿用 Magento 官方的传统 sample data 流程，例如在站点根目录执行 `php bin/magento sampledata:deploy && php bin/magento setup:upgrade`，无需额外的 PWA 专用数据包。

## 4. 常见问题

- **目录非空**：若 `root` 下已有文件且没有 `composer.json`，脚本会中止以防覆盖。请先清空或自行处理代码。
- **Repo 凭据缺失**：`composer.repo_user/repo_pass` 未配置时无法执行 `create-project`。如不需要下载核心，可保留空目录并手动上传代码（脚本会在检测到 `composer.json` 后跳过）。
- **OpenSearch 认证**：若关闭 `enable_auth` 或未设置用户名/密码，脚本会自动传入 `--opensearch-enable-auth=0`。
- **PWA Studio 构建耗时**：首次执行 `yarn install` 会较慢，可提前在目标目录预热依赖或在 `.npmrc` 中设置国内源。
- **Valkey/RabbitMQ 脚本失败**：脚本内已记录警告，不会中断安装。可根据输出提示单独执行 `saltgoat magetools valkey-setup` / `rabbitmq-salt` 修复。

## 5. 清理/重新部署

若需重装，可删除下列资源后再次运行安装脚本：

1. 站点目录 (`rm -rf /var/www/pwa`)
2. 数据库与用户 (`DROP DATABASE pwamage; DROP USER 'pwa'@'localhost';`)
3. Cron/Salt Schedule（`saltgoat magetools cron pwa uninstall`）
4. Valkey / RabbitMQ 配置（`valkey-setup ... --no-reuse`、`rabbitmq-salt remove pwa`）

完成清理后重新执行 `sudo saltgoat magetools pwa install pwa` 即可。

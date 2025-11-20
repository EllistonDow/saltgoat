# Magento PWA 后端一键部署指南

SaltGoat 在 `v1.2.x` 起新增 `saltgoat magetools pwa install`，用于在全新目录中快速部署 Magento 2（作为 PWA 后端）并串联 Valkey / RabbitMQ / Cron 等现有自动化组件。

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
  - `options.http_cache_hosts`：HTTP Cache/Varnish 地址，安装时会自动执行 `bin/magento --no-interaction setup:config:set --http-cache-hosts=<值>`，默认 `127.0.0.1:6081`
  - `node`：是否自动安装/升级 Node、Yarn 及目标版本
   - `services`：是否自动安装 Cron、执行 `valkey-setup`、`rabbitmq-salt`
   - `pwa_studio`：如需同时检出 PWA Studio 可设 `enable: true`

> `salt/pillar/magento-pwa.sls` 默认为空，可将其加入 `.gitignore`，实际部署时从 `.sample` 拷贝。

## 2. 执行一键安装

```bash
sudo saltgoat magetools pwa install pwas
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
8. 可选地克隆 PWA Studio 仓库并执行指定的 Yarn 命令
9. 输出安装摘要（后台地址、数据库信息、后续建议等）

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
- **检查 Salt Schedule**：
  ```bash
  sudo saltgoat magetools cron pwa status
  sudo saltgoat magetools salt-schedule pwa status
  ```
- **PWA Studio 前端**：根据 `docs/` 官方指引配置 `.env` 与 GraphQL endpoint，然后在 `target_dir` 内运行 `yarn watch` 或 `yarn build`。

## 4. 常见问题

- **目录非空**：若 `root` 下已有文件且没有 `composer.json`，脚本会中止以防覆盖。请先清空或自行处理代码。
- **Repo 凭据缺失**：`composer.repo_user/repo_pass` 未配置时无法执行 `create-project`。如不需要下载核心，可保留空目录并手动上传代码。
- **OpenSearch 认证**：若关闭 `enable_auth` 或未设置用户名/密码，脚本会自动传入 `--opensearch-enable-auth=0`。
- **Valkey/RabbitMQ 脚本失败**：脚本内已记录警告，不会中断安装。可根据输出提示单独执行 `saltgoat magetools valkey-setup` / `rabbitmq-salt` 修复。

## 5. 清理/重新部署

若需重装，可删除下列资源后再次运行安装脚本：

1. 站点目录 (`rm -rf /var/www/pwa`)
2. 数据库与用户 (`DROP DATABASE pwamage; DROP USER 'pwa'@'localhost';`)
3. Salt Schedule（`saltgoat magetools cron pwa uninstall`）
4. Valkey / RabbitMQ 配置（`valkey-setup ... --no-reuse`、`rabbitmq-salt remove pwa`）

完成清理后重新执行 `sudo saltgoat magetools pwa install pwa` 即可。

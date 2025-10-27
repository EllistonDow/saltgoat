# Magento 2 权限管理指南

## 核心原则

- 所有站点文件归属应统一到 `www-data:www-data`（或站点专用用户）。
- Web 端与 CLI 操作文档统一使用 `sudo -u www-data`。
- 保持目录/文件权限最小化：
  - `755`: `app`, `bin`, `dev`, `lib`, `phpserver`, `pub`, `setup`, `vendor`
  - `775`: `var`, `generated`, `pub/media`, `pub/static`, `app/etc`
  - `660`: `app/etc/env.php`

## SaltGoat 权限命令

```bash
# 修复（实际执行 state）
sudo saltgoat magetools permissions fix /var/www/site

# 仅检查（test=True 模式）
sudo saltgoat magetools permissions check /var/www/site

# 重新应用通用 state（会提示确认）
sudo saltgoat magetools permissions reset /var/www/site
```

- `fix` / `reset` 会调用 `optional.magento-permissions-smart`（或 `generic`）state，确保站点根目录、核心目录、可写目录及 `env.php` 权限符合基线。
- `check` 以 `test=True` 模式运行同一 state，仅列出将要执行的操作，不会更改任何文件。
- 命令会自动验证目录中存在 `bin/magento`，并通过 `pillar={'site_path': <path>}` 将路径传递给 Salt。

若在使用 `check` 时看到 `would have been executed`，说明实际执行 `fix` 会落地这些改动。执行完成后可再次运行 `check` 验证输出为空。

## 常见故障与解决

| 现象 | 可能原因 | 建议操作 |
|------|----------|----------|
| CLI 命令报权限拒绝 | 目录/文件属主为 root | `sudo saltgoat magetools permissions fix /var/www/site` |
| 前台/后台 500 错误，var/cache 无法写入 | `var/` 或 `generated/` 属主/权限不正确 | 同上 |
| 需要人工验证 | 想预览权限变更 | `sudo saltgoat magetools permissions check /var/www/site` |

## 手动操作（仅在无法使用 Salt 时）

```bash
sudo chown -R www-data:www-data /var/www/site
sudo find /var/www/site -type d -exec chmod 755 {} \;
sudo find /var/www/site -type f -exec chmod 644 {} \;
sudo chmod 775 /var/www/site/{var,generated,pub/media,pub/static,app/etc}
sudo chmod 660 /var/www/site/app/etc/env.php
```

## 最佳实践

1. 固定使用 `www-data` 运行 `bin/magento` 与 `n98-magerun2`：
   ```bash
   sudo -u www-data php bin/magento cache:flush
   sudo -u www-data n98-magerun2 sys:info
   ```
2. 避免直接 `sudo php bin/magento ...`，以免生成 root 文件。
3. 在部署/迁移后立即运行 `permissions fix`，确保权限基线一致。
4. 定期使用 `permissions check` 或 `salt-call --local state.apply optional.magento-permissions-smart test=True pillar="{'site_path': ...}"` 检查偏差。

文档涵盖的命令与状态位于：
- CLI：`modules/magetools/permissions.sh`
- Salt state：`salt/states/optional/magento-permissions-*.sls`

如需扩展（例如站点自定义用户或多站点场景），可以在 Pillar 中自定义 `site_path`，并扩展对应 state 模块。

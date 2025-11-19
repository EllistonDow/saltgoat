# 凭据与 Secret 管理指南

SaltGoat 默认把真实密码与访问令牌存放在 `salt/pillar/secret/` 目录，以避免在 Git 仓库中出现明文。本文介绍如何初始化密钥模板、更新现有密码以及让系统读取最新配置。

---

## 1. Secret 目录结构

```
salt/pillar/secret/
├── README.md           # 本目录说明
├── .gitkeep            # 保持目录存在
├── auth.sls.example    # 数据库/服务密码示例
├── magento_api.sls.example  # Magento API Token / OAuth1 示例
├── restic.sls.example  # Restic 仓库信息示例
└── smtp.sls.example    # SMTP/Postfix 凭据示例

2025-10：新增 `telegram.sls.example`，用于记录 Telegram Bot Token、群组 chat_id 及话题 `message_thread_id` 映射。
```

`.gitignore` 会忽略 `salt/pillar/secret/*.sls`，因此模板以 `.example` 结尾，只作为参考；真实环境需要复制后去掉 `.example` 后缀并填入实际密码。

---

## 2. 全新环境初始化

1. **复制模板并填写密码**

   ```bash
   cp salt/pillar/secret/auth.sls.example  salt/pillar/secret/auth.sls
   cp salt/pillar/secret/magento_api.sls.example salt/pillar/secret/magento_api.sls
   cp salt/pillar/secret/restic.sls.example salt/pillar/secret/restic.sls
   cp salt/pillar/secret/smtp.sls.example   salt/pillar/secret/smtp.sls
   cp salt/pillar/secret/telegram.sls.example salt/pillar/secret/telegram.sls
   ```
   > 自 1.8.3 起，`sudo saltgoat install all` 会在检测到缺失时自动生成 `salt/pillar/secret/saltgoat.sls` 等核心文件并写入随机密码；如需集中式或多环境管理，仍可按上述方式复制 `.example` 模板。

   然后编辑 `.sls` 文件，将占位值（`ChangeMe*`）替换为真实密码。示例：

   ```yaml
   # salt/pillar/secret/auth.sls
   secrets:
     mysql_password: 'SuperRoot123!'
     mysql_backup_password: 'BackupOnly123!'
     valkey_password: 'RedisStrong!'
     rabbitmq_password: 'Queue123!'
     webmin_password: 'WebminStrong!'
     phpmyadmin_password: 'PhpMyAdmin123!'

   # salt/pillar/secret/magento_api.sls
   secrets:
     magento_api:
       bank:
         base_url: "https://bank.example.com"
         token: "<integration_token>"          # 默认 Bearer
       tank:
         base_url: "https://tank.example.com"
         auth_mode: oauth1
         consumer_key: "<oauth_consumer_key>"
         consumer_secret: "<oauth_consumer_secret>"
         access_token: "<oauth_access_token>"
         access_token_secret: "<oauth_access_token_secret>"
   ```

2. **刷新 Pillar**

   ```bash
   sudo saltgoat pillar refresh
   ```

   此步骤仅让 Salt 拿到新配置，不会立刻修改系统中的服务密码。

3. **执行安装或密码同步脚本**

   - 全新安装：`sudo saltgoat install all`
   - 需要预先写入服务密码：`bash scripts/sync-passwords.sh`

   完成后可用 `sudo saltgoat passwords --show`（需确认后输出）检查当前值。

---

## 3. 更新现有密码的流程

在已经运行的环境中更换密码，请遵循以下顺序：

1. **编辑 Secret Pillar**

   - `salt/pillar/secret/auth.sls`：MySQL/Valkey/RabbitMQ/Webmin/phpMyAdmin。
   - `salt/pillar/secret/restic.sls`：Restic 仓库路径、密码、授权用户。
   - `salt/pillar/secret/smtp.sls`：SMTP 账号、Postfix profile、告警邮箱。
   - 如需 Telegram Token，可在 `salt/pillar/secret/auto.sls` 或自建文件中加入：
     ```yaml
   secrets:
     telegram:
        primary:
          token: 'BOT_TOKEN'
          chat_id: -1003210805906
          topics:
            saltgoat/business/order: 2
            saltgoat/business/customer: 3
            saltgoat/backup/xtrabackup: 4
            saltgoat/backup/restic: 5
     ```

2. **刷新 Pillar**

   ```bash
   sudo saltgoat pillar refresh
   ```

3. **根据服务类型执行对应脚本/状态**

   | 服务 / 组件                       | 同步命令                                                                                  |
   |-----------------------------------|-------------------------------------------------------------------------------------------|
   | MySQL / Valkey / RabbitMQ / Webmin | `bash scripts/sync-passwords.sh` （或针对单项使用 `sudo salt-call --local state.apply …`） |
   | SMTP / Postfix                    | `sudo saltgoat postfix --smtp <profile> [--enable|--disable]`                            |
   | Restic 备份                       | `sudo saltgoat magetools backup restic install`                                           |
   | Percona XtraBackup                | `sudo saltgoat magetools xtrabackup mysql install`                                        |
   | Magento 维护任务（需新密码）        | `sudo saltgoat magetools maintenance <site> …`（大多会自动读取新的 Pillar）               |
   | 其它 Salt 状态                    | `sudo salt-call --local state.apply <state.name>`                                         |

4. **验证**

   - `sudo saltgoat passwords --show`（需确认后输出）确认凭据已被 CLI 读取。
   - `sudo saltgoat magetools backup/restic/xtrabackup …` 或服务自测命令检查是否成功。
   - 如使用 Postfix，建议运行 `sudo saltgoat postfix --smtp <profile>` 后测试告警或 `sudo saltgoat monitor enable-beacons` 的 Telegram 推送。

---

## 4. 常见问题

### `sudo saltgoat pillar refresh` 不会直接改密码吗？

不会。该命令只刷新 Salt 的配置缓存。若要真正修改服务密码，必须在刷新 Pillar 后执行上表所列的状态/脚本，让服务读取新值并完成修改。

### Secret 文件应该提交到仓库吗？

不要。真实凭据应只保存在部署主机或安全的密钥管理系统中。`.gitignore` 已忽略 `salt/pillar/secret/*.sls`，并提供 `.example` 模板帮助你快速创建私有文件。

### 可以使用 Vault、Credstash 等 ext_pillar 吗？

可以。只要最终能在 `pillar['secrets']` 中拿到对应键值（如 `secrets.mysql_password`），SaltGoat 就能与外部密钥服务协同工作。示例模板仍然适用，可作为参考。

---

## 5. 关联文档

- [`docs/postfix-smtp.md`](docs/postfix-smtp.md)：SMTP/ Postfix 配置与切换。
- [`docs/mysql-backup.md`](docs/mysql-backup.md)：Percona XtraBackup 及 mysqldump。
- [`docs/backup-restic.md`](docs/backup-restic.md)：Restic 仓库备份与恢复。

如需更多帮助，可运行 `saltgoat help` 或查看各模块文档。确保在修改密码后及时同步服务并验证，以避免凭据不一致造成的故障。***

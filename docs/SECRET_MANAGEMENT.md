# 凭据与 Secret 管理指南

SaltGoat 默认把真实密码与访问令牌存放在 `salt/pillar/secret/` 目录，以避免在 Git 仓库中出现明文。本文介绍如何初始化密钥模板、更新现有密码以及让系统读取最新配置。

---

## 1. Secret 目录结构

```
salt/pillar/secret/
├── README.md           # 本目录说明
├── .gitkeep            # 保持目录存在
├── auth.sls.example    # 数据库/服务密码示例
├── restic.sls.example  # Restic 仓库信息示例
└── smtp.sls.example    # SMTP/Postfix 凭据示例
```

`.gitignore` 会忽略 `salt/pillar/secret/*.sls`，因此模板以 `.example` 结尾，只作为参考；真实环境需要复制后去掉 `.example` 后缀并填入实际密码。

---

## 2. 全新环境初始化

1. **复制模板并填写密码**

   ```bash
   cp salt/pillar/secret/auth.sls.example  salt/pillar/secret/auth.sls
   cp salt/pillar/secret/restic.sls.example salt/pillar/secret/restic.sls
   cp salt/pillar/secret/smtp.sls.example   salt/pillar/secret/smtp.sls
   ```

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
   ```

2. **刷新 Pillar**

   ```bash
   saltgoat pillar refresh
   ```

   此步骤仅让 Salt 拿到新配置，不会立刻修改系统中的服务密码。

3. **执行安装或密码同步脚本**

   - 全新安装：`sudo saltgoat install all`
   - 需要预先写入服务密码：`bash scripts/sync-passwords.sh`

   完成后可用 `saltgoat passwords --show`（需确认后输出）检查当前值。

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
           accept_from:
             - CHAT_ID
           chat_id: CHAT_ID
     ```

2. **刷新 Pillar**

   ```bash
   saltgoat pillar refresh
   ```

3. **根据服务类型执行对应脚本/状态**

   | 服务 / 组件                       | 同步命令                                                                                  |
   |-----------------------------------|-------------------------------------------------------------------------------------------|
   | MySQL / Valkey / RabbitMQ / Webmin | `bash scripts/sync-passwords.sh` （或针对单项使用 `sudo salt-call --local state.apply …`） |
   | SMTP / Postfix                    | `saltgoat postfix --smtp <profile> [--enable|--disable]`                                  |
   | Restic 备份                       | `sudo saltgoat magetools backup restic install`                                           |
   | Percona XtraBackup                | `sudo saltgoat magetools xtrabackup mysql install`                                        |
   | Magento 维护任务（需新密码）        | `saltgoat magetools maintenance <site> …`（大多会自动读取新的 Pillar）                     |
   | 其它 Salt 状态                    | `sudo salt-call --local state.apply <state.name>`                                         |

4. **验证**

   - `saltgoat passwords --show`（需确认后输出）确认凭据已被 CLI 读取。
   - `saltgoat magetools backup/restic/xtrabackup …` 或服务自测命令检查是否成功。
   - 如使用 Postfix，建议运行 `saltgoat postfix --smtp <profile>` 后测试告警或 `saltgoat monitor enable-beacons` 的 Telegram 推送。

---

## 4. 常见问题

### `saltgoat pillar refresh` 不会直接改密码吗？

不会。该命令只刷新 Salt 的配置缓存。若要真正修改服务密码，必须在刷新 Pillar 后执行上表所列的状态/脚本，让服务读取新值并完成修改。

### Secret 文件应该提交到仓库吗？

不要。真实凭据应只保存在部署主机或安全的密钥管理系统中。`.gitignore` 已忽略 `salt/pillar/secret/*.sls`，并提供 `.example` 模板帮助你快速创建私有文件。

### 可以使用 Vault、Credstash 等 ext_pillar 吗？

可以。只要最终能在 `pillar['secrets']` 中拿到对应键值（如 `secrets.mysql_password`），SaltGoat 就能与外部密钥服务协同工作。示例模板仍然适用，可作为参考。

---

## 5. 关联文档

- [`docs/POSTFIX_SMTP.md`](docs/POSTFIX_SMTP.md)：SMTP/ Postfix 配置与切换。
- [`docs/MYSQL_BACKUP.md`](docs/MYSQL_BACKUP.md)：Percona XtraBackup 及 mysqldump。
- [`docs/BACKUP_RESTIC.md`](docs/BACKUP_RESTIC.md)：Restic 仓库备份与恢复。

如需更多帮助，可运行 `saltgoat help` 或查看各模块文档。确保在修改密码后及时同步服务并验证，以避免凭据不一致造成的故障。***

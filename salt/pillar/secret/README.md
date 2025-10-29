# SaltGoat Secrets Pillar

将真实密码、API Token 等敏感配置放在此目录的 `.sls` 文件中，并确保这些文件 **不纳入版本控制**。仓库已在 `.gitignore` 中忽略 `salt/pillar/secret/*.sls`，你可以根据需要创建多个文件，例如：

- `salt/pillar/secret/auth.sls`
- `salt/pillar/secret/restic.sls`
- `salt/pillar/secret/smtp.sls`

在 `salt/pillar/top.sls` 中按主机或环境 include 对应的 secret Pillar，例如：

```yaml
base:
  '*':
    - saltgoat
    - nginx
    - secret.auth        # 新增：自定义的私有 Pillar（未托管）
```

推荐的密钥写法：

```yaml
secrets:
  mysql_password: 'ActualRootPassword'
  mysql_backup_password: 'BackupUserPassword'
  restic:
    password: 'ResticRepoPassword'
    repo: 's3:https://minio.example.com/backups/prod'
    service_user: 'backup'
    repo_owner: 'backup'
  email_accounts:
    primary:
      host: 'smtp.gmail.com'
      port: 587
      user: 'alerts@example.com'
      password: 'AppPassword'
      from_email: 'alerts@example.com'
      from_name: 'SaltGoat Alerts'
  telegram:
    primary:
      token: '123456:ABCDEF'
      accept_from:
        - 123456789
      chat_id: 123456789
```

> 提示：如果使用 ext_pillar（如 Vault、Credstash），只需确保最终能在 Pillar 中拿到 `secrets.*` 对应的键值，即可与仓库中的模板文件配合使用。

# Postfix / SMTP 集成指南

SaltGoat 允许在同一套 Pillar 中维护多组外发 SMTP 凭据，并可通过一键命令在不同账号间切换。本指南说明如何配置、切换与验证 Gmail、Microsoft 365 等常见服务。

## 1. 准备工作

1. **生成或更新 Pillar**  
   运行 `saltgoat pillar init` 会写出一个支持多账号的基本结构；已有环境可直接编辑 `salt/pillar/saltgoat.sls`（或你的私有 Pillar）。
   > 提示：`salt/pillar/lemp.sls` 仍然是示例模板，真实环境下请把敏感凭据写入 `salt/pillar/saltgoat.sls` 或你的外部机密仓库。
2. **账号凭据**  
   - 每个账号需要 `host`、`port`、`user`、`password`、`from_email`、`from_name` 字段。  
   - Gmail 需启用应用专用密码；Microsoft 365 默认只允许发件人 = 登录用户，使用别名需在 Exchange 管理中心授予 “Send As” 权限。
3. **Postfix 安装（可选）**  
   `mail.postfix.enabled` 默认为 `false`。若希望本机直接通过 Postfix relaying，先执行 `sudo apt-get install postfix` 或 `salt-call --local state.apply optional.postfix` 并将 `enabled` 设为 `true`。

## 2. Pillar 结构示例

```yaml
email:
  default: gmail          # 当前激活的账号
  retention_days: 30
  accounts:
    gmail:
      host: smtp.gmail.com
      port: 587
      user: abbsay@gmail.com
      password: lqeobfnszpmwjudg
      from_email: abbsay@gmail.com
      from_name: SaltGoat Alerts
    m365:
      host: smtp.office365.com
      port: 587
      user: hello@tschenfeng.com
      password: Linksys.2010     # 请替换为真实凭据
      from_email: hello@tschenfeng.com
      from_name: SaltGoat Alerts

mail:
  postfix:
    enabled: false         # 仅写入凭据，不 reload Postfix
    profile: gmail         # 与 email.default 保持一致
    inet_interfaces:
      - loopback-only
    mynetworks:
      - 127.0.0.0/8
    relay:
      tls_security_level: encrypt
    tls:
      smtp_security_level: may
      smtpd_security_level: may
      cert_file: /etc/ssl/certs/ssl-cert-snakeoil.pem
      key_file: /etc/ssl/private/ssl-cert-snakeoil.key
```

- `email.accounts` 可按需扩展更多配置段（如 `ses`, `mailgun` 等）。
- 将敏感凭据存入未托管的私有 Pillar，更安全。

## 3. 切换 SMTP 账号

使用内置命令即可切换：

```bash
# 切换到 Gmail（保持当前 Postfix 启用状态）
sudo ./saltgoat postfix --smtp gmail

# 切换到 Microsoft 365 并同时启用 Postfix
sudo ./saltgoat postfix --smtp m365 --enable

# 切换回 Gmail 同时关闭 Postfix
sudo ./saltgoat postfix --smtp gmail --disable
```

命令会执行以下步骤：

1. 更新 Pillar 中的 `email.default` 与 `mail.postfix.profile`。
2. 若附加 `--enable` / `--disable`，同步把 `mail.postfix.enabled` 置为 `true/false`。
3. 刷新 Pillar 缓存：`saltutil.refresh_pillar`。
4. 应用 `optional.postfix`，生成新的 `/etc/postfix/main.cf` / SASL 文件（只有在 Postfix 已安装并启用时才会重载服务，未安装时可忽略 `postconf` / `postmap` 的警告）。
5. 调用 `reload_environment`，写入 `/etc/postfix/sasl_passwd` 等凭据文件。

## 4. 验证方式

1. **快速脚本**（仅测试 SMTP 登录与发信）：  
   ```bash
   python3 - <<'PY'
   import smtplib, yaml
   from email.message import EmailMessage
   acct = yaml.safe_load(open('salt/pillar/saltgoat.sls'))['email']['accounts']['m365']
   with smtplib.SMTP(acct['host'], int(acct.get('port', 587)), timeout=30) as smtp:
       smtp.ehlo(); smtp.starttls(); smtp.ehlo()
       smtp.login(acct['user'], acct['password'])
       msg = EmailMessage()
       msg['Subject'] = 'SaltGoat SMTP 测试'
       msg['From'] = f"SaltGoat Alerts <{acct['from_email']}>"
       msg['To'] = acct['from_email']
       msg.set_content('这是一封 SaltGoat SMTP 测试邮件。')
       smtp.send_message(msg)
   print('邮件已发送')
   PY
   ```
   若返回 `SendAsDenied`，说明当前登录账户没有“代表地址发信”的权限。

2. **查看 Postfix 状态**（启用时）  
   ```bash
   sudo postconf relayhost myorigin
   sudo tail -f /var/log/mail.log
   ```

## 5. 常见问题

| 问题 | 可能原因 / 解决方案 |
| ---- | ------------------- |
| `SendAsDenied`（M365） | 登录账号与 `from_email` 不一致且未授予 Send As 权限；请在 Exchange 管理中心配置或保持二者一致。 |
| `postconf: command not found` | 本机未安装 Postfix；若仅使用脚本直连外部 SMTP 可忽略此警告。 |
| 切换命令成功但邮件仍走旧账号 | 确认 `salt/pillar/saltgoat.sls` 已更新，并重新运行 `saltgoat postfix --smtp <account>` + `python3` 测试脚本。 |

## 6. 清理与安全建议

- 将真实密码保存在私有 Pillar 或外部机密仓库，Git 版本库中仅留占位符。
- 切换至 CI/CD 环境时，配合 `pillar_roots` 或 Vault 方案存储凭据。
- 如不再使用 Postfix，可将 `mail.postfix.enabled` 设为 `false` 并运行：  
  `sudo salt-call --local state.apply optional.postfix`，公式会移除配置与服务。

---

完成以上配置后，使用 `saltgoat postfix --smtp <account>` 即可在多套 SMTP 凭据之间自由切换，方便在 Gmail 与 Microsoft 365 等服务之间测试或运维切换。祝使用愉快！
> 提示：若系统尚未安装 Postfix，即使使用 `--enable` 也只会生成凭据文件；待安装 Postfix 后再次执行 `saltgoat postfix --smtp <profile> --enable` 即可完成重载。

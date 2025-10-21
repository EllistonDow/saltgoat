# Postfix SMTP 服务器安装和配置
# salt/states/optional/postfix.sls

# 安装Postfix
install_postfix:
  pkg.installed:
    - name: postfix
    - require:
      - pkg: install_system_deps

# 安装邮件工具
install_mail_utils:
  pkg.installed:
    - name: mailutils
    - require:
      - pkg: install_postfix

# 配置Postfix
configure_postfix:
  file.managed:
    - name: /etc/postfix/main.cf
    - contents: |
        # Postfix main configuration
        myhostname = {{ grains['fqdn'] }}
        mydomain = {{ grains['domain'] }}
        myorigin = $mydomain
        inet_interfaces = loopback-only
        mydestination = $myhostname, localhost.$mydomain, localhost
        relayhost = {{ pillar.get('email', {}).get('smtp_host', '') }}
        mynetworks = 127.0.0.0/8
        mailbox_size_limit = 0
        recipient_delimiter = +
        inet_protocols = ipv4
        
        # SMTP settings
        smtpd_banner = $myhostname ESMTP $mail_name
        disable_vrfy_command = yes
        
        # Security settings
        smtpd_helo_required = yes
        smtpd_helo_restrictions = permit_mynetworks,reject_invalid_helo_hostname,permit
        smtpd_recipient_restrictions = permit_mynetworks,reject_unauth_destination,permit
        
        # TLS settings
        smtp_tls_security_level = may
        smtpd_tls_security_level = may
        smtpd_tls_cert_file = /etc/ssl/certs/ssl-cert-snakeoil.pem
        smtpd_tls_key_file = /etc/ssl/private/ssl-cert-snakeoil.key
        smtpd_tls_session_cache_database = btree:${data_directory}/smtpd_scache
        smtp_tls_session_cache_database = btree:${data_directory}/smtp_scache
        
        # SASL authentication (if SMTP credentials provided)
        {% if pillar.get('email', {}).get('smtp_user') %}
        smtp_sasl_auth_enable = yes
        smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
        smtp_sasl_security_options = noanonymous
        {% endif %}
    - require:
      - pkg: install_postfix

# 配置SASL密码文件 (if SMTP credentials provided)
configure_sasl_passwd:
  file.managed:
    - name: /etc/postfix/sasl_passwd
    - contents: |
        [{{ pillar.get('email', {}).get('smtp_host', '').split(':')[0] }}]:{{ pillar.get('email', {}).get('smtp_host', '').split(':')[1] or '587' }} {{ pillar.get('email', {}).get('smtp_user', '') }}:{{ pillar.get('email', {}).get('smtp_password', '') }}
    - mode: 600
    - require:
      - file: configure_postfix
    - onlyif: pillar.get('email', {}).get('smtp_user')

# 生成SASL密码数据库
generate_sasl_passwd_db:
  cmd.run:
    - name: postmap /etc/postfix/sasl_passwd
    - require:
      - file: configure_sasl_passwd
    - onlyif: pillar.get('email', {}).get('smtp_user')

# 启动Postfix服务
start_postfix:
  service.running:
    - name: postfix
    - enable: true
    - require:
      - file: configure_postfix

# 测试邮件发送
test_mail_sending:
  cmd.run:
    - name: echo "SaltGoat SMTP test" | mail -s "Test Email" root
    - require:
      - service: start_postfix
    - unless: test -f /tmp/postfix_test_sent

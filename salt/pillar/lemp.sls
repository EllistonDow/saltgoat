# SaltGoat Pillar Configuration
# 使用 Salt 原生功能进行配置管理

{% set secrets = pillar.get('secrets', {}) %}
{% set mysql_password = pillar.get('mysql_password', secrets.get('mysql_password', 'ChangeMeRoot!')) %}
{% set valkey_secret = pillar.get('valkey_password', secrets.get('valkey_password', 'ChangeMeValkey!')) %}
{% set rabbitmq_secret = pillar.get('rabbitmq_password', secrets.get('rabbitmq_password', 'ChangeMeRabbit!')) %}
{% set webmin_secret = pillar.get('webmin_password', secrets.get('webmin_password', 'ChangeMeWebmin!')) %}
{% set phpmyadmin_secret = pillar.get('phpmyadmin_password', secrets.get('phpmyadmin_password', 'ChangeMePhpMyAdmin!')) %}
{% set ssl_email = pillar.get('ssl_email', secrets.get('ssl_email', 'ssl@example.com')) %}
{% set email_accounts = secrets.get('email_accounts', {}) %}
{% set primary_email = email_accounts.get('primary', {}) %}
{% set secondary_email = email_accounts.get('secondary', {}) %}
{% set default_nginx_version = pillar.get('nginx_version', '1.29.3-1~noble') %}
{% set default_modsec_level = pillar.get('nginx_modsecurity_level', 5) %}
{% set default_modsec_enabled = pillar.get('nginx_modsecurity_enabled', True) %}
{% set default_csp_level = pillar.get('nginx_csp_level', 3) %}
{% set csp_policy_map = {
  1: "default-src 'self' http: https: data: blob: 'unsafe-inline' 'unsafe-eval'",
  2: "default-src 'self' http: https: data: blob: 'unsafe-inline' 'unsafe-eval'; script-src 'self' 'unsafe-inline' 'unsafe-eval'",
  3: "default-src 'self' http: https: data: blob: 'unsafe-inline'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'",
  4: "default-src 'self' http: https: data: blob:; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' http: https: data:; font-src 'self' http: https: data:",
  5: "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' http: https: data:; font-src 'self' http: https: data:; connect-src 'self' http: https:; frame-src 'self'"
} %}
{% set default_csp_policy = pillar.get('nginx_csp_policy', csp_policy_map.get(default_csp_level, csp_policy_map[3])) %}

# 系统配置
system:
  timezone: {{ grains.get('timezone', 'America/Los_Angeles') }}
  language: {{ grains.get('locale_info', {}).get('defaultlanguage', 'en_US.UTF-8') }}
  ssh_port: {{ grains.get('ssh_port', '22') }}

# 数据库配置
mysql:
  root_password: {{ mysql_password }}
  version: '8.4'

# Valkey 配置
valkey:
  password: {{ valkey_secret }}
  version: '8'

# RabbitMQ 配置
rabbitmq:
  admin_password: {{ rabbitmq_secret }}
  version: '4.1'

# Webmin 配置
webmin:
  password: {{ webmin_secret }}

# phpMyAdmin 配置
phpmyadmin:
  password: {{ phpmyadmin_secret }}

# SSL 配置
ssl:
  email: {{ ssl_email }}

# PHP 配置
php:
  version: '8.3'
  memory_limit: {{ pillar.get('php_memory_limit', '512M') }}
  max_execution_time: {{ pillar.get('php_max_execution_time', '300') }}
  extensions:
    - bcmath
    - ctype
    - curl
    - dom
    - fileinfo
    - filter
    - ftp
    - gd
    - hash
    - iconv
    - intl
    - json
    - libxml
    - mbstring
    - openssl
    - pcre
    - pdo_mysql
    - simplexml
    - soap
    - sockets
    - sodium
    - tokenizer
    - xmlwriter
    - xsl
    - zip
    - zlib

# Nginx 配置（使用 apt 安装官方包）
nginx:
  version: {{ default_nginx_version|yaml_dquote }}
  worker_processes: {{ pillar.get('nginx_worker_processes', 'auto') }}
  modsecurity:
    enabled: {{ default_modsec_enabled }}
    level: {{ default_modsec_level }}
    admin_path: {{ pillar.get('nginx_modsecurity_admin_path', '/admin') }}
  csp:
    enabled: {{ pillar.get('nginx_csp_enabled', True) }}
    level: {{ default_csp_level }}
    policy: {{ default_csp_policy|yaml_dquote }}

# Composer 配置
composer:
  version: '2.8'

# OpenSearch 配置
opensearch:
  version: '2.19'

# Varnish 配置
varnish:
  version: '7.6'

# 防火墙配置
firewall:
  allowed_ports: {{ pillar.get('firewall_allowed_ports', '22,80,443,3306,6379,5672,15672,10000').split(',') }}

# 邮件通知配置（支持多账号切换）
email:
  default: {{ pillar.get('email_default', secrets.get('email_default', 'primary')) }}
  retention_days: {{ pillar.get('log_retention_days', '30') }}
  accounts:
    primary:
      host: "{{ primary_email.get('host', 'smtp.example.com') }}"
      port: {{ primary_email.get('port', 587) }}
      user: "{{ primary_email.get('user', 'alerts@example.com') }}"
      password: "{{ primary_email.get('password', 'ChangeMeEmail!') }}"
      from_email: "{{ primary_email.get('from_email', 'alerts@example.com') }}"
      from_name: "{{ primary_email.get('from_name', 'SaltGoat Alerts') }}"
    secondary:
      host: "{{ secondary_email.get('host', 'smtp-backup.example.com') }}"
      port: {{ secondary_email.get('port', 587) }}
      user: "{{ secondary_email.get('user', 'alerts-backup@example.com') }}"
      password: "{{ secondary_email.get('password', 'ChangeMeEmailBackup!') }}"
      from_email: "{{ secondary_email.get('from_email', 'alerts-backup@example.com') }}"
      from_name: "{{ secondary_email.get('from_name', 'SaltGoat Alerts Backup') }}"

# 邮件服务配置（Postfix 采用配置文件驱动，可与 email 账号联动）
mail:
  postfix:
    enabled: False
    profile: {{ pillar.get('postfix_profile', secrets.get('postfix_profile', 'primary')) }}  # 默认联动 email.accounts 中的 primary
    hostname: {{ grains.get('fqdn') }}
    domain: {{ grains.get('domain') or grains.get('fqdn') }}
    origin: '$mydomain'
    inet_interfaces:
      - 'loopback-only'
    mynetworks:
      - '127.0.0.0/8'
    relay:
      tls_security_level: 'encrypt'
    tls:
      smtp_security_level: 'may'
      smtpd_security_level: 'may'
      cert_file: '/etc/ssl/certs/ssl-cert-snakeoil.pem'
      key_file: '/etc/ssl/private/ssl-cert-snakeoil.key'
    auth:
      mechanism: 'login'
    aliases: []

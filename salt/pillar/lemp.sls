# SaltGoat Pillar Configuration
# 使用 Salt 原生功能进行配置管理

# 系统配置
system:
  timezone: {{ grains.get('timezone', 'America/Los_Angeles') }}
  language: {{ grains.get('locale_info', {}).get('defaultlanguage', 'en_US.UTF-8') }}
  ssh_port: {{ grains.get('ssh_port', '22') }}

# 数据库配置
mysql:
  root_password: {{ grains.get('pillar_mysql_root_password', 'SaltGoat2024!') }}
  version: '8.4'

# Valkey 配置
valkey:
  password: {{ grains.get('pillar_valkey_password', 'Valkey2024!') }}
  version: '8'

# RabbitMQ 配置
rabbitmq:
  admin_password: {{ grains.get('pillar_rabbitmq_admin_password', 'RabbitMQ2024!') }}
  version: '4.1'

# Webmin 配置
webmin:
  password: {{ grains.get('pillar_webmin_password', 'Webmin2024!') }}

# phpMyAdmin 配置
phpmyadmin:
  password: {{ grains.get('pillar_phpmyadmin_password', 'phpMyAdmin2024!') }}

# SSL 配置
ssl:
  email: {{ grains.get('pillar_ssl_email', 'admin@example.com') }}

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
  version: '1.28.0-1~noble'
  worker_processes: {{ pillar.get('nginx_worker_processes', 'auto') }}
  modsecurity:
    enabled: {{ pillar.get('nginx_modsecurity_enabled', False) }}
    level: {{ pillar.get('nginx_modsecurity_level', 0) }}
    admin_path: {{ pillar.get('nginx_modsecurity_admin_path', '/admin') }}
  csp:
    enabled: {{ pillar.get('nginx_csp_enabled', False) }}
    level: {{ pillar.get('nginx_csp_level', 0) }}
    policy: {{ pillar.get('nginx_csp_policy', "default-src 'self' http: https: data: blob: 'unsafe-inline' 'unsafe-eval'") }}

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
  default: gmail
  retention_days: {{ pillar.get('log_retention_days', '30') }}
  accounts:
    gmail:
      host: 'smtp.gmail.com'
      port: 587
      user: 'abbsay@gmail.com'
      password: 'lqeobfnszpmwjudg'
      from_email: 'abbsay@gmail.com'
      from_name: 'SaltGoat Alerts'
    m365:
      host: 'smtp.office365.com'
      port: 587
      user: 'hello@tschenfeng.com'
      password: 'Linksys.2010'
      from_email: 'notice@tschenfeng.com'
      from_name: 'SaltGoat Alerts'

# 邮件服务配置（Postfix 采用配置文件驱动，可与 email 账号联动）
mail:
  postfix:
    enabled: False
    profile: gmail             # 默认联动 email.accounts 中的 gmail，可改为 m365
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

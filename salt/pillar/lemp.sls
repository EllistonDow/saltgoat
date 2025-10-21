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

# Nginx 配置
nginx:
  version: '1.29.1'
  modsecurity: true
  worker_processes: {{ pillar.get('nginx_worker_processes', 'auto') }}

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

# 邮件通知配置
email:
  smtp_host: {{ grains.get('pillar_smtp_host', 'smtp.gmail.com:587') }}
  smtp_user: {{ grains.get('pillar_smtp_user', 'your-email@gmail.com') }}
  smtp_password: {{ grains.get('pillar_smtp_password', 'your-app-password') }}
  from_email: {{ grains.get('pillar_smtp_from_email', 'your-email@gmail.com') }}
  from_name: {{ grains.get('pillar_smtp_from_name', 'SaltGoat Alerts') }}
  retention_days: {{ pillar.get('log_retention_days', '30') }}
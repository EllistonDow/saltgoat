# SaltGoat Top Configuration
# 定义 Salt 状态文件的执行顺序和目标

base:
  '*':
    - common.system
    - common.packages
    - common.security
    - core.sysctl
    - core.nginx
    - core.php
    - core.mysql
    - core.composer
    - optional.valkey
    - optional.opensearch
    - optional.rabbitmq
    - optional.varnish
    - optional.fail2ban
    - optional.fail2ban-watch
    - optional.webmin
    - optional.phpmyadmin
    - optional.certbot
    - schedules.saltgoat

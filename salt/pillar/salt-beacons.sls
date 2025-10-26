saltgoat:
  beacons:
    service:
      services:
        nginx:
          interval: 30
        mysql:
          interval: 30
        php8.3-fpm:
          interval: 30
        valkey:
          interval: 30
        rabbitmq:
          interval: 45
        opensearch:
          interval: 45
      disable_during_state_run: True
    load:
      averages:
        1:
          interval: 60
          max: 6
        5:
          interval: 60
          max: 4
        15:
          interval: 60
          max: 3
    mem:
      percent:
        max: 85
      interval: 60
    diskusage:
      interval: 120
      percent:
        /: 90
    inotify:
      /etc/nginx:
        mask:
          - modify
          - close_write
        recurse: False
        interval: 60
        files:
          - /etc/nginx/nginx.conf
      /etc/mysql/mysql.conf.d:
        mask:
          - modify
          - close_write
        recurse: False
      /var/www:
        mask:
          - close_write
          - attrib
        recurse: True
        if_missing: warn
        auto_add: True
        sls_whitelist:
          - optional.magento-permissions
    pkg:
      interval: 3600
  reactor:
    autorestart_services:
      services:
        - nginx
        - mysql
        - php8.3-fpm
        - valkey
        - rabbitmq
        - opensearch
    resource_alerts:
      log_path: /var/log/saltgoat/alerts.log
    config_watch:
      auto_permissions: true
      monitored_paths:
        - /etc/nginx/nginx.conf
        - /etc/mysql/mysql.conf.d/mysqld.cnf
        - /var/www
      site_path: /var/www/tank
    pkg_updates:
      log_path: /var/log/saltgoat/alerts.log
      auto_refresh: true

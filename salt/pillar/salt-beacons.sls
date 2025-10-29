{% set cpu_count = grains.get('num_cpus', 1) or 1 %}
{% set load_max_1m = (cpu_count * 1.5) %}
{% set load_max_5m = (cpu_count * 1.25) %}
{% set load_max_15m = (cpu_count * 1.1) %}
{% set mem_warn_percent = 78 %}
{% set disk_root_percent = 88 %}
{% set secrets = pillar.get('secrets', {}) %}
{% set telegram_cfg = secrets.get('telegram', {}).get('primary', {}) %}
{% set accept_from = telegram_cfg.get('accept_from', []) %}
{% if not accept_from %}
{% set accept_from = [123456789] %}
{% endif %}
{% set default_chat_id = telegram_cfg.get('chat_id', accept_from[0]) %}

saltgoat:
  beacons:
    service:
      - services:
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
      - disable_during_state_run: True
      - onchangeonly: True
    load:
      averages:
        1m:
          - 0.0
          - {{ ('%.2f' % load_max_1m)|float }}
        5m:
          - 0.0
          - {{ ('%.2f' % load_max_5m)|float }}
        15m:
          - 0.0
          - {{ ('%.2f' % load_max_15m)|float }}
    memusage:
      - percent: {{ ('%.2f' % mem_warn_percent)|float }}
      - interval: 60
      - onchangeonly: False
      - emitatstartup: False
    diskusage:
      interval: 120
      percent:
        /: {{ ('%.2f' % disk_root_percent)|float }}
    inotify:
      - files:
          /etc/nginx/nginx.conf:
            mask:
              - modify
              - close_write
          /etc/mysql/mysql.conf.d/mysqld.cnf:
            mask:
              - modify
              - close_write
          /var/www:
            mask:
              - create
              - close_write
              - attrib
            recurse: True
            if_missing: warn
            auto_add: True
            sls_whitelist:
              - optional.magento-permissions
        interval: 60
    pkg:
      interval: 3600
      pkgs:
        - nginx
        - mysql-server
        - php8.3-fpm
        - valkey
        - rabbitmq-server
        - opensearch
    telegram_bot_msg:
      - token: "{{ telegram_cfg.get('token', '') }}"
      - accept_from:
{% for chat in accept_from %}
          - {{ chat }}
{% endfor %}
      - chat_id: {{ default_chat_id }}
      - interval: 10
      - name: primary
    watchdog:
      - directories:
          /var/www:
            mask:
              - create
              - modify
              - delete
              - move
      - interval: 15
  beacons_blacklist:
    - adb
    - aix_account
    - avahi_announce
    - bonjour_announce
    - glxinfo
    - vmadm
    - twilio_txt_msg
    - haproxy
    - journald
    - network_settings
    - sensehat
    - smartos_imgadm
    - smartos_vmadm
    - imgadm
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
    backups:
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

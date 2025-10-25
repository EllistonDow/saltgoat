# Magento RabbitMQ 管理（Salt 原生）

{# Pillar inputs #}
{% set site_name = pillar.get('site_name') %}
{% set site_path = pillar.get('site_path', '/var/www/{0}'.format(site_name) if site_name else None) %}
{% set amqp_host = pillar.get('amqp_host', '127.0.0.1') %}
{% set amqp_port = pillar.get('amqp_port', 5672) %}
{% set amqp_user = pillar.get('amqp_user', site_name if site_name else 'magento') %}
{% set amqp_password = pillar.get('amqp_password') %}
{% set amqp_vhost = pillar.get('amqp_vhost', '/' ~ site_name if site_name else '/magento') %}
{% set mode = pillar.get('mode', 'smart') %}
{% set threads = pillar.get('threads', 2) %}
{% set service_user = pillar.get('service_user', 'www-data') %}
{% set php_memory_limit = pillar.get('php_memory_limit', '2G') %}
{% set cpu_quota = pillar.get('cpu_quota', '50%') %}
{% set nice = pillar.get('nice', '10') %}

{% if not site_name %}
magento_rabbitmq_missing_site:
  test.fail_without_changes:
    - comment: "pillar['site_name'] 未提供。"
{% elif not site_path %}
magento_rabbitmq_missing_path:
  test.fail_without_changes:
    - comment: "无法推导站点路径，请提供 pillar['site_path']。"
{% else %}

{% set env_file = site_path ~ '/app/etc/env.php' %}
{% set site_exists = salt['file.directory_exists'](site_path) %}
{% set env_exists = salt['file.file_exists'](env_file) %}

{% if not site_exists %}
magento_rabbitmq_site_missing:
  test.fail_without_changes:
    - comment: "站点目录 {{ site_path }} 不存在。"
{% elif not env_exists %}
magento_rabbitmq_env_missing:
  test.fail_without_changes:
    - comment: "未找到 {{ env_file }}，请确认 Magento 已安装。"
{% else %}

{# Consumer sets #}
{% set consumers_all = [
  'async.operations.all',
  'product_action_attribute.update',
  'product_action_attribute.website.update',
  'catalog_website_attribute_value_sync',
  'media.storage.catalog.image.resize',
  'exportProcessor',
  'inventory.source.items.cleanup',
  'inventory.mass.update',
  'inventory.reservations.cleanup',
  'inventory.reservations.update',
  'inventory.reservations.updateSalabilityStatus',
  'inventory.indexer.sourceItem',
  'inventory.indexer.stock',
  'media.content.synchronization',
  'media.gallery.renditions.update',
  'media.gallery.synchronization',
  'codegeneratorProcessor',
  'sales.rule.update.coupon.usage',
  'sales.rule.quote.trigger.recollect',
  'product_alert',
  'saveConfigProcessor',
] %}
{% set consumers_smart = [
  'async.operations.all',
  'product_action_attribute.update',
  'media.storage.catalog.image.resize',
  'exportProcessor',
  'inventory.reservations.update',
  'inventory.indexer.stock',
  'media.content.synchronization',
  'sales.rule.update.coupon.usage',
  'product_alert',
  'saveConfigProcessor',
] %}
{% set consumers = consumers_all if mode == 'all' else consumers_smart %}

{# Ensure RabbitMQ service present (best-effort) #}
rabbitmq_server_running_primary:
  service.running:
    - name: rabbitmq-server
    - enable: True
    - onlyif: test -e /lib/systemd/system/rabbitmq-server.service || systemctl status rabbitmq-server >/dev/null 2>&1

rabbitmq_server_running_alias:
  service.running:
    - name: rabbitmq
    - enable: True
    - onlyif: test -e /lib/systemd/system/rabbitmq.service || systemctl status rabbitmq >/dev/null 2>&1

{# Configure vhost, user, permissions #}
magento_rabbitmq_vhost:
  rabbitmq_vhost.present:
    - name: {{ amqp_vhost }}

magento_rabbitmq_user:
  rabbitmq_user.present:
    - name: {{ amqp_user }}
    - password: {{ amqp_password }}
    - require:
      - rabbitmq_vhost: magento_rabbitmq_vhost

magento_rabbitmq_permissions:
  cmd.run:
    - name: sudo rabbitmqctl set_permissions -p '{{ amqp_vhost }}' '{{ amqp_user }}' '.*' '.*' '.*'
    - unless: sudo rabbitmqctl list_permissions -p '{{ amqp_vhost }}' 2>/dev/null | awk '{print $1}' | grep -qx '{{ amqp_user }}'
    - require:
      - rabbitmq_user: magento_rabbitmq_user

{# Update Magento AMQP in env.php #}
magento_rabbitmq_config_env:
  cmd.run:
    - name: |
        php <<'PHP'
        <?php
        $envFile = 'app/etc/env.php';
        $cfg = include $envFile;
        if (!is_array($cfg)) { fwrite(STDERR, "env.php 解析失败\n"); exit(1);} 
        $cfg['queue']['consumers_wait_for_messages'] = 1;
        $cfg['queue']['amqp'] = [
          'host' => '{{ amqp_host }}',
          'port' => '{{ amqp_port }}',
          'user' => '{{ amqp_user }}',
          'password' => '{{ amqp_password }}',
          'virtualhost' => '{{ amqp_vhost }}',
        ];
        $export = "<?php\nreturn " . var_export($cfg, true) . ";\n";
        if (false === file_put_contents($envFile, $export, LOCK_EX)) { fwrite(STDERR, "写入失败\n"); exit(1);} 
        ?>
        PHP
    - cwd: {{ site_path }}
    - runas: www-data
    - unless: |
        php <<'PHP'
        <?php
        $cfg = include 'app/etc/env.php';
        if (!is_array($cfg)) exit(1);
        $amqp = $cfg['queue']['amqp'] ?? [];
        exit((isset($amqp['host']) && $amqp['host'] === '{{ amqp_host }}'
          && (string)($amqp['port'] ?? '') === '{{ amqp_port }}'
          && ($amqp['user'] ?? '') === '{{ amqp_user }}'
          && ($amqp['password'] ?? '') === '{{ amqp_password }}'
          && ($amqp['virtualhost'] ?? '') === '{{ amqp_vhost }}') ? 0 : 1);
        ?>
        PHP
    - require:
      - rabbitmq_user: magento_rabbitmq_user

{# Install systemd template unit #}
/etc/systemd/system/magento-consumer@.service:
  file.managed:
    - mode: '0644'
    - user: root
    - group: root
    - contents: |
        [Unit]
        Description=Magento Consumer instance %i
        After=network.target rabbitmq-server.service
        Wants=rabbitmq-server.service

        [Service]
        Type=simple
        User={{ service_user }}
        Group={{ service_user }}
        WorkingDirectory=/
        ExecStart=/bin/sh -lc '\
          INSTANCE="%i"; \
          INDEX="${INSTANCE##*-}"; \
          REST="${INSTANCE%-$INDEX}"; \
          if [ -z "$REST" ] || [ -z "$INDEX" ]; then \
            echo "[magento-consumer@$INSTANCE] unable to parse instance identifier"; exit 1; \
          fi; \
          CONSUMER="${REST##*-}"; \
          SITE="${REST%-${CONSUMER}}"; \
          SITE="${SITE%-}"; \
          if [ -z "$SITE" ] || [ -z "$CONSUMER" ]; then \
            echo "[magento-consumer@$INSTANCE] missing SITE or CONSUMER"; exit 1; \
          fi; \
          cd /var/www/$SITE || exit 1; \
          FAILS=0; \
          while true; do \
            /usr/bin/php -d memory_limit={{ php_memory_limit }} bin/magento queue:consumers:start "$CONSUMER" --single-thread --max-messages=10000; RC=$?; \
            if [ $RC -ne 0 ]; then \
              FAILS=$((FAILS+1)); SLEEP=$(( FAILS<5 ? 5 : 30 )); \
              echo "[magento-consumer@$SITE-$CONSUMER] exit code=$RC, backoff=$SLEEP s"; \
              sleep $SLEEP; \
            else \
              FAILS=0; sleep 2; \
            fi; \
          done\
        '
        Restart=always
        RestartSec=5
        StandardOutput=journal
        StandardError=journal
        MemoryMax={{ php_memory_limit }}
        CPUQuota={{ cpu_quota }}
        Nice={{ nice }}
        LimitNOFILE=65536

        [Install]
        WantedBy=multi-user.target

systemd_daemon_reload_for_magento_consumers:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: /etc/systemd/system/magento-consumer@.service

{# Declare and start units #}
{% for consumer in consumers %}
  {% for n in range(1, (threads if threads is number else 2) + 1) %}
magento_consumer_unit_{{ consumer | replace('.', '_') }}_{{ n }}_enabled:
  service.enabled:
    - name: magento-consumer@{{ site_name }}-{{ consumer }}-{{ n }}.service
    - require:
      - file: /etc/systemd/system/magento-consumer@.service

magento_consumer_unit_{{ consumer | replace('.', '_') }}_{{ n }}_running:
  service.running:
    - name: magento-consumer@{{ site_name }}-{{ consumer }}-{{ n }}.service
    - enable: True
    - require:
      - service: magento_consumer_unit_{{ consumer | replace('.', '_') }}_{{ n }}_enabled
      - cmd: systemd_daemon_reload_for_magento_consumers
      - cmd: magento_rabbitmq_config_env
  {% endfor %}
{% endfor %}

{% endif %}
{% endif %}

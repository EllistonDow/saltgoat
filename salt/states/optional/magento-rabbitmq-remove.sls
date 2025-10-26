# Magento RabbitMQ 清理（Salt 原生）

{% set site_name = pillar.get('site_name') %}
{% set site_path = pillar.get('site_path', '/var/www/{0}'.format(site_name) if site_name else None) %}
{% set service_user = pillar.get('service_user', 'www-data') %}
{% set magento_php = 'sudo -u {0} php'.format(service_user) if service_user else 'php' %}
{% set site_exists = site_path and salt['file.directory_exists'](site_path) %}
{% set env_file = site_path ~ '/app/etc/env.php' if site_path else None %}
{% set env_exists = env_file and salt['file.file_exists'](env_file) %}

{% if not site_name %}
magento_rabbitmq_remove_missing_site:
  test.fail_without_changes:
    - comment: "pillar['site_name'] 未提供，无法清理。"
{% else %}

magento_rabbitmq_remove_units:
  cmd.run:
    - name: |
        bash -euo pipefail <<'SH'
        SITE="{{ site_name }}"
        removed=0
        list_units() {
          systemctl list-units --type=service --all --no-legend 2>/dev/null \
            | awk '{print $1}' \
            | grep -E "^magento-consumer(@|-)${SITE}-.*\.service$" || true
        }
        while IFS= read -r unit; do
          [[ -z "$unit" ]] && continue
          systemctl stop "$unit" >/dev/null 2>&1 || true
          systemctl disable "$unit" >/dev/null 2>&1 || true
          systemctl reset-failed "$unit" >/dev/null 2>&1 || true
          echo "[INFO] 已停用消费者: $unit"
          removed=1
        done < <(list_units)

        shopt -s nullglob
        for path in /etc/systemd/system/magento-consumer-${SITE}-*.service; do
          [[ -e "$path" ]] || continue
          rm -f "$path"
          echo "[INFO] 已删除旧版 unit: $path"
          removed=1
        done
        for path in /etc/systemd/system/*/magento-consumer-${SITE}-*.service; do
          [[ -e "$path" ]] || continue
          rm -f "$path"
          echo "[INFO] 已删除旧版 unit: $path"
          removed=1
        done

        if [[ "$removed" -eq 0 ]]; then
          echo "[INFO] 未发现 {{ site_name }} 相关消费者单元"
        fi
        SH

magento_rabbitmq_remove_daemon_reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - cmd: magento_rabbitmq_remove_units

{% if site_exists and env_exists %}
magento_rabbitmq_remove_env:
  cmd.run:
    - name: |
        {{ magento_php }} <<'PHP'
        <?php
        $envFile = 'app/etc/env.php';
        $cfg = include $envFile;
        if (!is_array($cfg)) { exit(0); }
        $changed = false;
        if (isset($cfg['queue']['amqp'])) {
            unset($cfg['queue']['amqp']);
            $changed = true;
        }
        if (isset($cfg['queue']['consumers_wait_for_messages'])) {
            unset($cfg['queue']['consumers_wait_for_messages']);
            $changed = true;
        }
        if (isset($cfg['queue']) && empty($cfg['queue'])) {
            unset($cfg['queue']);
            $changed = true;
        }
        if (!$changed) {
            exit(0);
        }
        $export = "<?php\nreturn " . var_export($cfg, true) . ";\n";
        if (false === file_put_contents($envFile, $export, LOCK_EX)) {
            fwrite(STDERR, "写入 env.php 失败\n");
            exit(1);
        }
        ?>
        PHP
    - cwd: {{ site_path }}
    - unless: |
        {{ magento_php }} <<'PHP'
        <?php
        $cfg = include 'app/etc/env.php';
        if (!is_array($cfg)) { exit(0); }
        if (!isset($cfg['queue']['amqp']) && !isset($cfg['queue']['consumers_wait_for_messages'])) {
            exit(0);
        }
        exit(1);
        ?>
        PHP
    - require:
      - cmd: magento_rabbitmq_remove_units
{% endif %}

{% endif %}

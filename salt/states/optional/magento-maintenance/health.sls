# Magento 维护：健康检查

{% set site_name = pillar.get('site_name') %}
{% set site_path = pillar.get('site_path', '/var/www/{0}'.format(site_name) if site_name else None) %}
{% set magento_user = pillar.get('magento_user', 'www-data') %}
{% set php_bin = pillar.get('php_bin', 'php') %}
{% set site_exists = site_path and salt['file.directory_exists'](site_path) %}
{% set magento_bin = site_path ~ '/bin/magento' if site_path else None %}
{% set magento_exists = magento_bin and salt['file.file_exists'](magento_bin) %}

{% if not site_name %}
magento_maintenance_health_missing_site:
  test.fail_without_changes:
    - comment: "pillar['site_name'] 未提供，无法执行健康检查。"
{% elif not site_path %}
magento_maintenance_health_missing_path:
  test.fail_without_changes:
    - comment: "pillar['site_path'] 未提供且无法推导站点路径。"
{% elif not site_exists %}
magento_maintenance_health_site_absent:
  test.fail_without_changes:
    - comment: "站点目录 {{ site_path }} 不存在。"
{% elif not magento_exists %}
magento_maintenance_health_magento_absent:
  test.fail_without_changes:
    - comment: "未找到 {{ site_path }}/bin/magento，确认 Magento 是否已安装。"
{% else %}

magento_maintenance_health_version:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento --version
    - cwd: {{ site_path }}

magento_maintenance_health_db_status:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento setup:db:status
    - cwd: {{ site_path }}

magento_maintenance_health_cache_status:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento cache:status
    - cwd: {{ site_path }}

magento_maintenance_health_indexer_status:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento indexer:status
    - cwd: {{ site_path }}

magento_maintenance_health_queue_consumers:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento queue:consumers:list
    - cwd: {{ site_path }}

magento_maintenance_health_cron_check:
  cmd.run:
    - name: |
        bash -euo pipefail <<'SH'
        for candidate in "{{ site_path }}/var/log/magento.cron.log" "{{ site_path }}/var/log/cron.log"; do
          if [ -f "$candidate" ]; then
            ts=$(date -r "$candidate" '+%F %T')
            echo "[INFO] Cron 日志存在: $candidate (最近更新时间 $ts)"
            tail -n 5 "$candidate" || true
            exit 0
          fi
        done
        echo "[WARNING] 未找到 Magento cron 日志，请确认 cron/schedule 是否正常运行。"
        SH
    - runas: root

magento_maintenance_health_fpc_mode:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento config:show system/full_page_cache/caching_application
    - cwd: {{ site_path }}

magento_maintenance_health_n98_syscheck:
  cmd.run:
    - name: sudo -u {{ magento_user }} n98-magerun2 sys:check
    - cwd: {{ site_path }}
    - onlyif: command -v n98-magerun2 >/dev/null 2>&1

magento_maintenance_health_disk_usage:
  cmd.run:
    - name: df -h {{ site_path }}
    - runas: root

{% endif %}

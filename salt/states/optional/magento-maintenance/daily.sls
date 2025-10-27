# Magento 维护：每日任务

{% set site_name = pillar.get('site_name') %}
{% set site_path = pillar.get('site_path', '/var/www/{0}'.format(site_name) if site_name else None) %}
{% set magento_user = pillar.get('magento_user', 'www-data') %}
{% set php_bin = pillar.get('php_bin', 'php') %}
{% set site_exists = site_path and salt['file.directory_exists'](site_path) %}
{% set magento_bin = site_path ~ '/bin/magento' if site_path else None %}
{% set magento_exists = magento_bin and salt['file.file_exists'](magento_bin) %}

{% if not site_name %}
magento_maintenance_daily_missing_site:
  test.fail_without_changes:
    - comment: "pillar['site_name'] 未提供，无法执行每日任务。"
{% elif not site_path %}
magento_maintenance_daily_missing_path:
  test.fail_without_changes:
    - comment: "pillar['site_path'] 未提供且无法推导站点路径。"
{% elif not site_exists %}
magento_maintenance_daily_site_absent:
  test.fail_without_changes:
    - comment: "站点目录 {{ site_path }} 不存在。"
{% elif not magento_exists %}
magento_maintenance_daily_magento_absent:
  test.fail_without_changes:
    - comment: "未找到 {{ site_path }}/bin/magento，确认 Magento 是否已安装。"
{% else %}

magento_maintenance_daily_cache_flush:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento cache:flush
    - cwd: {{ site_path }}

magento_maintenance_daily_indexer_reindex:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento indexer:reindex
    - cwd: {{ site_path }}
    - require:
      - cmd: magento_maintenance_daily_cache_flush

magento_maintenance_daily_permission_check:
  cmd.run:
    - name: |
        bash -euo pipefail <<'SH'
        count=$(find var generated -user root 2>/dev/null | wc -l || true)
        if [ "$count" -gt 0 ]; then
          echo "[WARNING] 发现 ${count} 个 root 拥有的文件 (var/, generated/)。建议执行 saltgoat magetools permissions fix {{ site_path }}。"
        else
          echo "[INFO] 权限检查通过。"
        fi
        SH
    - cwd: {{ site_path }}
    - runas: root

magento_maintenance_daily_session_clean:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento session:clean
    - cwd: {{ site_path }}

magento_maintenance_daily_log_clean:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento log:clean
    - cwd: {{ site_path }}

magento_maintenance_daily_cache_clean:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento cache:clean
    - cwd: {{ site_path }}

{% endif %}

# Magento 维护：清理任务

{% set site_name = pillar.get('site_name') %}
{% set site_path = pillar.get('site_path', '/var/www/{0}'.format(site_name) if site_name else None) %}
{% set magento_user = pillar.get('magento_user', 'www-data') %}
{% set php_bin = pillar.get('php_bin', 'php') %}
{% set site_exists = site_path and salt['file.directory_exists'](site_path) %}
{% set magento_bin = site_path ~ '/bin/magento' if site_path else None %}
{% set magento_exists = magento_bin and salt['file.file_exists'](magento_bin) %}

{% if not site_name %}
magento_maintenance_cleanup_missing_site:
  test.fail_without_changes:
    - comment: "pillar['site_name'] 未提供，无法执行清理任务。"
{% elif not site_path %}
magento_maintenance_cleanup_missing_path:
  test.fail_without_changes:
    - comment: "pillar['site_path'] 未提供且无法推导站点路径。"
{% elif not site_exists %}
magento_maintenance_cleanup_site_absent:
  test.fail_without_changes:
    - comment: "站点目录 {{ site_path }} 不存在。"
{% elif not magento_exists %}
magento_maintenance_cleanup_magento_absent:
  test.fail_without_changes:
    - comment: "未找到 {{ site_path }}/bin/magento，确认 Magento 是否已安装。"
{% else %}

magento_maintenance_cleanup_cache:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento cache:flush
    - cwd: {{ site_path }}

magento_maintenance_cleanup_generated:
  cmd.run:
    - name: |
        bash -euo pipefail <<'SH'
        rm -rf "{{ site_path }}/generated/"*
        chown -R {{ magento_user }}:{{ magento_user }} "{{ site_path }}/generated"
        chmod -R 775 "{{ site_path }}/generated"
        SH
    - runas: root

magento_maintenance_cleanup_logs:
  cmd.run:
    - name: |
        bash -euo pipefail <<'SH'
        find "{{ site_path }}/var/log" -type f -name "*.log" -exec truncate -s 0 {} \;
        SH
    - runas: root

magento_maintenance_cleanup_sessions:
  cmd.run:
    - name: |
        bash -euo pipefail <<'SH'
        find "{{ site_path }}/var/session" -type f -name "sess_*" -mtime +1 -delete
        SH
    - runas: root

magento_maintenance_cleanup_tmp:
  cmd.run:
    - name: |
        bash -euo pipefail <<'SH'
        find "{{ site_path }}/var/tmp" -mindepth 1 -mtime +1 -delete
        SH
    - runas: root

{% endif %}

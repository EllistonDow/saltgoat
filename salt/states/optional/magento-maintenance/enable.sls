# Magento 维护：启用维护模式

{% set site_name = pillar.get('site_name') %}
{% set site_path = pillar.get('site_path', '/var/www/{0}'.format(site_name) if site_name else None) %}
{% set magento_user = pillar.get('magento_user', 'www-data') %}
{% set php_bin = pillar.get('php_bin', 'php') %}
{% set site_exists = site_path and salt['file.directory_exists'](site_path) %}
{% set magento_bin = site_path ~ '/bin/magento' if site_path else None %}
{% set magento_exists = magento_bin and salt['file.file_exists'](magento_bin) %}

{% if not site_name %}
magento_maintenance_enable_missing_site:
  test.fail_without_changes:
    - comment: "pillar['site_name'] 未提供，无法启用维护模式。"
{% elif not site_path %}
magento_maintenance_enable_missing_path:
  test.fail_without_changes:
    - comment: "pillar['site_path'] 未提供且无法推导站点路径。"
{% elif not site_exists %}
magento_maintenance_enable_site_absent:
  test.fail_without_changes:
    - comment: "站点目录 {{ site_path }} 不存在。"
{% elif not magento_exists %}
magento_maintenance_enable_magento_absent:
  test.fail_without_changes:
    - comment: "未找到 {{ site_path }}/bin/magento，确认 Magento 是否已安装。"
{% else %}

magento_maintenance_enable:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento maintenance:enable
    - cwd: {{ site_path }}
    - unless: sudo -u {{ magento_user }} {{ php_bin }} bin/magento maintenance:status | grep -q "Maintenance mode is enabled"

{% endif %}

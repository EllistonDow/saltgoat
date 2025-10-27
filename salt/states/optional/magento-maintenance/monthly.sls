# Magento 维护：每月任务（高风险项需显式允许）

{% set site_name = pillar.get('site_name') %}
{% set site_path = pillar.get('site_path', '/var/www/{0}'.format(site_name) if site_name else None) %}
{% set magento_user = pillar.get('magento_user', 'www-data') %}
{% set php_bin = pillar.get('php_bin', 'php') %}
{% set composer_bin = pillar.get('composer_bin', 'composer') %}
{% set static_languages = pillar.get('static_languages') %}
{% set static_jobs = pillar.get('static_jobs', 4) %}
{% set allow_setup_upgrade = pillar.get('allow_setup_upgrade', False) %}
{% set site_exists = site_path and salt['file.directory_exists'](site_path) %}
{% set magento_bin = site_path ~ '/bin/magento' if site_path else None %}
{% set magento_exists = magento_bin and salt['file.file_exists'](magento_bin) %}

{% if not site_name %}
magento_maintenance_monthly_missing_site:
  test.fail_without_changes:
    - comment: "pillar['site_name'] 未提供，无法执行每月任务。"
{% elif not site_path %}
magento_maintenance_monthly_missing_path:
  test.fail_without_changes:
    - comment: "pillar['site_path'] 未提供且无法推导站点路径。"
{% elif not site_exists %}
magento_maintenance_monthly_site_absent:
  test.fail_without_changes:
    - comment: "站点目录 {{ site_path }} 不存在。"
{% elif not magento_exists %}
magento_maintenance_monthly_magento_absent:
  test.fail_without_changes:
    - comment: "未找到 {{ site_path }}/bin/magento，确认 Magento 是否已安装。"
{% else %}

magento_maintenance_monthly_ensure_maintenance:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento maintenance:enable
    - cwd: {{ site_path }}

magento_maintenance_monthly_cleanup_generated:
  cmd.run:
    - name: |
        bash -euo pipefail <<'SH'
        rm -rf "{{ site_path }}/var/cache"/*
        rm -rf "{{ site_path }}/var/page_cache"/*
        rm -rf "{{ site_path }}/var/view_preprocessed"/*
        rm -rf "{{ site_path }}/generated"/*
        rm -rf "{{ site_path }}/pub/static"/*
        rm -rf "{{ site_path }}/pub/media/catalog/product/cache"/*
        chown -R {{ magento_user }}:{{ magento_user }} "{{ site_path }}/generated"
        SH
    - runas: root

{% if allow_setup_upgrade %}
magento_maintenance_monthly_setup_upgrade:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento setup:upgrade
    - cwd: {{ site_path }}
{% else %}
magento_maintenance_monthly_setup_upgrade_skipped:
  test.succeed_without_changes:
    - comment: "setup:upgrade 已跳过（allow_setup_upgrade=False）。"
{% endif %}

magento_maintenance_monthly_di_compile:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento setup:di:compile
    - cwd: {{ site_path }}

magento_maintenance_monthly_static_deploy:
  cmd.run:
    - name: |
        sudo -u {{ magento_user }} {{ php_bin }} bin/magento setup:static-content:deploy -f -j {{ static_jobs }} {% if static_languages %}{{ static_languages }}{% endif %}
    - cwd: {{ site_path }}

magento_maintenance_monthly_indexer_reindex:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento indexer:reindex
    - cwd: {{ site_path }}

magento_maintenance_monthly_disable_maintenance:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento maintenance:disable
    - cwd: {{ site_path }}

magento_maintenance_monthly_cache_clean:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento cache:clean
    - cwd: {{ site_path }}

magento_maintenance_monthly_sitemap:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento sitemap:generate
    - cwd: {{ site_path }}

magento_maintenance_monthly_module_status:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento module:status
    - cwd: {{ site_path }}

{% endif %}

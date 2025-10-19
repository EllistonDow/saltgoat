# Magento 2 高效权限设置（Salt 原生方法）

{% set site_path = '/var/www/tank' %}

# 设置站点根目录权限
set_site_root_permissions:
  cmd.run:
    - name: |
        chown -R www-data:www-data {{ site_path }}
        chmod 755 {{ site_path }}

# 设置 Magento 核心目录权限
set_magento_core_permissions:
  cmd.run:
    - name: |
        chown -R www-data:www-data {{ site_path }}/app {{ site_path }}/bin {{ site_path }}/dev {{ site_path }}/lib {{ site_path }}/phpserver {{ site_path }}/pub {{ site_path }}/setup {{ site_path }}/vendor
        chmod -R 755 {{ site_path }}/app {{ site_path }}/bin {{ site_path }}/dev {{ site_path }}/lib {{ site_path }}/phpserver {{ site_path }}/pub {{ site_path }}/setup {{ site_path }}/vendor
    - require:
      - cmd: set_site_root_permissions

# 设置可写目录权限（775）
set_writable_directories:
  cmd.run:
    - name: |
        chown -R www-data:www-data {{ site_path }}/var {{ site_path }}/generated {{ site_path }}/pub/media {{ site_path }}/pub/static {{ site_path }}/app/etc
        chmod -R 775 {{ site_path }}/var {{ site_path }}/generated {{ site_path }}/pub/media {{ site_path }}/pub/static {{ site_path }}/app/etc
    - require:
      - cmd: set_magento_core_permissions

# 设置配置文件权限（660）
set_config_file_permissions:
  cmd.run:
    - name: |
        chown www-data:www-data {{ site_path }}/app/etc/env.php
        chmod 660 {{ site_path }}/app/etc/env.php
    - require:
      - cmd: set_writable_directories

# 确保 www-data 可以访问父目录
ensure_parent_directory_access:
  cmd.run:
    - name: |
        chmod 755 /var/www
        chown root:www-data /var/www
    - require:
      - cmd: set_config_file_permissions
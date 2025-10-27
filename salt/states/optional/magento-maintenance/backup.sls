# Magento 维护：传统备份（tar + mysqldump）

{% set site_name = pillar.get('site_name') %}
{% set site_path = pillar.get('site_path', '/var/www/{0}'.format(site_name) if site_name else None) %}
{% set backup_dir = pillar.get('backup_target_dir', '/var/backups/magento') %}
{% set backup_keep_days = pillar.get('backup_keep_days', 7) %}
{% set mysql_database = pillar.get('mysql_database', site_name) %}
{% set mysql_user = pillar.get('mysql_user', 'root') %}
{% set mysql_password = pillar.get('mysql_password') %}
{% set site_exists = site_path and salt['file.directory_exists'](site_path) %}

{% if not site_name %}
magento_maintenance_backup_missing_site:
  test.fail_without_changes:
    - comment: "pillar['site_name'] 未提供，无法执行备份。"
{% elif not site_path %}
magento_maintenance_backup_missing_path:
  test.fail_without_changes:
    - comment: "pillar['site_path'] 未提供且无法推导站点路径。"
{% elif not site_exists %}
magento_maintenance_backup_site_absent:
  test.fail_without_changes:
    - comment: "站点目录 {{ site_path }} 不存在。"
{% else %}

magento_maintenance_backup_dir:
  file.directory:
    - name: {{ backup_dir }}
    - mode: '0750'
    - user: root
    - group: root

magento_maintenance_backup_files:
  cmd.run:
    - name: |
        bash -euo pipefail <<'SH'
        TS=$(date +%Y%m%d_%H%M%S)
        archive="{{ backup_dir }}/{{ site_name }}_${TS}.tar.gz"
        tar --exclude="var/cache" \
            --exclude="var/page_cache" \
            --exclude="var/view_preprocessed" \
            --exclude="var/log" \
            --exclude="generated/code" \
            -czf "$archive" -C "{{ site_path }}" .
        SH
    - require:
      - file: magento_maintenance_backup_dir

{% if mysql_database %}
magento_maintenance_backup_database:
  cmd.run:
    - name: |
        bash -euo pipefail <<'SH'
        command -v mysqldump >/dev/null 2>&1 || exit 0
        TS=$(date +%Y%m%d_%H%M%S)
        outfile="{{ backup_dir }}/{{ site_name }}_db_${TS}.sql"
        {% if mysql_password %}
        export MYSQL_PWD="{{ mysql_password }}"
        {% endif %}
        mysqldump -u {{ mysql_user }} --single-transaction --quick "{{ mysql_database }}" > "$outfile"
        SH
    - require:
      - file: magento_maintenance_backup_dir
{% endif %}

magento_maintenance_backup_retention:
  cmd.run:
    - name: |
        bash -euo pipefail <<'SH'
        find "{{ backup_dir }}" -maxdepth 1 -type f -name "{{ site_name }}_*.tar.gz" -mtime +{{ backup_keep_days|int }} -delete
        find "{{ backup_dir }}" -maxdepth 1 -type f -name "{{ site_name }}_db_*.sql" -mtime +{{ backup_keep_days|int }} -delete
        SH
    - require:
      - file: magento_maintenance_backup_dir

{% endif %}

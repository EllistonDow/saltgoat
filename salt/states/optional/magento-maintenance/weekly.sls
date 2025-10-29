# Magento 维护：每周任务

{% set site_name = pillar.get('site_name') %}
{% set site_path = pillar.get('site_path', '/var/www/{0}'.format(site_name) if site_name else None) %}
{% set magento_user = pillar.get('magento_user', 'www-data') %}
{% set php_bin = pillar.get('php_bin', 'php') %}
{% set composer_bin = pillar.get('composer_bin', 'composer') %}
{% set valkey_cli = pillar.get('valkey_cli', pillar.get('redis_cli', 'valkey-cli')) %}
{% set valkey_password = pillar.get('valkey_password', pillar.get('redis_password')) %}
{% set allow_valkey_flush = pillar.get('allow_valkey_flush', pillar.get('allow_redis_flush', False)) %}
{% set backup_dir = pillar.get('backup_target_dir') %}
{% set backup_keep_days = pillar.get('backup_keep_days', 7) %}
{% set mysql_database = pillar.get('mysql_database', site_name) %}
{% set mysql_user = pillar.get('mysql_user', 'root') %}
{% set mysql_password = pillar.get('mysql_password') %}
{% set trigger_restic = pillar.get('trigger_restic', False) %}
{% set restic_site_override = pillar.get('restic_site_override') %}
{% set restic_repo_override = pillar.get('restic_repo_override') %}
{% set restic_extra_paths = pillar.get('restic_extra_paths', []) %}
{% set restic_custom = restic_site_override or restic_repo_override or restic_extra_paths %}
{% set site_exists = site_path and salt['file.directory_exists'](site_path) %}
{% set magento_bin = site_path ~ '/bin/magento' if site_path else None %}
{% set magento_exists = magento_bin and salt['file.file_exists'](magento_bin) %}

{% if not site_name %}
magento_maintenance_weekly_missing_site:
  test.fail_without_changes:
    - comment: "pillar['site_name'] 未提供，无法执行每周任务。"
{% elif not site_path %}
magento_maintenance_weekly_missing_path:
  test.fail_without_changes:
    - comment: "pillar['site_path'] 未提供且无法推导站点路径。"
{% elif not site_exists %}
magento_maintenance_weekly_site_absent:
  test.fail_without_changes:
    - comment: "站点目录 {{ site_path }} 不存在。"
{% elif not magento_exists %}
magento_maintenance_weekly_magento_absent:
  test.fail_without_changes:
    - comment: "未找到 {{ site_path }}/bin/magento，确认 Magento 是否已安装。"
{% else %}

magento_maintenance_weekly_cache_flush:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento cache:flush
    - cwd: {{ site_path }}

magento_maintenance_weekly_indexer_status:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento indexer:status
    - cwd: {{ site_path }}
    - require:
      - cmd: magento_maintenance_weekly_cache_flush

magento_maintenance_weekly_indexer_reindex:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento indexer:reindex
    - cwd: {{ site_path }}
    - require:
      - cmd: magento_maintenance_weekly_indexer_status

magento_maintenance_weekly_log_rotate:
  cmd.run:
    - name: |
        bash -euo pipefail <<'SH'
        find "{{ site_path }}/var/log" -type f -name "*.log" -size +100M -exec truncate -s 0 {} \;
        SH
    - runas: root

{% if allow_valkey_flush %}
magento_maintenance_weekly_valkey_flush:
  cmd.run:
    - name: |
        if command -v "{{ valkey_cli }}" >/dev/null 2>&1; then
          {% if valkey_password %}{{ valkey_cli }} -a "{{ valkey_password }}" FLUSHALL{% else %}{{ valkey_cli }} FLUSHALL{% endif %}
        else
          exit 0
        fi
    - runas: root
{% else %}
magento_maintenance_weekly_valkey_flush_skipped:
  test.succeed_without_changes:
    - comment: "Valkey FLUSHALL 已跳过（allow_valkey_flush=False）。"
{% endif %}

{% if backup_dir %}
magento_maintenance_weekly_backup_dir:
  file.directory:
    - name: {{ backup_dir }}
    - mode: '0750'
    - user: root
    - group: root

magento_maintenance_weekly_backup_files:
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
      - file: magento_maintenance_weekly_backup_dir

{% if mysql_database %}
magento_maintenance_weekly_backup_database:
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
      - file: magento_maintenance_weekly_backup_dir
{% endif %}

magento_maintenance_weekly_backup_retention:
  cmd.run:
    - name: |
        bash -euo pipefail <<'SH'
        find "{{ backup_dir }}" -maxdepth 1 -type f -name "{{ site_name }}_*.tar.gz" -mtime +{{ backup_keep_days|int }} -delete
        find "{{ backup_dir }}" -maxdepth 1 -type f -name "{{ site_name }}_db_*.sql" -mtime +{{ backup_keep_days|int }} -delete
        SH
    - require:
      - file: magento_maintenance_weekly_backup_dir
{% endif %}

{% macro shquote(val) -%}'{{ val | replace("'", "'\\''") }}'{%- endmacro %}

{% if trigger_restic %}
  {% if restic_custom %}
    {% set restic_cmd = "saltgoat magetools backup restic run" %}
    {% if restic_site_override %}
      {% set restic_cmd = restic_cmd ~ " --site " ~ shquote(restic_site_override) %}
    {% endif %}
    {% if restic_repo_override %}
      {% set restic_cmd = restic_cmd ~ " --backup-dir " ~ shquote(restic_repo_override) %}
    {% endif %}
    {% for extra_path in restic_extra_paths %}
      {% set restic_cmd = restic_cmd ~ " --paths " ~ shquote(extra_path) %}
    {% endfor %}
magento_maintenance_weekly_restic_hook:
  cmd.run:
    - name: |
        if command -v saltgoat >/dev/null 2>&1; then
          {{ restic_cmd }} || true
        else
          echo "[INFO] 未找到 saltgoat，跳过 Restic 备份"
        fi
    - runas: root
  {% else %}
magento_maintenance_weekly_restic_hook:
  cmd.run:
    - name: |
        if command -v saltgoat >/dev/null 2>&1; then
          if [ -x /usr/local/bin/saltgoat-restic-backup ]; then
            /usr/local/bin/saltgoat-restic-backup
          else
            saltgoat magetools backup restic run || true
          fi
        elif [ -x /usr/local/bin/saltgoat-restic-backup ]; then
          /usr/local/bin/saltgoat-restic-backup
        else
          exit 0
        fi
    - runas: root
  {% endif %}
{% endif %}

magento_maintenance_weekly_n98_syscheck:
  cmd.run:
    - name: sudo -u {{ magento_user }} n98-magerun2 sys:check
    - cwd: {{ site_path }}
    - onlyif: command -v n98-magerun2 >/dev/null 2>&1

magento_maintenance_weekly_composer_outdated:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ composer_bin }} outdated --no-dev
    - cwd: {{ site_path }}
    - onlyif: command -v {{ composer_bin }} >/dev/null 2>&1

magento_maintenance_weekly_queue_consumers:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento queue:consumers:list
    - cwd: {{ site_path }}

magento_maintenance_weekly_cron_check:
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

magento_maintenance_weekly_fpc_mode:
  cmd.run:
    - name: sudo -u {{ magento_user }} {{ php_bin }} bin/magento config:show system/full_page_cache/caching_application
    - cwd: {{ site_path }}

{% endif %}

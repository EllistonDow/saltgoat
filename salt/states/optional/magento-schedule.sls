# SaltGoat Magento 2 定时维护任务（Salt Schedule 优先，自动回退 Cron）
# salt/states/optional/magento-schedule.sls

{% set site_name = pillar.get('site_name', 'tank') %}
{% set site_token = site_name | replace(' ', '_') | replace('-', '_') | lower %}
{% set magento_schedule_cfg = pillar.get('magento_schedule', {}) %}
{% set auto_schedule = pillar.get('auto_schedule', {}) %}
{% set maintenance_cmd = magento_schedule_cfg.get('maintenance_command', 'saltgoat magetools maintenance') %}
{% set maintenance_extra_args = magento_schedule_cfg.get('maintenance_extra_args', '') %}
{% set daily_args = magento_schedule_cfg.get('daily_args', '') %}
{% set weekly_args = magento_schedule_cfg.get('weekly_args', '') %}
{% set monthly_args = magento_schedule_cfg.get('monthly_args', '') %}
{% set health_args = magento_schedule_cfg.get('health_args', '') %}
{% set all_dump_jobs = auto_schedule.get('mysql_dump_jobs', magento_schedule_cfg.get('mysql_dump_jobs', [])) %}
{% set dump_jobs = namespace(items=[]) %}
{% for dump_job in all_dump_jobs %}
  {% if not dump_job.get('name') %}
    {% continue %}
  {% endif %}
  {% set job_site = dump_job.get('site') %}
  {% set job_sites = dump_job.get('sites') %}
  {% if job_site and job_site != site_name %}
    {% continue %}
  {% endif %}
  {% if job_sites and site_name not in job_sites %}
    {% continue %}
  {% endif %}
  {% do dump_jobs.items.append(dump_job) %}
{% endfor %}
{% set mysql_dump_jobs = dump_jobs.items %}

{% set all_api_watchers = auto_schedule.get('api_watchers', magento_schedule_cfg.get('api_watchers', [])) %}
{% set api_watchers_ns = namespace(items=[]) %}
{% for watcher in all_api_watchers %}
  {% if not watcher.get('name') %}
    {% continue %}
  {% endif %}
  {% set job_site = watcher.get('site') %}
  {% set job_sites = watcher.get('sites') %}
  {% if job_site and job_site != site_name %}
    {% continue %}
  {% endif %}
  {% if job_sites and site_name not in job_sites %}
    {% continue %}
  {% endif %}
  {% do api_watchers_ns.items.append(watcher) %}
{% endfor %}
{% set api_watchers = api_watchers_ns.items %}
{% set all_stats_jobs = auto_schedule.get('stats_jobs', magento_schedule_cfg.get('stats_jobs', [])) %}
{% set stats_jobs_ns = namespace(items=[]) %}
{% for stats_job in all_stats_jobs %}
  {% if not stats_job.get('name') %}
    {% continue %}
  {% endif %}
  {% set job_site = stats_job.get('site') %}
  {% set job_sites = stats_job.get('sites') %}
  {% if job_site and job_site != site_name %}
    {% continue %}
  {% endif %}
  {% if job_sites and site_name not in job_sites %}
    {% continue %}
  {% endif %}
  {% do stats_jobs_ns.items.append(stats_job) %}
{% endfor %}
{% set stats_jobs = stats_jobs_ns.items %}
{% set all_restic_jobs = auto_schedule.get('restic_jobs', magento_schedule_cfg.get('restic_jobs', [])) %}
{% set restic_jobs_ns = namespace(items=[]) %}
{% for restic_job in all_restic_jobs %}
  {% if not restic_job.get('name') %}
    {% continue %}
  {% endif %}
  {% set job_site = restic_job.get('site') %}
  {% set job_sites = restic_job.get('sites') %}
  {% if job_site and job_site != site_name %}
    {% continue %}
  {% endif %}
  {% if job_sites and site_name not in job_sites %}
    {% continue %}
  {% endif %}
  {% do restic_jobs_ns.items.append(restic_job) %}
{% endfor %}
{% set restic_jobs = restic_jobs_ns.items %}
{% macro shquote(val) -%}'{{ val | replace("'", "'\\''") }}'{%- endmacro %}
{% macro build_dump_cmd(job) -%}
saltgoat magetools xtrabackup mysql dump{% if job.get('database') %} --database {{ shquote(job.database) }}{% endif %}{% if job.get('backup_dir') %} --backup-dir {{ shquote(job.backup_dir) }}{% endif %}{% if job.get('repo_owner') %} --repo-owner {{ shquote(job.repo_owner) }}{% endif %} --site {{ shquote(site_name) }}{% if job.get('no_compress', False) %} --no-compress{% endif %}
{%- endmacro %}
{% macro build_stats_cmd(job) -%}
saltgoat magetools stats --site {{ site_name }}{% if job.get('period') %} --period {{ job.period }}{% else %} --period daily{% endif %}{% if job.get('page_size') %} --page-size {{ job.page_size }}{% endif %}{% if job.get('telegram_thread') is not none %} --telegram-thread {{ job.telegram_thread }}{% endif %}{% if job.get('no_telegram', False) %} --no-telegram{% endif %}{% if job.get('quiet', False) %} --quiet{% endif %}{% set job_extra = job.get('extra_args') %}{% if job_extra %}{% if job_extra is string %} {{ job_extra }}{% elif job_extra is sequence %}{% for arg in job_extra %} {{ arg }}{% endfor %}{% else %} {{ job_extra }}{% endif %}{% endif %}
{%- endmacro %}
{% macro build_restic_cmd(job) -%}
saltgoat magetools backup restic run --site {{ shquote(job.get('site_override', site_name)) }}{% if job.get('repo') %} --backup-dir {{ shquote(job.repo) }}{% endif %}{% set job_paths = job.get('paths') %}{% if job_paths %}{% if job_paths is string %} --paths {{ shquote(job_paths) }}{% elif job_paths is sequence %}{% set joined = job_paths | join(',') %}{% if joined %} --paths {{ shquote(joined) }}{% endif %}{% endif %}{% endif %}{% set job_tags = job.get('tags') %}{% if job_tags %}{% for tag in job_tags %} --tag {{ shquote(tag) }}{% endfor %}{% endif %}{% set extra = job.get('extra_args') %}{% if extra %}{% if extra is string %} {{ extra }}{% elif extra is sequence %}{% for arg in extra %} {{ arg }}{% endfor %}{% else %} {{ extra }}{% endif %}{% endif %}
{%- endmacro %}
{% set salt_minion_service = salt['file.file_exists']('/lib/systemd/system/salt-minion.service') or salt['file.file_exists']('/etc/systemd/system/salt-minion.service') %}
{% set cron_file = '/etc/cron.d/magento-maintenance-' ~ site_token %}
{% set legacy_cron_file = '/etc/cron.d/magento-maintenance' %}
{% set base_jobs = [
  {
    'name': 'magento_' ~ site_token ~ '_cron',
    'cron': '* * * * *',
    'command': 'cd /var/www/' ~ site_name ~ ' && sudo -u www-data php bin/magento cron:run >> /var/log/magento-cron.log 2>&1'
  },
  {
    'name': 'magento_' ~ site_token ~ '_daily',
    'cron': '0 2 * * *',
    'command': maintenance_cmd ~ ' ' ~ site_name ~ ' daily ' ~ maintenance_extra_args ~ ' ' ~ daily_args ~ ' >> /var/log/magento-maintenance.log 2>&1'
  },
  {
    'name': 'magento_' ~ site_token ~ '_weekly',
    'cron': '0 3 * * 0',
    'command': maintenance_cmd ~ ' ' ~ site_name ~ ' weekly ' ~ maintenance_extra_args ~ ' ' ~ weekly_args ~ ' >> /var/log/magento-maintenance.log 2>&1'
  },
  {
    'name': 'magento_' ~ site_token ~ '_monthly',
    'cron': '0 4 1 * *',
    'command': maintenance_cmd ~ ' ' ~ site_name ~ ' monthly ' ~ maintenance_extra_args ~ ' ' ~ monthly_args ~ ' >> /var/log/magento-maintenance.log 2>&1'
  },
  {
    'name': 'magento_' ~ site_token ~ '_health',
    'cron': '0 * * * *',
    'command': maintenance_cmd ~ ' ' ~ site_name ~ ' health ' ~ maintenance_extra_args ~ ' ' ~ health_args ~ ' >> /var/log/magento-health.log 2>&1'
  }
] %}

/usr/local/bin/magento-maintenance-salt:
  file.absent

/var/log/magento-cron.log:
  file.managed:
    - user: root
    - group: root
    - mode: 644
    - contents: ''

/var/log/magento-maintenance.log:
  file.managed:
    - user: root
    - group: root
    - mode: 644
    - contents: ''

/var/log/magento-health.log:
  file.managed:
    - user: root
    - group: root
    - mode: 644
    - contents: ''

{{ legacy_cron_file }}:
  file.absent

{{ cron_file }}:
  file.absent

{% if salt_minion_service %}

{% for job in base_jobs %}
magento_schedule_{{ job.name }}:
  schedule.present:
    - name: {{ job.name }}
    - function: cmd.run
    - job_args:
      - "{{ job.command }}"
    - job_kwargs:
        shell: /bin/bash
    - cron: '{{ job.cron }}'
    - run_on_start: False
    - persistent: True
    - maxrunning: 1
    - offline: True
{% endfor %}

{% for dump_job in mysql_dump_jobs %}
{% set dump_cmd = "saltgoat magetools xtrabackup mysql dump" %}
{% if dump_job.get('database') %}
  {% set dump_cmd = dump_cmd ~ " --database " ~ shquote(dump_job.database) %}
{% endif %}
{% if dump_job.get('backup_dir') %}
  {% set dump_cmd = dump_cmd ~ " --backup-dir " ~ shquote(dump_job.backup_dir) %}
{% endif %}
{% if dump_job.get('repo_owner') %}
  {% set dump_cmd = dump_cmd ~ " --repo-owner " ~ shquote(dump_job.repo_owner) %}
{% endif %}
{% if dump_job.get('no_compress', False) %}
  {% set dump_cmd = dump_cmd ~ " --no-compress" %}
{% endif %}

magento_schedule_mysql_dump_{{ dump_job.name }}:
  schedule.present:
    - name: {{ dump_job.name }}
    - function: cmd.run
    - job_args:
      - "{{ dump_cmd }}"
    - job_kwargs:
        shell: /bin/bash
    - cron: '{{ dump_job.cron }}'
    - run_on_start: False
    - persistent: True
    - maxrunning: 1
    - offline: True
{% endfor %}

{% for watcher in api_watchers %}
{% set watcher_kinds = watcher.get('kinds', ['orders', 'customers']) %}
magento_schedule_api_watch_{{ watcher.name }}:
  schedule.present:
    - name: {{ watcher.name }}
    - function: cmd.run
    - job_args:
      - saltgoat magetools api watch --site {{ site_name }}{% if watcher_kinds %} --kinds {{ watcher_kinds|join(',') }}{% endif %}
    - job_kwargs:
        shell: /bin/bash
    - cron: '{{ watcher.cron }}'
    - run_on_start: False
    - persistent: True
    - maxrunning: 1
    - offline: True
{% endfor %}

{% for stats_job in stats_jobs %}
magento_schedule_stats_{{ stats_job.name }}:
  schedule.present:
    - name: {{ stats_job.name }}
    - function: cmd.run
    - job_args:
      - {{ build_stats_cmd(stats_job).strip() }}
    - job_kwargs:
        shell: /bin/bash
    - cron: '{{ stats_job.cron }}'
    - run_on_start: False
    - persistent: True
    - maxrunning: 1
    - offline: True
{% endfor %}

{% for restic_job in restic_jobs %}
{# 如果 Restic 目标是本地路径，先确保目录和属主正确，以免首次备份用 root 创建导致后续权限错乱 #}
{% if restic_job.get('repo','').startswith('/') %}
magento_schedule_restic_repo_{{ restic_job.name }}:
  file.directory:
    - name: {{ restic_job.repo }}
    - user: {{ restic_job.get('repo_owner', magento_schedule_cfg.get('repo_owner', 'root')) }}
    - group: {{ restic_job.get('repo_owner', magento_schedule_cfg.get('repo_owner', 'root')) }}
    - mode: 750
    - makedirs: True
{% endif %}
magento_schedule_restic_{{ restic_job.name }}:
  schedule.present:
    - name: {{ restic_job.name }}
    - function: cmd.run
    - job_args:
      - {{ build_restic_cmd(restic_job).strip() }}
    - job_kwargs:
        shell: /bin/bash
    - cron: '{{ restic_job.cron }}'
    - run_on_start: False
    - persistent: True
    - maxrunning: 1
    - offline: True
{% endfor %}

{% if salt['service.available']('salt-minion') %}
salt-minion-schedule-service:
  service.running:
    - name: salt-minion
    - enable: True
    - watch:
{% for job in base_jobs %}
      - schedule: magento_schedule_{{ job.name }}
{% endfor %}
{% for dump_job in mysql_dump_jobs %}
      - schedule: magento_schedule_mysql_dump_{{ dump_job.name }}
{% endfor %}
{% for watcher in api_watchers %}
      - schedule: magento_schedule_api_watch_{{ watcher.name }}
{% endfor %}
{% for stats_job in stats_jobs %}
      - schedule: magento_schedule_stats_{{ stats_job.name }}
{% endfor %}
{% for restic_job in restic_jobs %}
      - schedule: magento_schedule_restic_{{ restic_job.name }}
{% endfor %}
      - schedule: saltgoat_schedule_auto_job
      - schedule: saltgoat_daily_summary_job
{% endif %}

saltgoat_schedule_auto_job:
  schedule.present:
    - name: saltgoat_schedule_auto
    - function: cmd.run
    - job_args:
      - saltgoat magetools schedule auto
    - job_kwargs:
        shell: /bin/bash
    - cron: '30 3 * * *'
    - run_on_start: False
    - persistent: True
    - maxrunning: 1
    - offline: True

saltgoat_daily_summary_job:
  schedule.present:
    - name: saltgoat_daily_summary
    - function: cmd.run
    - job_args:
      - saltgoat monitor report daily
    - job_kwargs:
        shell: /bin/bash
    - cron: '0 6 * * *'
    - run_on_start: False
    - persistent: True
    - maxrunning: 1
    - offline: True

{% else %}

salt_minion_required:
  test.fail_without_changes:
    - comment: "salt-minion service is required for optional.magento-schedule (Salt Schedule only)."

{% endif %}

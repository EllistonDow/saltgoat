# SaltGoat Magento 2 定时维护任务（Salt Schedule 优先，自动回退 Cron）
# salt/states/optional/magento-schedule.sls

{% set site_name = pillar.get('site_name', 'tank') %}
{% set site_token = site_name | replace(' ', '_') | replace('-', '_') | lower %}
{% set maintenance_cmd = pillar.get('magento_schedule', {}).get('maintenance_command', 'saltgoat magetools maintenance') %}
{% set maintenance_extra_args = pillar.get('magento_schedule', {}).get('maintenance_extra_args', '') %}
{% set daily_args = pillar.get('magento_schedule', {}).get('daily_args', '') %}
{% set weekly_args = pillar.get('magento_schedule', {}).get('weekly_args', '') %}
{% set monthly_args = pillar.get('magento_schedule', {}).get('monthly_args', '') %}
{% set health_args = pillar.get('magento_schedule', {}).get('health_args', '') %}
{% set all_dump_jobs = pillar.get('magento_schedule', {}).get('mysql_dump_jobs', []) %}
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
{% macro shquote(val) -%}'{{ val | replace("'", "'\\''") }}'{%- endmacro %}
{% macro build_dump_cmd(job) -%}
saltgoat magetools xtrabackup mysql dump{% if job.get('database') %} --database {{ shquote(job.database) }}{% endif %}{% if job.get('backup_dir') %} --backup-dir {{ shquote(job.backup_dir) }}{% endif %}{% if job.get('repo_owner') %} --repo-owner {{ shquote(job.repo_owner) }}{% endif %}{% if job.get('no_compress', False) %} --no-compress{% endif %}
{%- endmacro %}
{% set salt_minion_service = salt['file.file_exists']('/lib/systemd/system/salt-minion.service') or salt['file.file_exists']('/etc/systemd/system/salt-minion.service') %}
{% set cron_file = '/etc/cron.d/magento-maintenance-' ~ site_token %}
{% set legacy_cron_file = '/etc/cron.d/magento-maintenance' %}
{% set base_jobs = [
  {
    'name': 'magento_' ~ site_token ~ '_cron',
    'cron': '* * * * *',
    'command': "cd /var/www/{{ site_name }} && sudo -u www-data php bin/magento cron:run >> /var/log/magento-cron.log 2>&1"
  },
  {
    'name': 'magento_' ~ site_token ~ '_daily',
    'cron': '0 2 * * *',
    'command': "{{ maintenance_cmd }} {{ site_name }} daily {{ maintenance_extra_args }} {{ daily_args }} >> /var/log/magento-maintenance.log 2>&1"
  },
  {
    'name': 'magento_' ~ site_token ~ '_weekly',
    'cron': '0 3 * * 0',
    'command': "{{ maintenance_cmd }} {{ site_name }} weekly {{ maintenance_extra_args }} {{ weekly_args }} >> /var/log/magento-maintenance.log 2>&1"
  },
  {
    'name': 'magento_' ~ site_token ~ '_monthly',
    'cron': '0 4 1 * *',
    'command': "{{ maintenance_cmd }} {{ site_name }} monthly {{ maintenance_extra_args }} {{ monthly_args }} >> /var/log/magento-maintenance.log 2>&1"
  },
  {
    'name': 'magento_' ~ site_token ~ '_health',
    'cron': '0 * * * *',
    'command': "{{ maintenance_cmd }} {{ site_name }} health {{ maintenance_extra_args }} {{ health_args }} >> /var/log/magento-health.log 2>&1"
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

{% if salt_minion_service %}

{{ legacy_cron_file }}:
  file.absent

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
{% endif %}

{% else %}

{{ legacy_cron_file }}:
  file.absent

{{ cron_file }}:
  file.managed:
    - user: root
    - group: root
    - mode: 644
    - contents: |
        # Magento 2 定时维护任务（Salt Schedule 不可用，回退系统 Cron）
{% for job in base_jobs %}
        {{ job.cron }} root {{ job.command }}
{% endfor %}
{% for dump_job in mysql_dump_jobs %}
        {{ dump_job.cron }} root {{ build_dump_cmd(dump_job).strip() }}
{% endfor %}

cron-service-magento:
  service.running:
    - name: cron
    - enable: True

{% endif %}

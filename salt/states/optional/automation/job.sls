{#-
  Manage a SaltGoat automation job (Salt Schedule only).
-#}

include:
  - optional.automation.init

{% set default_cfg = salt['pillar.get']('saltgoat:automation', {}) %}
{% set automation = pillar.get('automation', {}) %}
{% set base_dir = automation.get('base_dir', default_cfg.get('base_dir', '/srv/saltgoat/automation')) %}
{% set jobs_dir = automation.get('jobs_dir', default_cfg.get('jobs_dir', base_dir + '/jobs')) %}
{% set logs_dir = automation.get('logs_dir', default_cfg.get('logs_dir', base_dir + '/logs')) %}
{% set owner = automation.get('owner', default_cfg.get('owner', 'root')) %}
{% set group = automation.get('group', default_cfg.get('group', owner)) %}
{% set job_cfg = automation.get('job', {}) %}
{% set salt_minion_service = salt['file.file_exists']('/lib/systemd/system/salt-minion.service') or salt['file.file_exists']('/etc/systemd/system/salt-minion.service') %}

{% if not salt_minion_service %}
saltgoat-automation-job-salt-minion-required:
  test.fail_without_changes:
    - comment: 'automation.job requires salt-minion to manage Salt Schedule entries'
{% elif not job_cfg %}
saltgoat-automation-job-missing:
  test.fail_without_changes:
    - comment: 'automation.job state requires automation:job pillar data'
{% else %}
{% set job_data = job_cfg.get('data', {}) %}
{% set job_name = job_cfg.get('name', job_data.get('name', 'automation-job')) %}
{% set job_file = job_cfg.get('file', jobs_dir + '/' + job_name + '.json') %}
{% set ensure = job_cfg.get('ensure', 'present') %}
{% set cron_expr = job_cfg.get('cron', job_data.get('cron', '0 * * * *')) %}
{% set enabled = job_cfg.get('enabled', job_data.get('enabled', False)) %}
{% set splay = job_cfg.get('splay', job_data.get('splay', 0)) %}
{% set cron_file = '/etc/cron.d/saltgoat-automation-' + job_name %}

{% if ensure == 'absent' %}
{{ job_file }}:
  file.absent

saltgoat-automation-job-schedule-absent-{{ job_name }}:
  schedule.absent:
    - name: {{ job_name }}

{{ cron_file }}:
  file.absent

{% else %}
{{ job_file }}:
  file.serialize:
    - formatter: json
    - dataset_pillar: automation:job:data
    - user: {{ owner }}
    - group: {{ group }}
    - mode: {{ default_cfg.get('job_file_mode', '640') }}
    - makedirs: True
    - require:
      - file: {{ jobs_dir }}

{% if enabled %}
saltgoat-automation-job-schedule-{{ job_name }}:
  schedule.present:
    - name: {{ job_name }}
    - function: saltgoat.automation_job_run
    - kwargs:
        name: {{ job_name }}
    - cron: '{{ cron_expr }}'
    - run_on_start: False
    - maxrunning: 1
    - splay: {{ splay }}
    - return_job: False
    - persist: True
    - require:
      - file: {{ job_file }}

{{ cron_file }}:
  file.absent:
    - require:
      - schedule: saltgoat-automation-job-schedule-{{ job_name }}

{% else %}
saltgoat-automation-job-schedule-disabled-{{ job_name }}:
  schedule.absent:
    - name: {{ job_name }}
    - require:
      - file: {{ job_file }}

{{ cron_file }}:
  file.absent
{% endif %}

{% endif %}
{% endif %}

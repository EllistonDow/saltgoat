# Manage Dropbox daemon via systemd and optional Salt beacons

{% set cfg = pillar.get('dropbox', {}) or {} %}
{% set enabled = cfg.get('enabled', False) %}

{% if not enabled %}
dropbox_disabled:
  test.succeed_without_changes:
    - comment: "Dropbox service disabled via pillar dropbox.enabled"
{% else %}
{% set unit_name = cfg.get('unit_name', 'dropbox.service') %}
{% set manage_unit = cfg.get('manage_unit', True) %}
{% set unit_path = '/etc/systemd/system/' + unit_name %}
{% set description = cfg.get('description', 'Dropbox headless daemon') %}
{% set user = cfg.get('user', 'doge') %}
{% set group = cfg.get('group', user) %}
{% set workdir = cfg.get('working_dir', '/home/' + user) %}
{% set exec_start = cfg.get('exec', '/usr/bin/dropbox start -i') %}
{% set restart_policy = cfg.get('restart', 'always') %}
{% set restart_sec = cfg.get('restart_sec', '5s') %}
{% set environment = cfg.get('environment', {}) %}

{% if manage_unit %}
{{ unit_path }}:
  file.managed:
    - user: root
    - group: root
    - mode: 644
    - source: salt://optional/dropbox/dropbox.service.jinja
    - template: jinja
    - context:
        description: {{ description | tojson }}
        user: {{ user | tojson }}
        group: {{ group | tojson }}
        working_dir: {{ workdir | tojson }}
        exec_start: {{ exec_start | tojson }}
        restart: {{ restart_policy | tojson }}
        restart_sec: {{ restart_sec | tojson }}
        environment: {{ environment | tojson }}
{% else %}
dropbox_unit_managed_externally:
  test.succeed_without_changes:
    - comment: "Pillar dropbox.manage_unit = false, skipping custom unit deployment"
{% endif %}

{% if manage_unit %}
dropbox-daemon-reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: {{ unit_path }}
{% endif %}

dropbox-service:
  service.running:
    - name: {{ unit_name }}
    - enable: True
    - require:
{% if manage_unit %}
      - file: {{ unit_path }}
{% endif %}
{% endif %}

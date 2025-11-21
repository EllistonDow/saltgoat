{# Deploy notification queue drainer timer #}
{% set script_dir = '/opt/saltgoat-monitor' %}
{% set script_path = script_dir + '/notification-drain.py' %}
{% set service_unit = '/etc/systemd/system/saltgoat-notification-drain.service' %}
{% set timer_unit = '/etc/systemd/system/saltgoat-notification-drain.timer' %}
{% set repo_root = salt['pillar.get']('saltgoat:repo_root', '/opt/saltgoat') %}
{% set queue_dir = salt['pillar.get']('saltgoat:notifications:queue_dir', '/var/log/saltgoat/notify-queue') %}
{% set max_batch = salt['pillar.get']('saltgoat:notifications:drain_max', 100) %}
{% set alert_threshold = salt['pillar.get']('saltgoat:notifications:drain_alert_threshold', 500) %}
{% set alert_tag = salt['pillar.get']('saltgoat:notifications:drain_alert_tag', 'saltgoat/monitor/notification_queue') %}
{% set alert_site = salt['pillar.get']('saltgoat:notifications:drain_alert_site', '') %}
{% set drain_args = '--max ' ~ max_batch %}

{{ script_dir }}:
  file.directory:
    - user: root
    - group: root
    - mode: 0755

{{ script_path }}:
  file.managed:
    - source: salt://scripts/notification-drain.py
    - user: root
    - group: root
    - mode: 0755
    - require:
      - file: {{ script_dir }}

{{ service_unit }}:
  file.managed:
    - user: root
    - group: root
    - mode: 0644
    - contents: |
        [Unit]
        Description=SaltGoat notification queue drain
        After=network-online.target

        [Service]
        Type=oneshot
        User=root
        Group=root
        Environment=PYTHONUNBUFFERED=1
        Environment=SALTGOAT_REPO_ROOT={{ repo_root }}
        ExecStart=/usr/bin/python3 {{ script_path }} {{ drain_args }} --queue-dir "{{ queue_dir }}" --alert-threshold {{ alert_threshold }} --alert-tag "{{ alert_tag }}"{% if alert_site %} --alert-site "{{ alert_site }}"{% endif %}
        Nice=10
        IOSchedulingClass=best-effort
        IOSchedulingPriority=7
        NoNewPrivileges=yes
    - require:
      - file: {{ script_path }}

{{ timer_unit }}:
  file.managed:
    - user: root
    - group: root
    - mode: 0644
    - contents: |
        [Unit]
        Description=SaltGoat notification queue drain timer

        [Timer]
        OnBootSec=1min
        OnUnitActiveSec=2min
        RandomizedDelaySec=15
        Persistent=true

        [Install]
        WantedBy=timers.target
    - require:
      - file: {{ service_unit }}

notification_drain_daemon_reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: {{ service_unit }}
      - file: {{ timer_unit }}

saltgoat-notification-drain.timer:
  service.running:
    - enable: True
    - require:
      - cmd: notification_drain_daemon_reload
      - file: {{ timer_unit }}

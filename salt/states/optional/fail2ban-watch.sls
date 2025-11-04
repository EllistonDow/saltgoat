{# Manage SaltGoat Fail2ban watcher service and timer #}
{% set script_dir = '/opt/saltgoat-security' %}
{% set script_path = script_dir + '/fail2ban_watch.py' %}
{% set state_file = '/var/log/saltgoat/fail2ban-state.json' %}
{% set service_unit = '/etc/systemd/system/saltgoat-fail2ban-watch.service' %}
{% set timer_unit = '/etc/systemd/system/saltgoat-fail2ban-watch.timer' %}

{{ script_dir }}:
  file.directory:
    - user: root
    - group: root
    - mode: 0755

{{ script_dir }}/lib:
  file.directory:
    - user: root
    - group: root
    - mode: 0755
    - require:
      - file: {{ script_dir }}

{{ script_path }}:
  file.managed:
    - source: salt://templates/security/fail2ban_watch.py
    - user: root
    - group: root
    - mode: 0755
    - require:
      - file: {{ script_dir }}/lib

{{ script_dir }}/lib/notification.py:
  file.managed:
    - source: salt://templates/security/lib/notification.py
    - user: root
    - group: root
    - mode: 0644
    - require:
      - file: {{ script_dir }}/lib

{{ state_file }}:
  file.managed:
    - user: root
    - group: root
    - mode: 0640
    - makedirs: True
    - contents: ''
    - replace: False

{{ service_unit }}:
  file.managed:
    - user: root
    - group: root
    - mode: 0644
    - contents: |
        [Unit]
        Description=SaltGoat Fail2ban Watcher
        After=network-online.target fail2ban.service

        [Service]
        Type=oneshot
        User=root
        Group=root
        Environment=PYTHONUNBUFFERED=1
        ExecStart=/usr/bin/python3 {{ script_path }} --state {{ state_file }}
        Nice=5

        [Install]
        WantedBy=multi-user.target
    - require:
      - file: {{ script_path }}

{{ timer_unit }}:
  file.managed:
    - user: root
    - group: root
    - mode: 0644
    - contents: |
        [Unit]
        Description=SaltGoat Fail2ban Watcher Timer

        [Timer]
        OnBootSec=2min
        OnUnitActiveSec=5min
        RandomizedDelaySec=30
        Persistent=true

        [Install]
        WantedBy=timers.target
    - require:
      - file: {{ service_unit }}

fail2ban_watch_daemon_reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: {{ service_unit }}
      - file: {{ timer_unit }}

saltgoat-fail2ban-watch.timer:
  service.running:
    - enable: True
    - require:
      - cmd: fail2ban_watch_daemon_reload
      - file: {{ timer_unit }}

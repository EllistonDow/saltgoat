{# Manage Goat Pulse hourly snapshot timer #}
{% set install_dir = '/opt/saltgoat-monitoring' %}
{% set script_path = install_dir + '/goat_pulse.py' %}
{% set metrics_dir = '/var/lib/saltgoat' %}
{% set metrics_file = metrics_dir + '/goat-pulse.prom' %}
{% set service_unit = '/etc/systemd/system/saltgoat-goatpulse.service' %}
{% set timer_unit = '/etc/systemd/system/saltgoat-goatpulse.timer' %}

{{ install_dir }}:
  file.directory:
    - user: root
    - group: root
    - mode: 0755

{{ script_path }}:
  file.managed:
    - source: salt://scripts/goat_pulse.py
    - user: root
    - group: root
    - mode: 0755
    - require:
      - file: {{ install_dir }}

{{ metrics_dir }}:
  file.directory:
    - user: root
    - group: root
    - mode: 0755

{{ metrics_file }}:
  file.managed:
    - user: root
    - group: root
    - mode: 0644
    - replace: False
    - require:
      - file: {{ metrics_dir }}

{{ service_unit }}:
  file.managed:
    - user: root
    - group: root
    - mode: 0644
    - contents: |
        [Unit]
        Description=SaltGoat Goat Pulse Snapshot
        After=network-online.target
        Wants=network-online.target

        [Service]
        Type=oneshot
        User=root
        Group=root
        Environment=PYTHONUNBUFFERED=1
        WorkingDirectory={{ install_dir }}
        ExecStart=/usr/bin/python3 {{ script_path }} --once --plain --telegram --metrics-file {{ metrics_file }}
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
        Description=SaltGoat Goat Pulse Snapshot Timer

        [Timer]
        OnBootSec=5min
        OnCalendar=hourly
        RandomizedDelaySec=120
        Persistent=true

        [Install]
        WantedBy=timers.target
    - require:
      - file: {{ service_unit }}

goat_pulse_daemon_reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: {{ service_unit }}
      - file: {{ timer_unit }}

saltgoat-goatpulse.timer:
  service.running:
    - enable: True
    - require:
      - cmd: goat_pulse_daemon_reload
      - file: {{ timer_unit }}
      - file: {{ service_unit }}

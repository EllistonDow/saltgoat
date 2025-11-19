# Salt master tuning

{% set salt_master_cfg = pillar.get('saltgoat', {}).get('salt_master', {}) %}
{% set worker_threads = salt_master_cfg.get('worker_threads', 4) %}

/etc/salt/master.d:
  file.directory:
    - user: root
    - group: salt
    - mode: 750

/etc/salt/master.d/saltgoat.conf:
  file.managed:
    - user: root
    - group: salt
    - mode: 640
    - contents: |
        # Managed by SaltGoat
        worker_threads: {{ worker_threads }}
    - require:
      - file: /etc/salt/master.d

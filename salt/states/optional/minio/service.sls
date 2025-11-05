{% set minio = salt['pillar.get']('minio', {}) %}
{% if not minio.get('enabled', True) %}
minio-service-skip:
  test.succeed_without_changes:
    - name: minio disabled
{% else %}
{% set binary = minio.get('binary', '/usr/local/bin/minio') %}
{% set binary_source = minio.get('binary_source', 'https://dl.min.io/server/minio/release/linux-amd64/minio') %}
{% set binary_hash = minio.get('binary_hash', '') %}
{% set user = minio.get('user', 'minio') %}
{% set group = minio.get('group', user) %}
{% set config_dir = minio.get('config_dir', '/etc/minio') %}
{% set env_file = config_dir ~ '/minio.env' %}
{% set unit_file = '/etc/systemd/system/minio.service' %}

minio-binary:
  file.managed:
    - name: {{ binary }}
    - mode: 0755
    - source: {{ binary_source }}
    {% if binary_hash %}
    - source_hash: {{ binary_hash }}
    - skip_verify: False
    {% else %}
    - skip_verify: True
    {% endif %}

minio-service-unit:
  file.managed:
    - name: {{ unit_file }}
    - mode: 0644
    - contents: |
        [Unit]
        Description=MinIO
        Wants=network-online.target
        After=network-online.target

        [Service]
        User={{ user }}
        Group={{ group }}
        EnvironmentFile=-{{ env_file }}
        ExecStart={{ binary }} server $MINIO_VOLUMES
        LimitNOFILE=65536
        Restart=on-failure
        RestartSec=5s

        [Install]
        WantedBy=multi-user.target
    - require:
      - file: minio-config-dir

minio-service:
  service.running:
    - name: minio
    - enable: True
    - reload: True
    - require:
      - file: minio-service-unit
      - file: minio-env
      - file: minio-binary
    - watch:
      - file: minio-service-unit
      - file: minio-env
      - file: minio-binary
{% endif %}

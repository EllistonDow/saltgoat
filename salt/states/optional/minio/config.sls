{% set minio = salt['pillar.get']('minio', {}) %}
{% if not minio.get('enabled', True) %}
minio-config-skip:
  test.succeed_without_changes:
    - name: minio disabled
{% else %}
{% set config_dir = minio.get('config_dir', '/etc/minio') %}
{% set env_file = config_dir ~ '/minio.env' %}
{% set data_dir = minio.get('data_dir', '/var/lib/minio/data') %}
{% set listen = minio.get('listen_address', '0.0.0.0:9000') %}
{% set console = minio.get('console_address', '0.0.0.0:9001') %}
{% set tls = minio.get('tls', {}) %}
{% set cert = tls.get('cert', '/etc/minio/certs/public.crt') %}
{% set key = tls.get('key', '/etc/minio/certs/private.key') %}

minio-env:
  file.managed:
    - name: {{ env_file }}
    - mode: 0640
    - user: {{ minio.get('user', 'minio') }}
    - group: {{ minio.get('group', minio.get('user', 'minio')) }}
    - makedirs: True
    - contents: |
        MINIO_VOLUMES="{{ data_dir }}"
        MINIO_SERVER_ADDR="{{ listen }}"
        MINIO_CONSOLE_ADDRESS="{{ console }}"
        MINIO_ROOT_USER="{{ minio.get('root_credentials', {}).get('access_key', 'minioadmin') }}"
        MINIO_ROOT_PASSWORD="{{ minio.get('root_credentials', {}).get('secret_key', 'minioadmin') }}"
        {% if tls.get('enabled', False) %}
        MINIO_SERVER_URL="https://{{ listen }}"
        MINIO_CERT_FILE="{{ cert }}"
        MINIO_KEY_FILE="{{ key }}"
        {% endif %}
    - require:
      - file: minio-config-dir

{% if tls.get('enabled', False) %}
minio-cert-dir:
  file.directory:
    - name: {{ config_dir }}/certs
    - user: {{ minio.get('user', 'minio') }}
    - group: {{ minio.get('group', minio.get('user', 'minio')) }}
    - mode: 0750
    - makedirs: True
    - require:
      - file: minio-config-dir

{% if tls.get('cert_source') %}
minio-cert-file:
  file.managed:
    - name: {{ cert }}
    - source: {{ tls.get('cert_source') }}
    - user: {{ minio.get('user', 'minio') }}
    - group: {{ minio.get('group', minio.get('user', 'minio')) }}
    - mode: 0640
    - require:
      - file: minio-cert-dir
{% endif %}

{% if tls.get('key_source') %}
minio-key-file:
  file.managed:
    - name: {{ key }}
    - source: {{ tls.get('key_source') }}
    - user: {{ minio.get('user', 'minio') }}
    - group: {{ minio.get('group', minio.get('user', 'minio')) }}
    - mode: 0640
    - require:
      - file: minio-cert-dir
{% endif %}
{% endif %}
{% endif %}

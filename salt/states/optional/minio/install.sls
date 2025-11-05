{% set minio = salt['pillar.get']('minio', {}) %}
{% if not minio.get('enabled', True) %}
minio-install-skip:
  test.succeed_without_changes:
    - name: minio disabled
{% else %}
{% set user = minio.get('user', 'minio') %}
{% set group = minio.get('group', user) %}
{% set data_dir = minio.get('data_dir', '/var/lib/minio/data') %}
{% set config_dir = minio.get('config_dir', '/etc/minio') %}

minio-group:
  group.present:
    - name: {{ group }}

minio-user:
  user.present:
    - name: {{ user }}
    - gid: {{ group }}
    - home: {{ config_dir }}
    - shell: /usr/sbin/nologin
    - require:
      - group: minio-group

minio-data-dir:
  file.directory:
    - name: {{ data_dir }}
    - user: {{ user }}
    - group: {{ group }}
    - mode: 0750
    - makedirs: True
    - require:
      - user: minio-user

minio-config-dir:
  file.directory:
    - name: {{ config_dir }}
    - user: {{ user }}
    - group: {{ group }}
    - mode: 0750
    - makedirs: True
    - require:
      - user: minio-user
{% endif %}

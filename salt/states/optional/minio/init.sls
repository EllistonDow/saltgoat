{% if salt['pillar.get']('minio:enabled', True) %}
include:
  - optional.minio.install
  - optional.minio.config
  - optional.minio.service
{% else %}
minio-skipped:
  test.succeed_without_changes:
    - name: minio pillar disabled
{% endif %}

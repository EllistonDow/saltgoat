{% if salt['pillar.get']('minio:enabled', True) %}
include:
  - optional.minio.deploy
{% else %}
minio-skipped:
  test.succeed_without_changes:
    - name: minio pillar disabled
{% endif %}

{% set secret_includes = [] %}
{% if salt['cp.file_exists']('salt://secret/auto.sls') %}
{%   set secret_includes = secret_includes + ['secret.auto'] %}
{% endif %}
{% if salt['cp.file_exists']('salt://secret/local.sls') %}
{%   set secret_includes = secret_includes + ['secret.local'] %}
{% endif %}

base:
  '*':
{% for secret in secret_includes %}
    - {{ secret }}
{% endfor %}
    - saltgoat
    - nginx
    - magento-optimize
    - salt-beacons
    - backup-restic
    - mysql-backup

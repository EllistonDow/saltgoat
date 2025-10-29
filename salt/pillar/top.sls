{% set secret_includes = [] %}
{% set pillar_roots = opts.get('pillar_roots', {}) %}
{% set base_roots = pillar_roots.get('base', []) %}
{% for root in base_roots %}
{%   set auto_path = root ~ '/secret/auto.sls' %}
{%   if salt['file.file_exists'](auto_path) %}
{%     set secret_includes = secret_includes + ['secret.auto'] %}
{%     break %}
{%   endif %}
{% endfor %}
{% for root in base_roots %}
{%   set local_path = root ~ '/secret/local.sls' %}
{%   if salt['file.file_exists'](local_path) %}
{%     set secret_includes = secret_includes + ['secret.local'] %}
{%     break %}
{%   endif %}
{% endfor %}

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

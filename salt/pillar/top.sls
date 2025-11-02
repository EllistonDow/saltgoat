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
{% set extra_secret_files = ['magento_api', 'restic', 'smtp', 'telegram'] %}
{% for name in extra_secret_files %}
{%   for root in base_roots %}
{%     set extra_path = root ~ '/secret/' ~ name ~ '.sls' %}
{%     if salt['file.file_exists'](extra_path) %}
{%       set secret_includes = secret_includes + ['secret.' ~ name] %}
{%       break %}
{%     endif %}
{%   endfor %}
{% endfor %}

base:
  '*':
{% for secret in secret_includes %}
    - {{ secret }}
{% endfor %}
{% for name in ['auto', 'magento_api', 'restic', 'smtp', 'telegram'] %}
{%   if ('secret.' ~ name) not in secret_includes %}
{%     for root in base_roots %}
{%       if salt['file.file_exists'](root ~ '/secret/' ~ name ~ '.sls') %}
    - secret.{{ name }}
{%         break %}
{%       endif %}
{%     endfor %}
{%   endif %}
{% endfor %}
    - saltgoat
    - nginx
    - magento-optimize
    - magento-schedule
    - salt-beacons
    - backup-restic
    - mysql-backup
    - notifications
    - telegram-topics

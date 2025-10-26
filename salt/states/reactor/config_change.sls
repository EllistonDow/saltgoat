{# Configuration change reactor #}
{% set log_path = salt['pillar.get']('saltgoat:reactor:resource_alerts:log_path', '/var/log/saltgoat/alerts.log') %}
{% set config_watch = salt['pillar.get']('saltgoat:reactor:config_watch', {}) %}
{% set auto_permissions = config_watch.get('auto_permissions', False) %}
{% set site_path = config_watch.get('site_path', '/var/www/tank') %}

config_change_log_{{ data.get('_stamp', '')|replace(':', '_')|replace('.', '_') }}:
  local.cmd.run:
    - tgt: {{ data['id'] }}
    - arg:
      - "echo \"$(date '+%F %T') [CONFIG] tag={{ tag }} payload={{ data|json }}\" >> {{ log_path }}"

{% if auto_permissions %}
config_change_permissions_fix:
  local.cmd.run:
    - tgt: {{ data['id'] }}
    - arg:
      - "saltgoat magetools permissions fix {{ site_path }}"
    - require:
      - local: config_change_log_{{ data.get('_stamp', '')|replace(':', '_')|replace('.', '_') }}
{% endif %}

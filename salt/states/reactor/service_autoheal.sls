{# Service auto-healing reactor #}
{% set allowed_services = salt['pillar.get']('saltgoat:reactor:autorestart_services:services', []) %}
{% set log_path = salt['pillar.get']('saltgoat:reactor:resource_alerts:log_path', '/var/log/saltgoat/alerts.log') %}

{%- for service_name, service_data in data.get('services', {}).items() %}
  {%- set status = service_data.get('status', True) %}
  {%- if service_name in allowed_services and not status %}
service_autorestart_{{ service_name }}_{{ loop.index }}:
  local.service.restart:
    - tgt: {{ data['id'] }}
    - arg:
      - {{ service_name }}

service_autorestart_log_{{ service_name }}_{{ loop.index }}:
  local.cmd.run:
    - tgt: {{ data['id'] }}
    - arg:
      - "echo \"$(date '+%F %T') [SERVICE] Auto-restarted {{ service_name }} after beacon alert\" >> {{ log_path }}"
    - require:
      - local: service_autorestart_{{ service_name }}_{{ loop.index }}
  {%- endif %}
{%- endfor %}

{# Service auto-healing reactor #}
{% set default_services = ['nginx', 'mysql', 'php8.3-fpm', 'valkey', 'rabbitmq', 'opensearch'] %}
{% set allowed_services = salt['pillar.get']('saltgoat:reactor:autorestart_services:services', default_services) or default_services %}
{% set log_path = salt['pillar.get']('saltgoat:reactor:resource_alerts:log_path', '/var/log/saltgoat/alerts.log') %}
{% set tag_parts = tag.split('/') %}
{% set event_minion = data.get('id') or data.get('minion_id') or (tag_parts[2] if tag_parts|length > 2 else '') or data.get('host') or 'minion' %}

{% set payload = data.get('data') if data.get('data') is mapping else data %}
{% set ns = namespace(service_name=payload.get('service_name') or payload.get('name') or (tag_parts[4] if tag_parts|length > 4 else None), service_info={}, running=True) %}
{% if ns.service_name %}
  {% if payload.get(ns.service_name) is mapping %}
    {% set ns.service_info = payload.get(ns.service_name) %}
  {% elif payload.get('services') is mapping and payload['services'].get(ns.service_name) is mapping %}
    {% set ns.service_info = payload['services'].get(ns.service_name) %}
  {% endif %}
  {% set running_value = ns.service_info.get('status', ns.service_info.get('running', True)) %}
  {% if running_value in [False, 0, '0'] %}
    {% set ns.running = False %}
  {% elif running_value in [True, 1, '1'] %}
    {% set ns.running = True %}
  {% elif running_value is string %}
    {% if running_value.lower() in ['false', 'down', 'stopped', 'dead', 'failed', 'inactive'] %}
      {% set ns.running = False %}
    {% else %}
      {% set ns.running = True %}
    {% endif %}
  {% else %}
    {% set ns.running = running_value %}
  {% endif %}
  {% if not ns.running %}
    {% set event_b64 = salt['hashutil.base64_b64encode'](data|json) %}
    {% set allowed_b64 = salt['hashutil.base64_b64encode'](allowed_services|json) %}
service_autoheal_handler_{{ ns.service_name | replace('-', '_') }}:
  local.cmd.run:
    - tgt: {{ event_minion }}
    - arg:
      - |-
        python3 /opt/saltgoat-reactor/service_autoheal.py \
          --tag '{{ tag }}' \
          --service '{{ ns.service_name }}' \
          --event-b64 '{{ event_b64 }}' \
          --allowed-b64 '{{ allowed_b64 }}' \
          --log-path '{{ log_path }}' \
          --minion '{{ event_minion }}'
    - python_shell: True
  {% endif %}
{% endif %}

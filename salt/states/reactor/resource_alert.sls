{# Resource threshold reactor #}
{% set log_path = salt['pillar.get']('saltgoat:reactor:resource_alerts:log_path', '/var/log/saltgoat/alerts.log') %}

resource_alert_log_{{ data.get('_stamp', '')|replace(':', '_')|replace('.', '_') }}:
  local.cmd.run:
    - tgt: {{ data['id'] }}
    - arg:
      - "echo \"$(date '+%F %T') [RESOURCE] tag={{ tag }} payload={{ data|json }}\" >> {{ log_path }}"

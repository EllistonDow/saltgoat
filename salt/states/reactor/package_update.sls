{# Package update reactor #}
{% set log_path = salt['pillar.get']('saltgoat:reactor:pkg_updates:log_path', '/var/log/saltgoat/alerts.log') %}
{% set auto_refresh = salt['pillar.get']('saltgoat:reactor:pkg_updates:auto_refresh', False) %}

pkg_update_log_{{ data.get('_stamp', '')|replace(':', '_')|replace('.', '_') }}:
  local.cmd.run:
    - tgt: {{ data['id'] }}
    - arg:
      - "echo \"$(date '+%F %T') [PKG] tag={{ tag }} payload={{ data|json }}\" >> {{ log_path }}"

{% if auto_refresh %}
pkg_update_refresh_db:
  local.cmd.run:
    - tgt: {{ data['id'] }}
    - arg:
      - "salt-call --local pkg.refresh_db >/dev/null 2>&1"
    - require:
      - local: pkg_update_log_{{ data.get('_stamp', '')|replace(':', '_')|replace('.', '_') }}
{% endif %}

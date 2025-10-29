{# Package update reactor #}
{% set log_path = salt['pillar.get']('saltgoat:reactor:pkg_updates:log_path', '/var/log/saltgoat/alerts.log') %}
{% set auto_refresh = salt['pillar.get']('saltgoat:reactor:pkg_updates:auto_refresh', False) %}
{% set tag_parts = tag.split('/') %}
{% set event_minion = data.get('id') or data.get('minion_id') or (tag_parts[2] if tag_parts|length > 2 else '') or data.get('host') or 'minion' %}
pkg_update_log_{{ data.get('_stamp', '')|replace(':', '_')|replace('.', '_') }}:
  local.cmd.run:
    - tgt: {{ event_minion }}
    - arg:
      - "python3 /opt/saltgoat-reactor/logger.py PKG \"{{ log_path }}\" \"{{ tag }}\" '{{ data|json }}'"
    - python_shell: True

{% if auto_refresh %}
pkg_update_refresh_db:
  local.cmd.run:
    - tgt: {{ event_minion }}
    - arg:
      - "salt-call --local pkg.refresh_db >/dev/null 2>&1"
    - require:
      - local: pkg_update_log_{{ data.get('_stamp', '')|replace(':', '_')|replace('.', '_') }}
{% endif %}

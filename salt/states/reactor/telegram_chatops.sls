{# Telegram ChatOps reactor #}
{% if salt['pillar.get']('saltgoat:chatops:enabled', True) %}
{% set tag_parts = tag.split('/') %}
{% set event_minion = data.get('id') or data.get('minion_id') or (tag_parts[2] if tag_parts|length > 2 else '') or data.get('host') or 'minion' %}
{% set event_b64 = salt['hashutil.base64_b64encode'](data|json) %}

chatops_dispatch_{{ data.get('_stamp', '')|replace(':', '_')|replace('.', '_') }}:
  local.cmd.run:
    - tgt: {{ event_minion }}
    - arg:
      - |-
        python3 /opt/saltgoat-reactor/telegram_chatops.py \
          --config '/etc/saltgoat/chatops.json' \
          --event-b64 '{{ event_b64 }}'
    - python_shell: True
{% endif %}

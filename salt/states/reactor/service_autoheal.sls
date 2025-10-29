{# Service auto-healing reactor #}
{% set default_services = ['nginx', 'mysql', 'php8.3-fpm', 'valkey', 'rabbitmq', 'opensearch'] %}
{% set allowed_services = salt['pillar.get']('saltgoat:reactor:autorestart_services:services', default_services) or default_services %}
{% set log_path = salt['pillar.get']('saltgoat:reactor:resource_alerts:log_path', '/var/log/saltgoat/alerts.log') %}
{% set telegram_cfg_path = '/etc/saltgoat/telegram.json' %}
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
  {% if ns.service_name in allowed_services and not ns.running %}
service_autorestart_{{ ns.service_name }}:
  local.service.restart:
    - tgt: {{ event_minion }}
    - arg:
      - {{ ns.service_name }}

service_autorestart_log_{{ ns.service_name }}:
  local.cmd.run:
    - tgt: {{ event_minion }}
    - arg:
      - |-
        python3 /opt/saltgoat-reactor/logger.py SERVICE "{{ log_path }}" "{{ tag }} service={{ ns.service_name }} action=autorestart" '{{ data|json }}'
    - python_shell: True
    - require:
      - local: service_autorestart_{{ ns.service_name }}

service_autorestart_telegram_{{ ns.service_name }}:
  local.cmd.run:
    - tgt: {{ event_minion }}
    - arg:
      - |-
        python3 - <<'PY'
        import json
        import subprocess
        import sys

        sys.path.insert(0, "/opt/saltgoat-reactor")
        import reactor_common  # pylint: disable=import-error

        payload = {{ data|json }}
        inner = payload.get("data") if isinstance(payload, dict) else None
        if isinstance(inner, dict):
            payload = {**inner, **{k: v for k, v in payload.items() if k != "data"}}
        host = payload.get('id') or payload.get('host') or payload.get('minion_id') or "{{ event_minion }}"
        service = "{{ ns.service_name }}"
        service_info = payload.get(service, {}) or payload.get("services", {}).get(service, {})
        previous_state = service_info.get('previous', service_info.get('status'))
        running_state = service_info.get('running', service_info.get('status'))
        if isinstance(running_state, str):
            running_bool = running_state.lower() not in {'false', 'down', 'stopped', '0'}
        else:
            running_bool = bool(running_state)
        if previous_state is None:
            previous_state = 'running' if running_bool else 'down'
        extra = json.dumps(service_info, ensure_ascii=False)

        LOG_PATH = "{{ log_path }}"
        TAG = "{{ tag }}"

        def log(kind, payload_obj):
            try:
                subprocess.run(
                    [
                        "python3",
                        "/opt/saltgoat-reactor/logger.py",
                        "TELEGRAM",
                        LOG_PATH,
                        f"{TAG} {kind}",
                        json.dumps(payload_obj, ensure_ascii=False),
                    ],
                    check=False,
                    timeout=5,
                )
            except Exception:
                pass

        profiles = reactor_common.load_telegram_profiles("{{ telegram_cfg_path }}", log)
        if not profiles:
            log("skip", {"reason": "no_profiles"})
            raise SystemExit()

        lines = [
            "[SaltGoat] WARNING service auto-heal",
            f"Host: {host}",
            f"Service: {service}",
            f"Previous state: {previous_state}",
            "Action: restart issued automatically",
        ]
        if extra and extra not in ('{}', 'null'):
            lines.append(f"Details: {extra}")
        message = "\n".join(lines)

        reactor_common.broadcast_telegram(message, profiles, log)
        PY
    - python_shell: True
    - require:
      - local: service_autorestart_log_{{ ns.service_name }}
  {% endif %}
{% endif %}

{# Configuration change reactor #}
{% set log_path = salt['pillar.get']('saltgoat:reactor:resource_alerts:log_path', '/var/log/saltgoat/alerts.log') %}
{% set config_watch = salt['pillar.get']('saltgoat:reactor:config_watch', {}) %}
{% set auto_permissions = config_watch.get('auto_permissions', False) %}
{% set site_path = config_watch.get('site_path', '/var/www/tank') %}
{% set telegram_cfg_path = '/etc/saltgoat/telegram.json' %}
{% set tag_parts = tag.split('/') %}
{% set event_minion = data.get('id') or data.get('minion_id') or (tag_parts[2] if tag_parts|length > 2 else '') or data.get('host') or 'minion' %}

config_change_log_{{ data.get('_stamp', '')|replace(':', '_')|replace('.', '_') }}:
  local.cmd.run:
    - tgt: {{ event_minion }}
    - arg:
      - |-
        python3 /opt/saltgoat-reactor/logger.py CONFIG "{{ log_path }}" "{{ tag }}" '{{ data|json }}'
    - python_shell: True

config_change_telegram_{{ data.get('_stamp', '')|replace(':', '_')|replace('.', '_') }}:
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
        host = payload.get("id") or payload.get("host") or payload.get("minion_id") or "{{ event_minion }}"
        tag = "{{ tag }}"
        change = payload.get("change") or payload.get("watchdog", {}).get("change") or "modified"
        path = payload.get("path") or payload.get("watchdog", {}).get("path") or payload.get("mount") or "n/a"
        target = payload.get("watchdog", {}).get("filename") or payload.get("filepath") or payload.get("name") or ""
        details = json.dumps(payload, ensure_ascii=False)

        LOG_PATH = "{{ log_path }}"
        TAG = tag

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
            "[SaltGoat] CONFIG change detected",
            f"Host: {host}",
            f"Tag: {tag}",
            f"Change: {change}",
            f"Path: {path}",
        ]
        if target:
            lines.append(f"Target: {target}")
        lines.append("Details:")
        lines.append(details)
        message = "\n".join(lines)

        reactor_common.broadcast_telegram(message, profiles, log, tag=TAG)
        PY
    - python_shell: True
    - require:
      - local: config_change_log_{{ data.get('_stamp', '')|replace(':', '_')|replace('.', '_') }}

{% if auto_permissions %}
config_change_permissions_fix:
  local.cmd.run:
    - tgt: {{ event_minion }}
    - arg:
      - "saltgoat magetools permissions fix {{ site_path }}"
    - require:
      - local: config_change_log_{{ data.get('_stamp', '')|replace(':', '_')|replace('.', '_') }}
{% endif %}

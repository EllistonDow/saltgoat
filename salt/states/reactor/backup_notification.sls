{# Backup event reactor #}
{% set log_path = salt['pillar.get']('saltgoat:reactor:backups:log_path', '/var/log/saltgoat/alerts.log') %}
{% set telegram_cfg_path = '/etc/saltgoat/telegram.json' %}
{% set parts = tag.split('/') %}
{% set backup_kind = parts[2] if parts|length > 2 else 'unknown' %}
{% set backup_status = parts[3] if parts|length > 3 else data.get('status', 'unknown') %}
{% set event_minion = data.get('id') or data.get('minion_id') or data.get('host') or (parts[1] if parts|length > 1 else '') or 'minion' %}

backup_event_log_{{ data.get('_stamp', '')|replace(':', '_')|replace('.', '_') }}:
  local.cmd.run:
    - tgt: {{ event_minion }}
    - arg:
      - |-
        python3 /opt/saltgoat-reactor/logger.py BACKUP "{{ log_path }}" "{{ tag }} kind={{ backup_kind }} status={{ backup_status }}" '{{ data|json }}'
    - python_shell: True

backup_event_telegram_{{ data.get('_stamp', '')|replace(':', '_')|replace('.', '_') }}:
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
        kind = "{{ backup_kind }}"
        status = "{{ backup_status }}"
        host = payload.get("host") or payload.get("id") or payload.get("minion_id") or "{{ event_minion }}"
        repo = payload.get("repo") or payload.get("file") or payload.get("path") or "n/a"
        log_file = payload.get("log_file") or payload.get("file") or "n/a"
        rc = payload.get("return_code", payload.get("retcode", 0))

        summary = []
        if payload.get("site"):
            summary.append(f"Site: {payload['site']}")
        if payload.get("project"):
            summary.append(f"Project: {payload['project']}")
        if payload.get("paths"):
            summary.append(f"Paths: {payload['paths']}")
        if payload.get("file") and payload.get("size"):
            summary.append(f"Archive: {payload['file']} ({payload['size']})")
        elif payload.get("file"):
            summary.append(f"Archive: {payload['file']}")
        if payload.get("timestamp"):
            summary.append(f"Timestamp: {payload['timestamp']}")
        if payload.get("reason"):
            summary.append(f"Reason: {payload['reason']}")
        summary.append(f"Return code: {rc}")

        severity = "SUCCESS" if status == "success" else "FAILURE"
        lines = [
            f"[SaltGoat] {severity} backup {kind}",
            f"Host: {host}",
            f"Repository/File: {repo}",
        ]
        if log_file:
            lines.append(f"Log: {log_file}")
        lines.extend(summary)
        message = "\n".join(lines)

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

        reactor_common.broadcast_telegram(message, profiles, log)
        PY
    - python_shell: True
    - require:
      - local: backup_event_log_{{ data.get('_stamp', '')|replace(':', '_')|replace('.', '_') }}

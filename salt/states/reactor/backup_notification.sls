{# Backup event reactor #}
{% set log_path = salt['pillar.get']('saltgoat:reactor:backups:log_path', '/var/log/saltgoat/alerts.log') %}
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
        import os
        import subprocess
        import sys
        from pathlib import Path

        sys.path.insert(0, "/opt/saltgoat-reactor")
        import reactor_common  # pylint: disable=import-error

        REPO_ROOT = os.environ.get("SALTGOAT_REPO_ROOT")
        if not REPO_ROOT:
            for candidate in (Path("/opt/saltgoat"), Path("/srv/saltgoat"), Path("/home/doge/saltgoat"), Path("/opt/saltgoat-reactor").resolve().parents[1]):
                if (Path(candidate) / "modules" / "lib" / "notification.py").is_file():
                    REPO_ROOT = str(candidate)
                    break
        if REPO_ROOT:
            sys.path.insert(0, REPO_ROOT)
        from modules.lib import notification as notif  # type: ignore

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
        site = payload.get("site")
        if site:
            summary.append(f"Site: {site}")
        if payload.get("project"):
            summary.append(f"Project: {payload['project']}")
        if payload.get("paths"):
            summary.append(f"Paths: {payload['paths']}")
        if payload.get("file") and payload.get("size"):
            summary.append(f"Archive: {payload['file']} ({payload['size']})")
        elif payload.get("file"):
            summary.append(f"Archive: {payload['file']}")
        if payload.get("database"):
            summary.append(f"Database: {payload['database']}")
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
        SITE_TAG = f"saltgoat/backup/{kind}/{site}" if site else None
        TELEGRAM_TAG = SITE_TAG or TAG

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

        thread_id = notif.get_thread_id(TELEGRAM_TAG) or notif.get_thread_id(f"saltgoat/backup/{kind}")
        profiles = reactor_common.load_telegram_profiles(None, log)
        if not profiles:
            log("skip", {"reason": "no_profiles"})
            notif.queue_failure(
                "telegram",
                TELEGRAM_TAG,
                payload,
                "no_profiles",
                {"thread": thread_id, "parse_mode": notif.get_parse_mode()},
            )
            raise SystemExit()
        parse_mode = notif.get_parse_mode()
        try:
            reactor_common.broadcast_telegram(message, profiles, log, tag=TELEGRAM_TAG, thread_id=thread_id, parse_mode=parse_mode)
        except Exception as exc:  # pylint: disable=broad-except
            log("error", {"message": str(exc)})
            notif.queue_failure(
                "telegram",
                TELEGRAM_TAG,
                payload,
                str(exc),
                {"thread": thread_id, "parse_mode": parse_mode},
            )
            raise
        PY
    - python_shell: True
    - require:
      - local: backup_event_log_{{ data.get('_stamp', '')|replace(':', '_')|replace('.', '_') }}

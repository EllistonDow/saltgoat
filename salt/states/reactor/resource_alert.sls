{# Resource threshold reactor #}
{% set log_path = salt['pillar.get']('saltgoat:reactor:resource_alerts:log_path', '/var/log/saltgoat/alerts.log') %}
{% set tag_parts = tag.split('/') %}
{% set event_minion = data.get('id') or data.get('minion_id') or (tag_parts[2] if tag_parts|length > 2 else '') or data.get('host') or 'minion' %}

resource_alert_log_{{ data.get('_stamp', '')|replace(':', '_')|replace('.', '_') }}:
  local.cmd.run:
    - tgt: {{ event_minion }}
    - arg:
      - |-
        python3 /opt/saltgoat-reactor/logger.py RESOURCE "{{ log_path }}" "{{ tag }}" '{{ data|json }}'
    - python_shell: True

resource_alert_telegram_{{ data.get('_stamp', '')|replace(':', '_')|replace('.', '_') }}:
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
        tag = "{{ tag }}"
        host = payload.get("id") or payload.get("host") or payload.get("minion_id") or "{{ event_minion }}"

        severity_rank = {"INFO": 0, "NOTICE": 1, "WARNING": 2, "CRITICAL": 3}
        severity = "INFO"
        details = []

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

        profiles = reactor_common.load_telegram_profiles(None, log)
        if not profiles:
            log("skip", {"reason": "no_profiles"})
            raise SystemExit()

        cpu_baseline = max(int({{ salt['grains.get']('num_cpus', 1) or 1 }}), 1)
        crit_load_1m = cpu_baseline * 1.5
        warn_load_1m = cpu_baseline * 1.25
        crit_load_5m = cpu_baseline * 1.25
        warn_load_5m = cpu_baseline * 1.1
        crit_load_15m = cpu_baseline * 1.1
        warn_load_15m = cpu_baseline * 1.0
        mem_notice = 78.0
        mem_warn = 85.0
        mem_crit = 90.0

        def bump(level: str):
            global severity
            if severity_rank.get(level, 0) > severity_rank.get(severity, 0):
                severity = level

        def as_float(value):
            try:
                return float(value)
            except (TypeError, ValueError):
                return None

        load_info = payload.get("load") or payload.get("avg")
        if not isinstance(load_info, dict):
            candidate_keys = ("1m", "5m", "15m")
            if any(key in payload for key in candidate_keys):
                load_info = {key: payload.get(key) for key in candidate_keys}
        if isinstance(load_info, dict):
            load1 = as_float(load_info.get("1m") or load_info.get("1") or load_info.get("1min"))
            load5 = as_float(load_info.get("5m") or load_info.get("5") or load_info.get("5min"))
            load15 = as_float(load_info.get("15m") or load_info.get("15") or load_info.get("15min"))
            if any(v is not None for v in (load1, load5, load15)):
                details.append(
                    "Load average: 1m={:.2f} 5m={:.2f} 15m={:.2f}".format(
                        load1 or 0.0, load5 or 0.0, load15 or 0.0
                    )
                )
                if ((load1 or 0) >= crit_load_1m) or ((load5 or 0) >= crit_load_5m) or ((load15 or 0) >= crit_load_15m):
                    bump("CRITICAL")
                elif ((load1 or 0) >= warn_load_1m) or ((load5 or 0) >= warn_load_5m) or ((load15 or 0) >= warn_load_15m):
                    bump("WARNING")
                else:
                    bump("NOTICE")

        mem_info = payload.get("mem") or payload.get("memory") or payload.get("memusage")
        if isinstance(mem_info, dict):
            percent = None
            percent_info = mem_info.get("percent")
            if isinstance(percent_info, dict):
                percent = percent_info.get("used") or percent_info.get("used_percent") or percent_info.get("max")
            else:
                percent = mem_info.get("used_percent")
            percent = as_float(percent)
            if percent is not None:
                details.append("Memory used: {:.1f}%".format(percent))
                if percent >= mem_crit:
                    bump("CRITICAL")
                elif percent >= mem_warn:
                    bump("WARNING")
                elif percent >= mem_notice:
                    bump("NOTICE")

        disk_info = payload.get("diskusage") or payload.get("disk")
        if isinstance(disk_info, dict):
            for mount, usage in disk_info.items():
                percent = as_float(usage)
                if percent is None:
                    continue
                details.append("Disk {} usage: {:.1f}%".format(mount, percent))
                if percent >= 95:
                    bump("CRITICAL")
                elif percent >= 90:
                    bump("WARNING")
                elif percent >= 85:
                    bump("NOTICE")

        if not details:
            details.append("Payload: {}".format(json.dumps(payload, ensure_ascii=False)))

        min_notice = severity_rank.get("NOTICE", 1)
        if severity_rank.get(severity, 0) < min_notice:
            log("skip", {"reason": "below_notice", "severity": severity, "host": host, "tag": tag})
            raise SystemExit()

        lines = [
            "[SaltGoat] {} resource alert".format(severity),
            "Host: {}".format(host),
            "Tag: {}".format(tag),
        ]
        if details:
            lines.append("Details:")
            lines.extend("- {}".format(item) for item in details)

        message = "\n".join(lines)

        reactor_common.broadcast_telegram(message, profiles, log, tag=tag)
        PY
    - python_shell: True
    - require:
      - local: resource_alert_log_{{ data.get('_stamp', '')|replace(':', '_')|replace('.', '_') }}

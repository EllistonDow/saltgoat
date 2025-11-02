#!/bin/bash
# Verify backup notification helpers emit log entries and respect notification filters.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

REACTOR_DIR="${TMP_DIR}/reactor"
mkdir -p "${REACTOR_DIR}"
cat >"${REACTOR_DIR}/__init__.py" <<'PY'
PY

LOGGER="${REACTOR_DIR}/logger.py"
cat >"${LOGGER}" <<'PY'
import json
import sys
from pathlib import Path

_, log_path, label, payload = sys.argv[1:5]
entry = {"label": label, "payload": json.loads(payload)}
path = Path(log_path)
path.parent.mkdir(parents=True, exist_ok=True)
with path.open("a", encoding="utf-8") as fh:
    fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
PY

REACTOR_COMMON="${REACTOR_DIR}/reactor_common.py"
cat >"${REACTOR_COMMON}" <<'PY'
from typing import Any, Dict, List

def load_telegram_profiles(config_path: str, log):
    log("profiles", {"config": config_path})
    return [[{"chat_id": 123, "token": "dummy"}]]

def broadcast_telegram(message: str, profiles: List[List[Dict[str, Any]]], log, tag: str, thread_id=None, parse_mode="HTML"):
    log("broadcast", {"message": message, "tag": tag, "parse_mode": parse_mode})
PY

TELEGRAM_JSON="${TMP_DIR}/telegram.json"
cat >"${TELEGRAM_JSON}" <<'JSON'
{"profiles": [{"chat_id": 123}]}
JSON

ALERT_LOG="${TMP_DIR}/alerts.log"

export SALTGOAT_REACTOR_DIR="${REACTOR_DIR}"
export SALTGOAT_ALERT_LOG="${ALERT_LOG}"
export SALTGOAT_TELEGRAM_CONFIG="${TELEGRAM_JSON}"
export PYTHONPATH="${ROOT_DIR}:${PYTHONPATH:-}"

run_mysql_notification() {
    : >"${ALERT_LOG}"
    (
        set -euo pipefail
        export SALTGOAT_UNIT_TEST=1
        source "${ROOT_DIR}/modules/magetools/mysql-backup.sh"
        notify_dump_telegram success bank /tmp/dump.sql 10MB "" 0 1 bank
    )
    grep -q 'saltgoat/backup/mysql_dump/bank' "${ALERT_LOG}"
}

run_restic_notification() {
    : >"${ALERT_LOG}"
    (
        set -euo pipefail
        export SALTGOAT_UNIT_TEST=1
        source "${ROOT_DIR}/modules/magetools/backup-restic.sh"
        send_direct_notification success /tmp/repo bank /tmp/log.txt data tag 0 manual host
    )
    grep -q 'saltgoat/backup/restic/bank' "${ALERT_LOG}"
}

run_mysql_notification
run_restic_notification

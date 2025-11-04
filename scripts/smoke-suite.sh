#!/bin/bash
# SaltGoat smoke suite: quick confidence run before big changes/rollouts

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

LOG_PREFIX="[SMOKE]"
TIMESTAMP="$(date -Iseconds)"
ARTIFACT_DIR="${SMOKE_ARTIFACT_DIR:-/tmp}"
DOCTOR_REPORT="${ARTIFACT_DIR%/}/saltgoat-doctor-${TIMESTAMP}.md"

log() {
    printf '%s %s\n' "$LOG_PREFIX" "$*"
}

run_step() {
    local title="$1"
    shift
    log "Step: ${title}"
    if "$@"; then
        log "✓ ${title} completed"
    else
        log "✗ ${title} failed"
        exit 1
    fi
}

as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

log "Starting SaltGoat smoke suite @ ${TIMESTAMP}"

run_step "Verify (shellcheck + tests)" bash "${REPO_ROOT}/scripts/verify.sh"
run_step "Monitor auto-sites (dry-run)" as_root saltgoat monitor auto-sites --dry-run
run_step "Monitor quick-check" as_root saltgoat monitor quick-check
run_step "Doctor snapshot" as_root saltgoat doctor --format markdown >"${DOCTOR_REPORT}"

log "Doctor report saved to ${DOCTOR_REPORT}"

HOST_FQDN=$(hostname -f)
HOST_SLUG=$(python3 - "$HOST_FQDN" <<'PY'
import re, sys
name = sys.argv[1].strip().lower()
slug = re.sub(r"[^a-z0-9-]", "-", name.replace("/", "-"))
slug = re.sub(r"-+", "-", slug).strip("-")
print(slug or "host")
PY
)
DOCTOR_TAG="saltgoat/doctor/${HOST_SLUG}"

run_step "Publish doctor report" python3 - "${DOCTOR_REPORT}" "${DOCTOR_TAG}" <<'PY'
import html
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

report_path = Path(sys.argv[1])
tag = sys.argv[2]
text = report_path.read_text(encoding="utf-8").strip()
if not text:
    print("[WARN] Doctor report empty, skip Telegram")
    sys.exit(0)

from modules.lib import notification as notif  # type: ignore

cfg_path = Path("/etc/saltgoat/telegram.json")
try:
    config = json.loads(cfg_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"[WARN] Unable to load Telegram config: {exc}")
    sys.exit(0)

entries = config.get("entries")
if not isinstance(entries, list) or not entries:
    print("[WARN] No Telegram profiles configured")
    sys.exit(0)

entry = entries[0]
token = entry.get("token")
targets = entry.get("targets") or []
chat_id = None
for target in targets:
    if isinstance(target, dict):
        chat = str(target.get("chat_id", ""))
        if chat.startswith("-100"):
            chat_id = chat
            break
if not chat_id:
    for target in targets:
        if isinstance(target, dict) and target.get("chat_id"):
            chat_id = str(target["chat_id"])
            break

if not token or not chat_id:
    print("[WARN] Missing Telegram bot token or chat_id")
    sys.exit(0)

thread_id = notif.get_thread_id(tag) or notif.get_thread_id("saltgoat/doctor")
payload = {
    "chat_id": chat_id,
    "text": f"<b>[INFO] Doctor Snapshot</b>\n<pre>{html.escape(text)}</pre>",
    "parse_mode": "HTML",
    "disable_web_page_preview": True,
}
if thread_id:
    payload["message_thread_id"] = str(thread_id)

data = urllib.parse.urlencode(payload).encode()
url = f"https://api.telegram.org/bot{token}/sendMessage"
try:
    urllib.request.urlopen(url, data=data, timeout=15)
    print("[INFO] Doctor report sent to Telegram")
except Exception as exc:
    print(f"[WARN] Failed to send doctor report: {exc}")
    sys.exit(1)
PY

log "Smoke suite finished successfully."

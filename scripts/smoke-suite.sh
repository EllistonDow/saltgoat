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
import sys
from pathlib import Path

report_path = Path(sys.argv[1])
tag = sys.argv[2]
text = report_path.read_text(encoding="utf-8").strip()
if not text:
    print("[WARN] Doctor report empty, skip Telegram")
    sys.exit(0)

sys.path.insert(0, "/opt/saltgoat-reactor")
try:
    import reactor_common  # type: ignore
except Exception as exc:
    print(f"[WARN] Unable to import reactor_common: {exc}")
    sys.exit(0)

from modules.lib import notification as notif  # type: ignore

def _log(kind, payload):
    print(f"[TELEGRAM:{kind}] {payload}")

profiles = reactor_common.load_telegram_profiles(None, _log)
if not profiles:
    print("[WARN] No Telegram profiles configured via Pillar")
    sys.exit(0)

thread_id = notif.get_thread_id(tag) or notif.get_thread_id("saltgoat/doctor")
message = f"<b>[INFO] Doctor Snapshot</b>\n<pre>{html.escape(text)}</pre>"
reactor_common.broadcast_telegram(message, profiles, _log, tag=tag, thread_id=thread_id)
print("[INFO] Doctor report sent to Telegram")
PY

log "Smoke suite finished successfully."

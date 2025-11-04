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
log "Smoke suite finished successfully."

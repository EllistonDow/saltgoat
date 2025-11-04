#!/bin/bash
# Watch salt/pillar changes and auto-run monitor auto-sites (dry-run)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

log() {
    printf '[%s] %s\n' "$(date -Iseconds)" "$*"
}

log "Running saltgoat verify -- dry-run"
sudo saltgoat verify

log "Running saltgoat monitor auto-sites (dry-run)"
sudo saltgoat monitor auto-sites --dry-run || true

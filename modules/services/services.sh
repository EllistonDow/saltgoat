#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PY_SCRIPT="${SCRIPT_DIR}/scripts/services_overview.py"

services_main() {
    local subcmd="${1:-overview}"
    if [[ "$subcmd" == "overview" || "$subcmd" == "list" ]]; then
        shift
    fi
    python3 "$PY_SCRIPT" "$@"
}

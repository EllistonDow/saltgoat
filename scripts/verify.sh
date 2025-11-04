#!/bin/bash
# SaltGoat 本地自检：确保常用静态检查与单元测试通过

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

log_section() {
    printf '\n==========================================\n%s\n==========================================\n' "$1"
}

log_section "Running scripts/code-review.sh -a"
bash scripts/code-review.sh -a

log_section "Running python3 -m unittest"
python3 -m unittest

log_section "SaltGoat verify completed successfully."

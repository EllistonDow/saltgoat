#!/bin/bash
# SaltGoat doctor summary: quick health snapshot for operators.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

python3 modules/lib/doctor.py "$@"

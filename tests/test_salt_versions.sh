#!/bin/bash
# Quick safety checks for Salt environment

set -euo pipefail

if ! command -v salt-call >/dev/null 2>&1; then
    echo "salt-call command not found; skipping Salt safety checks."
    exit 0
fi

echo "[INFO] Gathering Salt versions (salt-call test.versions_report)..."
sudo bash -c "salt-call --local test.versions_report >/tmp/saltgoat-versions-report.txt"
echo "[SUCCESS] Versions report written to /tmp/saltgoat-versions-report.txt"

echo "[INFO] Rendering optional.analyse lowstate..."
sudo bash -c "salt-call --local state.show_lowstate optional.analyse >/tmp/saltgoat-optional-analyse-lowstate.txt"
echo "[SUCCESS] optional.analyse lowstate captured to /tmp/saltgoat-optional-analyse-lowstate.txt"

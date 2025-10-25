#!/bin/bash
# Dry-run Magento optimization state to ensure templates render correctly.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    exec sudo bash "$0" "$@"
fi

echo "[INFO] Running Magento optimization state (test mode)..."
salt-call --local state.apply optional.magento-optimization test=True

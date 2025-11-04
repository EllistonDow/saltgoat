#!/bin/bash
# Lightweight Magento CLI verification suite.
# Usage: tests/test_magento_cli_suite.sh [/var/www/site]

set -euo pipefail

APP_DIR="${1:-/var/www/tank}"
USER="${MAGENTO_USER:-www-data}"

if [[ ! -f "${APP_DIR}/bin/magento" ]]; then
    echo "bin/magento not found in ${APP_DIR}" >&2
    exit 1
fi

run_magento() {
    local cmd="$1"
    echo ">> php bin/magento ${cmd}"
    sudo -u "${USER}" -H bash -lc "cd '${APP_DIR}' && php bin/magento ${cmd}"
    echo ""
}

COMMANDS=(
    "cache:status"
    "app:config:status"
    "indexer:info"
    "setup:db:status --verbose"
    "config:show web/secure/base_url"
    "config:show system/full_page_cache/caching_application"
    "cron:install --help"
    "module:status"
    "setup:di:compile --help"
)

for cmd in "${COMMANDS[@]}"; do
    run_magento "$cmd"
done

echo "Magento CLI verification complete for ${APP_DIR}"

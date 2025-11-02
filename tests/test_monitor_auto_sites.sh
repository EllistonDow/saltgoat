#!/bin/bash
# Test monitor_auto_sites site discovery and YAML generation with mock directories
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

SITE_ROOT="${TMP_DIR}/www"
NGINX_DIR="${TMP_DIR}/nginx"
MONITOR_FILE="${TMP_DIR}/monitoring.sls"

mkdir -p "${SITE_ROOT}/bank/app/etc" "${NGINX_DIR}"
cat >"${SITE_ROOT}/bank/app/etc/env.php" <<'PHP'
<?php
return [
    'backend' => [
        'frontName' => 'admin'
    ],
];
PHP

cat >"${NGINX_DIR}/bank.conf" <<CONF
server {
    listen 80;
    server_name bank.example.com;
    root ${SITE_ROOT}/bank;
}
CONF

OUTPUT=$(SCRIPT_DIR="${ROOT_DIR}" SALTGOAT_SITE_ROOT="${SITE_ROOT}" SALTGOAT_NGINX_DIR="${NGINX_DIR}" SALTGOAT_MONITOR_FILE="${MONITOR_FILE}" SALTGOAT_SKIP_SALT_CALL=1 SALTGOAT_SKIP_SYSTEMCTL=1 SALTGOAT_SKIP_TELEGRAM=1 SALTGOAT_SKIP_REFRESH=1 bash <<'SUBSHELL'
set -euo pipefail
log_highlight(){ :; }
log_info(){ :; }
log_success(){ :; }
log_warning(){ :; }
log_error(){ :; }
source "${SCRIPT_DIR}/monitoring/system.sh"
monitor_auto_sites
SUBSHELL
)

echo "$OUTPUT" | grep -q "ADDED_SITES bank"

grep -q "bank" "${MONITOR_FILE}"
grep -q "bank.example.com" "${MONITOR_FILE}" || grep -q "127.0.0.1" "${MONITOR_FILE}"
grep -q "tls_warn_days" "${MONITOR_FILE}"

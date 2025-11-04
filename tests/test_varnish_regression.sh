#!/bin/bash
# Regression helper that toggles Varnish for selected sites and verifies HTTP reachability.
# Usage: tests/test_varnish_regression.sh [site ...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PILLAR_FILE="${REPO_ROOT}/salt/pillar/nginx.sls"
DEFAULT_SITES=(bank tank pwas)
SITES=("$@")
declare -A ORIGINAL_STATE=()
declare -A TARGET_URL=()

if [[ ${#SITES[@]} -eq 0 ]]; then
    SITES=("${DEFAULT_SITES[@]}")
fi

log() {
    local level="$1"; shift
    printf '==> [%s] %s\n' "$level" "$*"
}

site_state() {
    local site="$1"
    if sudo grep -q "/etc/nginx/snippets/varnish-frontend-${site}.conf" "/etc/nginx/sites-available/${site}" 2>/dev/null; then
        echo "enabled"
    else
        echo "disabled"
    fi
}

resolve_site_url() {
    local site="$1"
    sudo python3 - "$PILLAR_FILE" "$site" <<'PY' || true
import sys, yaml
pillar, site = sys.argv[1:3]
try:
    data = yaml.safe_load(open(pillar, encoding="utf-8")) or {}
except FileNotFoundError:
    data = {}
sites = ((data.get("nginx") or {}).get("sites") or {})
entry = sites.get(site, {})
names = entry.get("server_name") or []
if isinstance(names, list) and names:
    print(f"https://{names[0]}")
elif isinstance(names, str) and names.strip():
    print(f"https://{names.strip()}")
PY
}

http_check() {
    local url="$1"
    local expect_varnish="$2"
    local site="$3"
    local tmp_headers body status
    tmp_headers="$(mktemp)"
    body="$(mktemp)"
    status="$(curl -sS -o "$body" -D "$tmp_headers" -w "%{http_code}" -H "Cache-Control: no-cache" --retry 2 --retry-all-errors --max-time 20 "$url")" || status="000"
    if [[ "$status" != "200" ]]; then
        log "ERROR" "${site}: HTTP ${status} for ${url}"
        log "ERROR" "Response snippet: $(head -n 3 "$body")"
        rm -f "$tmp_headers" "$body"
        return 1
    fi
    if [[ "$expect_varnish" == "yes" ]]; then
        if ! grep -qi '^X-Varnish:' "$tmp_headers"; then
            log "ERROR" "${site}: missing X-Varnish header while expecting cached response"
            rm -f "$tmp_headers" "$body"
            return 1
        fi
    else
        if grep -qi '^X-Varnish:' "$tmp_headers"; then
            log "WARN" "${site}: received X-Varnish header while Varnish should be disabled"
        fi
    fi
    rm -f "$tmp_headers" "$body"
    log "INFO" "${site}: ${url} returned 200 (${expect_varnish})"
}

disable_site() {
    local site="$1"
    log "INFO" "${site}: disabling Varnish"
    sudo saltgoat magetools varnish disable "$site"
}

enable_site() {
    local site="$1"
    log "INFO" "${site}: enabling Varnish"
    sudo saltgoat magetools varnish enable "$site"
}

cleanup() {
    local rc="${1:-$?}"
    for site in "${SITES[@]}"; do
        local desired="${ORIGINAL_STATE[$site]:-}"
        [[ -z "$desired" ]] && continue
        local current
        current="$(site_state "$site")"
        if [[ "$desired" != "$current" ]]; then
            log "WARN" "Restoring ${site} to ${desired}"
            if [[ "$desired" == "enabled" ]]; then
                sudo saltgoat magetools varnish enable "$site" >/dev/null 2>&1 || true
            else
                sudo saltgoat magetools varnish disable "$site" >/dev/null 2>&1 || true
            fi
        fi
    done
    trap - EXIT
    exit "$rc"
}

trap 'cleanup "$?"' EXIT

main() {
    for site in "${SITES[@]}"; do
        [[ -n "$site" ]] || continue
        ORIGINAL_STATE["$site"]="$(site_state "$site")"
        TARGET_URL["$site"]="$(resolve_site_url "$site")"
        if [[ -z "${TARGET_URL[$site]}" ]]; then
            TARGET_URL["$site"]="https://${site}.magento.tattoogoat.com"
        fi
        log "INFO" "${site}: original state ${ORIGINAL_STATE[$site]}, URL ${TARGET_URL[$site]}"
        if [[ "${ORIGINAL_STATE[$site]}" == "enabled" ]]; then
            sudo saltgoat magetools varnish diagnose "$site" >/dev/null
        fi

        if [[ "${ORIGINAL_STATE[$site]}" == "enabled" ]]; then
            disable_site "$site"
            http_check "${TARGET_URL[$site]}" "no" "$site"
            enable_site "$site"
            http_check "${TARGET_URL[$site]}" "yes" "$site"
        else
            enable_site "$site"
            sudo saltgoat magetools varnish diagnose "$site" >/dev/null
            http_check "${TARGET_URL[$site]}" "yes" "$site"
            disable_site "$site"
            http_check "${TARGET_URL[$site]}" "no" "$site"
        fi
        log "INFO" "${site}: regression cycle complete"
    done
    return 0
}

main "$@"
rc=$?
trap - EXIT
cleanup "$rc"

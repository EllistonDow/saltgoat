#!/bin/bash
# Quick TUI-style status panel for common SaltGoat services and Magento storefronts.
# Usage: scripts/health-panel.sh [site ...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PILLAR_FILE="${REPO_ROOT}/salt/pillar/nginx.sls"
SERVICES=(nginx php8.3-fpm varnish mysql rabbitmq-server redis-server valkey-server salt-minion)
SITES=("$@")

if [[ ${#SITES[@]} -eq 0 ]]; then
    SITES=(bank tank pwas)
fi

log_header() {
    printf '\n== %s ==\n' "$1"
}

service_exists() {
    local svc="$1"
    systemctl status "$svc" >/dev/null 2>&1
}

service_row() {
    local svc="$1"
    local display="${svc}.service"
    if ! systemctl status "$svc" >/dev/null 2>&1; then
        printf '%-24s %-10s %-20s %s\n' "$display" "absent" "-" "-"
        return
    fi
    local state enabled since sub pid
    state="$(systemctl is-active "$svc" 2>/dev/null || echo unknown)"
    enabled="$(systemctl is-enabled "$svc" 2>/dev/null || echo "-")"
    since="$(systemctl show -p ActiveEnterTimestamp "$svc" 2>/dev/null | cut -d= -f2)"
    sub="$(systemctl show -p SubState "$svc" 2>/dev/null | cut -d= -f2)"
    pid="$(systemctl show -p MainPID "$svc" 2>/dev/null | cut -d= -f2)"
    [[ -z "$since" ]] && since="-"
    [[ -z "$sub" ]] && sub="-"
    [[ -z "$pid" || "$pid" == "0" ]] && pid="-"
    printf '%-24s %-10s %-20s %s (pid %s)\n' "$display" "$state/$enabled" "${since:0:19}" "$sub" "$pid"
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

site_row() {
    local site="$1"
    local url="$2"
    local headers body status time_total cache curl_output rc
    headers="$(mktemp)"
    body="$(mktemp)"
    set +e
    curl_output="$(curl -sS -o "$body" -D "$headers" -w "%{http_code} %{time_total}" -H "Cache-Control: no-cache" --max-time 15 --retry 1 "$url")"
    rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
        status="000"
        time_total="0"
    else
        read -r status time_total <<<"$curl_output"
    fi
    if [[ "$status" != "200" ]]; then
        printf '%-8s %-6s %-8s %s\n' "$site" "$status" "-" "$url"
    else
        if grep -qi '^X-Varnish:' "$headers"; then
            cache="via-varnish"
        else
            cache="direct"
        fi
        printf '%-8s %-6s %-8ss %s (%s)\n' "$site" "$status" "$time_total" "$url" "$cache"
    fi
    rm -f "$headers" "$body"
}

log_header "Service status"
printf '%-24s %-10s %-20s %s\n' "Unit" "State/Enabled" "ActiveSince" "Details"
for svc in "${SERVICES[@]}"; do
    service_row "$svc"
done

log_header "Storefront probes"
printf '%-8s %-6s %-8s %s\n' "Site" "HTTP" "Time" "URL"
for site in "${SITES[@]}"; do
    [[ -n "$site" ]] || continue
    url="$(resolve_site_url "$site")"
    if [[ -z "$url" ]]; then
        url="https://${site}.magento.tattoogoat.com"
    fi
    site_row "$site" "$url"
done

log_header "Disk usage"
df -h /var/www /var/log / | awk 'NR==1 || /^\/dev/ || /^Filesystem/'

#!/bin/bash
# Goat Pulse MOTD + GeoIP city lookup.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOAT_PULSE="${SCRIPT_DIR}/goat_pulse.py"
LOGGER="/var/log/saltgoat/geoip.log"

clear
if [[ -x "$GOAT_PULSE" ]]; then
    python3 "$GOAT_PULSE" --once || true
fi

printf '\nLast login city info:\n'
if command -v last >/dev/null 2>&1; then
    ENTRY="$(last -i | grep -m1 -v 'pts/0' || true)"
    if [[ -n "$ENTRY" ]]; then
        IP="$(awk '{print $3}' <<<"$ENTRY")"
        if [[ "$IP" =~ ^[0-9] ]]; then
            CITY="$(python3 "${SCRIPT_DIR}/geoip_lookup.py" "$IP" 2>/dev/null || true)"
            printf 'IP %s -> %s\n' "$IP" "$CITY"
            printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$CITY" >>"$LOGGER"
        else
            printf 'IP %s -> local/unknown\n' "$IP"
        fi
    else
        printf 'No previous login entries\n'
    fi
else
    printf 'last command unavailable\n'
fi

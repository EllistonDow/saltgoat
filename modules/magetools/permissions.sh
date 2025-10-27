#!/bin/bash
# Magento 权限管理入口（基于 Salt state）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../lib/logger.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"

ensure_magento_site() {
    local site_path="$1"
    if [[ ! -f "$site_path/bin/magento" ]]; then
        log_error "未在 Magento 目录中，请指定正确路径"
        log_info "示例: saltgoat magetools permissions fix /var/www/site"
        exit 1
    fi
}

build_pillar_json() {
    python3 - <<'PY' "$1"
import json, sys
print(json.dumps({"site_path": sys.argv[1]}))
PY
}

apply_permissions_state() {
    local site_path="$1"
    local state_name="$2"
    local mode="$3"

    ensure_magento_site "$site_path"
    local pillar_json
    pillar_json=$(build_pillar_json "$site_path")

    local args=(--local --retcode-passthrough state.apply "$state_name" "pillar=$pillar_json")
    if [[ "$mode" == "test" ]]; then
        args+=(test=True)
        log_info "以 test=True 模式检查权限变更 (site: $site_path)"
    else
        log_info "应用 Salt 权限 state: $state_name (site: $site_path)"
    fi

    sudo salt-call "${args[@]}"
}

fix_magento_permissions() {
    local site_path="${1:-$(pwd)}"
    apply_permissions_state "$site_path" optional.magento-permissions-smart apply
}

check_magento_permissions() {
    local site_path="${1:-$(pwd)}"
    apply_permissions_state "$site_path" optional.magento-permissions-smart test
}

reset_magento_permissions() {
    local site_path="${1:-$(pwd)}"
    log_warning "将重新应用权限 state（同 fix），是否继续? (y/N)"
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "操作已取消"
        exit 0
    fi
    apply_permissions_state "$site_path" optional.magento-permissions-generic apply
}

#!/bin/bash
# Magento 权限管理入口（基于 Salt state）

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
fi

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

fast_fix_magento_permissions_local() {
    local site_path="$1"
    local site_user="${2:-www-data}"
    local site_group="${3:-www-data}"
    local max_parallel_jobs="${MAGENTO_PERMISSIONS_MAX_JOBS:-16}"
    local batch_size="${MAGENTO_PERMISSIONS_BATCH_SIZE:-2000}"

    ensure_magento_site "$site_path"

    log_info "高性能修正 Magento 权限 (path: $site_path, user: $site_user, group: $site_group)"

    sudo chown -R "${site_user}:${site_group}" "$site_path"

    (
        cd "$site_path" || exit 1

        find . -type d -print0 | xargs -0 -r -n "$batch_size" -P "$max_parallel_jobs" sudo chmod 755
        find . -type f -print0 | xargs -0 -r -n "$batch_size" -P "$max_parallel_jobs" sudo chmod 644

        local writable_dirs=(var generated "pub/media" "pub/static")
        local dir_path
        for dir_path in "${writable_dirs[@]}"; do
            [[ -d "$dir_path" ]] || continue
            find "$dir_path" -type d -print0 | xargs -0 -r -n "$batch_size" -P "$max_parallel_jobs" sudo chmod 775
            find "$dir_path" -type f -print0 | xargs -0 -r -n "$batch_size" -P "$max_parallel_jobs" sudo chmod 664
            find "$dir_path" -type d -print0 | xargs -0 -r -n "$batch_size" -P "$max_parallel_jobs" sudo chmod g+s
        done

        if [[ -d "app/etc" ]]; then
            sudo chmod 770 app/etc
            sudo chmod g+s app/etc
        fi

        if [[ -f "bin/magento" ]]; then
            sudo chmod 755 bin/magento
        fi

        find . -type f -name "*.sh" -print0 | xargs -0 -r -n "$batch_size" -P "$max_parallel_jobs" sudo chmod 755

        if [[ -f "app/etc/env.php" ]]; then
            sudo chmod 660 app/etc/env.php
        fi
    ) || return 1

    log_success "Magento 权限修复完成（高性能并行模式）"
}

#!/bin/bash
# Magento Valkey 配置检测（Salt 原生）
# 用法:
#   saltgoat magetools valkey-check <site>
#     [--site-path /var/www/custom]
#     [--expected-owner www-data]
#     [--expected-group www-data]
#     [--expected-perms 640]
#     [--valkey-conf /etc/valkey/valkey.conf]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/utils.sh"

SITE_NAME=""
SITE_PATH=""
EXPECTED_OWNER="www-data"
EXPECTED_GROUP="www-data"
EXPECTED_PERMS=""
VALKEY_CONF="/etc/valkey/valkey.conf"

usage() {
    cat <<'EOF'
SaltGoat Magento Valkey 配置检测

用法:
  saltgoat magetools valkey-check <site> [选项]

选项:
  --site-path PATH       指定站点路径（默认 /var/www/<site>）
  --expected-owner USER  校验 env.php 所有者（默认 www-data）
  --expected-group GROUP 校验 env.php 所属组（默认 www-data）
  --expected-perms NNN   校验 env.php 权限位（如 640，默认不校验）
  --valkey-conf PATH     指定 Valkey 配置文件（默认 /etc/valkey/valkey.conf）
  -h, --help             显示帮助
EOF
}

abort() {
    log_error "$1"
    exit 1
}

parse_args() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --site-path)
                [[ $# -lt 2 ]] && abort "--site-path 需要一个值"
                SITE_PATH="$2"
                shift 2
                ;;
            --expected-owner)
                [[ $# -lt 2 ]] && abort "--expected-owner 需要一个值"
                EXPECTED_OWNER="$2"
                shift 2
                ;;
            --expected-group)
                [[ $# -lt 2 ]] && abort "--expected-group 需要一个值"
                EXPECTED_GROUP="$2"
                shift 2
                ;;
            --expected-perms)
                [[ $# -lt 2 ]] && abort "--expected-perms 需要一个值"
                EXPECTED_PERMS="$2"
                shift 2
                ;;
            --valkey-conf)
                [[ $# -lt 2 ]] && abort "--valkey-conf 需要一个值"
                VALKEY_CONF="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                abort "未知参数: $1"
                ;;
            *)
                if [[ -z "$SITE_NAME" ]]; then
                    SITE_NAME="$1"
                    shift
                else
                    abort "多余的位置参数: $1"
                fi
                ;;
        esac
    done

    if [[ -z "$SITE_NAME" ]]; then
        abort "必须指定站点名称"
    fi
    if [[ "$SITE_NAME" =~ [^a-zA-Z0-9_-] ]]; then
        abort "站点名称包含非法字符: $SITE_NAME"
    fi
}

resolve_site_path() {
    if [[ -z "$SITE_PATH" ]]; then
        SITE_PATH="/var/www/${SITE_NAME}"
    fi
    if [[ ! -d "$SITE_PATH" ]]; then
        abort "站点路径不存在: $SITE_PATH"
    fi
    if [[ ! -f "${SITE_PATH}/app/etc/env.php" ]]; then
        abort "未找到 Magento 配置文件: ${SITE_PATH}/app/etc/env.php"
    fi
}

build_pillar_json() {
    export PILLAR_SITE_NAME="$SITE_NAME"
    export PILLAR_SITE_PATH="$SITE_PATH"
    export PILLAR_EXPECTED_OWNER="$EXPECTED_OWNER"
    export PILLAR_EXPECTED_GROUP="$EXPECTED_GROUP"
    export PILLAR_EXPECTED_PERMS="$EXPECTED_PERMS"
    export PILLAR_VALKEY_CONF="$VALKEY_CONF"

    python3 <<'PY'
import json
import os

pillar = {
    "site_name": os.environ["PILLAR_SITE_NAME"],
    "site_path": os.environ["PILLAR_SITE_PATH"],
    "expected_owner": os.environ["PILLAR_EXPECTED_OWNER"],
    "expected_group": os.environ["PILLAR_EXPECTED_GROUP"],
    "expected_perms": os.environ["PILLAR_EXPECTED_PERMS"],
    "valkey_conf": os.environ["PILLAR_VALKEY_CONF"],
}

print(json.dumps(pillar, ensure_ascii=False))
PY
}

run_check() {
    local pillar_json
    pillar_json="$(build_pillar_json)"

    log_info "执行 Magento Valkey 配置检测 ..."
    if ! sudo salt-call --local --retcode-passthrough state.apply optional.magento-valkey-check pillar="$pillar_json"; then
        abort "Valkey 检测失败"
    fi
    log_success "Valkey 检测完成"
}

main() {
    parse_args "$@"
    resolve_site_path
    run_check
}

main "$@"

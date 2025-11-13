#!/bin/bash
# PWA 命令入口

: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/modules/pwa/onepage.sh"

pwa_handler() {
    if [[ $# -eq 0 ]]; then
        "${SCRIPT_DIR}/modules/pwa/install.sh" help
        return
    fi

    case "$1" in
        "create")
            shift
            pwa_onepage_handler "$@"
            ;;
        "install"|"remove"|"status"|"sync-content"|"doctor"|"help"|"--help"|"-h"|"version"|"--version")
            "${SCRIPT_DIR}/modules/pwa/install.sh" "$@"
            ;;
        *)
            log_error "未知的 PWA 操作: ${1}"
            log_info "支持: install, remove, status, sync-content, doctor, help"
            exit 1
            ;;
    esac
}

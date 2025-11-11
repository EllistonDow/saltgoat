#!/bin/bash

is_true() {
    case "$1" in
        1|true|TRUE|True|yes|YES|on|ON) return 0 ;;
    esac
    return 1
}

abort() {
    log_error "$1"
    exit 1
}

systemd_unit_exists() {
    local unit="$1"
    systemctl list-unit-files "$unit" >/dev/null 2>&1
}

systemd_stop_unit() {
    local unit="$1"
    if systemd_unit_exists "$unit"; then
        if systemctl stop "$unit" >/dev/null 2>&1; then
            log_info "已停止 systemd 单元: ${unit}"
        fi
    fi
}

systemd_disable_unit() {
    local unit="$1"
    if systemd_unit_exists "$unit"; then
        if systemctl disable "$unit" >/dev/null 2>&1; then
            log_info "已禁用 systemd 单元: ${unit}"
        fi
    fi
}

pwa_service_name() {
    echo "pwa-frontend-${PWA_SITE_NAME}"
}

pwa_service_unit() {
    echo "$(pwa_service_name).service"
}

pwa_service_path() {
    echo "/etc/systemd/system/$(pwa_service_name).service"
}

safe_remove_path() {
    local target="$1"
    if [[ -z "$target" || "$target" == "/" || "$target" == "/*" ]]; then
        log_warning "安全保护：忽略对路径 '${target}' 的删除请求"
        return 1
    fi
    rm -rf --one-file-system "$target"
}

version_ge() {
    local current="$1"
    local required="$2"
    [[ "$(printf '%s\n%s\n' "$required" "$current" | sort -V | head -n1)" == "$required" ]]
}

escape_arg() {
    local arg="$1"
    printf "'"
    printf "%s" "$arg" | sed "s/'/'\\''/g"
    printf "'"
}

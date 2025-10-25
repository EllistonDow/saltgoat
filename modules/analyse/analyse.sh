#!/bin/bash
# Analyse 模块 - 部署网站分析平台（首批支持 Matomo）

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${MODULE_DIR}/../../lib/logger.sh"
# shellcheck disable=SC1091
source "${MODULE_DIR}/../../lib/utils.sh"

# 默认 Matomo 配置（可通过 Pillar 覆盖）
MATOMO_DEFAULT_INSTALL_DIR="/var/www/matomo"
MATOMO_DEFAULT_DOMAIN="matomo.local"
MATOMO_STATE_ID="optional.matomo"

analyse_install_matomo() {
    log_highlight "准备安装 Matomo 分析平台..."

    # 显示当前 Pillar 配置（如存在）
    local install_dir domain
    install_dir="$MATOMO_DEFAULT_INSTALL_DIR"
    domain="$MATOMO_DEFAULT_DOMAIN"
    if sudo test -f "$(get_local_pillar_file)"; then
        local pillar_value
        pillar_value=$(sudo salt-call --local pillar.get matomo.install_dir --out txt 2>/dev/null | awk '{print $2}' | tail -n 1)
        if [[ -n "$pillar_value" && "$pillar_value" != "None" ]]; then
            install_dir="$pillar_value"
        fi

        pillar_value=$(sudo salt-call --local pillar.get matomo.domain --out txt 2>/dev/null | awk '{print $2}' | tail -n 1)
        if [[ -n "$pillar_value" && "$pillar_value" != "None" ]]; then
            domain="$pillar_value"
        fi
    fi

    log_info "目标目录: ${install_dir}"
    log_info "访问域名: ${domain}"
    log_info "Salt 状态: ${MATOMO_STATE_ID}"

    if ! command_exists salt-call; then
        log_error "未检测到 salt-call，无法使用 Salt 状态安装"
        return 1
    fi

    if sudo salt-call --local state.apply "${MATOMO_STATE_ID}"; then
        log_success "Matomo 安装状态已成功执行"
        log_info "请访问 http://${domain}/ 完成 Web 向导配置。"
        log_note "如需 HTTPS，可运行: saltgoat nginx add-ssl ${domain} <email>"
    else
        log_error "Matomo 安装状态执行失败"
        return 1
    fi
}

analyse_install() {
    local target="${1:-}"
    case "$target" in
        "matomo")
            analyse_install_matomo
            ;;
        ""|"-h"|"--help"|"help")
            log_info "用法: saltgoat analyse install <matomo>"
            ;;
        *)
            log_error "未知的 analyse 组件: ${target}"
            log_info "当前支持: matomo"
            return 1
            ;;
    esac
}

analyse_handler() {
    local action="${1:-}"
    case "$action" in
        "install")
            analyse_install "$2"
            ;;
        ""|"-h"|"--help"|"help")
            show_analyse_help
            ;;
        *)
            log_error "未知的 analyse 操作: ${action}"
            log_info "支持: install"
            return 1
            ;;
    esac
}

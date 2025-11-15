#!/bin/bash
# Magento 2 + PWA 后端一键安装脚本

set -euo pipefail

: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# 供拆分后的 lib 脚本读取的全局常量
PWA_HELPER="${SCRIPT_DIR}/modules/lib/pwa_helpers.py"
PWA_HEALTH_HELPER="${SCRIPT_DIR}/modules/lib/pwa_health.py"
CONFIG_FILE="${SCRIPT_DIR}/salt/pillar/magento-pwa.sls"
DEFAULT_NODE_VERSION="18"
DEFAULT_PWA_PORT="8082"
declare -a PWA_REQUIRED_ENV_VARS=("MAGENTO_BACKEND_URL" "CHECKOUT_BRAINTREE_TOKEN")
PWA_HOME_TEMPLATE_WARNING=""
: "$PWA_HELPER" "$PWA_HEALTH_HELPER" "$CONFIG_FILE" "$DEFAULT_NODE_VERSION" "$DEFAULT_PWA_PORT" "$PWA_HOME_TEMPLATE_WARNING"
: "${PWA_REQUIRED_ENV_VARS[@]}"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/utils.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/modules/magetools/permissions.sh"

PWA_LIB_DIR="${SCRIPT_DIR}/modules/pwa/lib"
# shellcheck disable=SC1091
source "${PWA_LIB_DIR}/common.sh"
# shellcheck disable=SC1091
source "${PWA_LIB_DIR}/config.sh"
# shellcheck disable=SC1091
source "${PWA_LIB_DIR}/magento.sh"
# shellcheck disable=SC1091
source "${PWA_LIB_DIR}/pwa_studio.sh"
# shellcheck disable=SC1091
source "${PWA_LIB_DIR}/status.sh"

PWA_WITH_FRONTEND="false"

usage() {
    cat <<'EOF'
SaltGoat Magento PWA 安装助手

用法:
  saltgoat pwa install <site> [--with-pwa|--no-pwa]
  saltgoat pwa status <site>
  saltgoat pwa sync-content <site> [--pull] [--rebuild] [--skip-cms] [--home-id <identifier>]
  saltgoat pwa remove <site> [--purge]
  saltgoat pwa help

说明:
  - <site> 必须在 salt/pillar/magento-pwa.sls 中定义
  - 首次运行会自动安装 Node/Yarn（如缺失）、创建数据库/用户、生成 Magento 项目并执行 setup:install
  - 可选地调用现有的 Valkey / RabbitMQ / Cron 自动化脚本
  - 如配置中启用 pwa_studio.enable 或追加 --with-pwa，将自动克隆 PWA Studio 并执行 Yarn 构建
  - `status` 输出站点与前端服务状态；`sync-content` 用于重新应用 overrides/环境变量，按需拉取仓库或重建；`--skip-cms` 可跳过 CMS 模板写入；`--no-pb` 将首页 identifier 切换到无 Page Builder 版本；`--home-id` 可显式指定 identifier；`remove --purge` 可清理 systemd 服务并删除 PWA Studio 目录
EOF
}

summarize_install() {
    echo ""
    log_highlight "PWA 站点安装完成"
    cat <<EOF
- 站点目录: ${PWA_ROOT}
- 后台地址: ${PWA_BASE_URL_SECURE}${PWA_ADMIN_FRONTNAME}
- 管理员账号: ${PWA_ADMIN_USER} / ${PWA_ADMIN_PASSWORD}
- 数据库: ${PWA_DB_NAME} (${PWA_DB_USER}@${PWA_DB_HOST})
- OpenSearch: ${PWA_OPENSEARCH_SCHEME:-http}://${PWA_OPENSEARCH_HOST}:${PWA_OPENSEARCH_PORT} (index prefix: ${PWA_OPENSEARCH_PREFIX})
- Node.js: $(command_exists node && node --version || echo "未安装")
- Yarn: $(command_exists yarn && yarn --version || echo "未安装")
EOF
    if [[ "$PWA_WITH_FRONTEND" == "true" ]]; then
        cat <<EOF
- PWA Studio: ${PWA_STUDIO_DIR}
- PWA 环境文件: ${PWA_STUDIO_ENV_FILE}
EOF
    fi

    log_info "后续建议:"
    cat <<EOF
1. 配置 SSL 证书并运行: sudo saltgoat magetools varnish enable ${PWA_SITE_NAME}
2. 运行: sudo saltgoat magetools valkey-setup ${PWA_SITE_NAME} （如未自动执行）
3. 运行: sudo saltgoat magetools rabbitmq-salt smart ${PWA_SITE_NAME} （如未自动执行）
4. 如启用 PWA Studio，可将构建产物通过 Nginx/PM2 对外发布，详见 docs/magento-pwa.md。
EOF
}

set_pwa_home_identifier() {
    local identifier="$1"
    if [[ -z "$identifier" ]]; then
        return
    fi
    local overrides
    overrides=$(python3 -c 'import json,sys; print(json.dumps({"MAGENTO_PWA_HOME_IDENTIFIER": sys.argv[1]}))' "$identifier")
    if python3 "$PWA_HELPER" apply-env --file "$PWA_STUDIO_ENV_FILE" --overrides "$overrides"; then
        local root_env="${PWA_STUDIO_DIR%/}/.env"
        local venia_env="${PWA_STUDIO_DIR%/}/packages/venia-concept/.env"
        sync_env_copy "$PWA_STUDIO_ENV_FILE" "$root_env"
        sync_env_copy "$PWA_STUDIO_ENV_FILE" "$venia_env"
        log_info "已设置 MAGENTO_PWA_HOME_IDENTIFIER=${identifier}"
    else
        log_warning "更新 MAGENTO_PWA_HOME_IDENTIFIER 失败 (${identifier})"
    fi
}

install_site() {
    local site="$1"
    local pwa_override="$2"
    load_site_config "$site"
    if [[ -n "$pwa_override" ]]; then
        if [[ "$pwa_override" == "true" ]]; then
            PWA_WITH_FRONTEND="true"
        elif [[ "$pwa_override" == "false" ]]; then
            PWA_WITH_FRONTEND="false"
        fi
    fi
    ensure_node_yarn
    ensure_directory
    ensure_composer_project
    ensure_mysql_root_password
    ensure_mysql_log_bin_trust
    ensure_database
    run_magento_install
    post_install_tasks
    install_cron_if_needed
    configure_valkey_if_needed
    configure_rabbitmq_if_needed
    if is_true "${PWA_WITH_FRONTEND:-false}"; then
        prepare_pwa_repo
        ensure_saltgoat_extension_workspace
        build_pwa_frontend
        ensure_pwa_service
    else
        log_info "当前站点未启用 PWA Studio，跳过前端构建与服务创建。"
    fi
    summarize_install
}

sync_site_content() {
    local site="$1"
    local do_pull="$2"
    local do_rebuild="$3"
    local skip_cms="$4"
    local use_alt_home="${5:-false}"
    local custom_home_identifier="${6:-}"
    load_site_config "$site"

    if ! is_true "${PWA_WITH_FRONTEND:-false}"; then
        log_warning "该站点 Pillar 未启用 PWA Studio，同步流程已跳过。"
        return 0
    fi
    if [[ ! -d "$PWA_STUDIO_DIR" ]]; then
        if is_true "$do_pull"; then
            log_info "PWA Studio 目录缺失，将重新克隆。"
        else
            log_warning "未检测到 PWA Studio 目录: ${PWA_STUDIO_DIR}，建议添加 --pull 重新获取仓库。"
        fi
    fi

    if is_true "$do_pull"; then
        prepare_pwa_repo
        ensure_saltgoat_extension_workspace
    elif [[ ! -d "$PWA_STUDIO_DIR/.git" ]]; then
        log_warning "PWA Studio 仓库未初始化，可使用 --pull 自动克隆。"
    fi

    if [[ -d "$PWA_STUDIO_DIR" ]]; then
        ensure_saltgoat_extension_workspace
        sync_pwa_overrides
        ensure_checkout_payment_override
        apply_mos_graphql_fixes
        prepare_pwa_env
        if [[ -n "$custom_home_identifier" ]]; then
            set_pwa_home_identifier "$custom_home_identifier"
        elif is_true "$use_alt_home"; then
            local fallback_identifier
            fallback_identifier="$(read_pwa_env_value "MAGENTO_PWA_ALT_HOME_IDENTIFIER" 2>/dev/null || echo "pwa_home_no_pb")"
            if [[ -z "$fallback_identifier" ]]; then
                fallback_identifier="pwa_home_no_pb"
            fi
            log_info "已根据 --no-pb 将首页 Identifier 切换为 ${fallback_identifier}"
            set_pwa_home_identifier "$fallback_identifier"
        fi
        prune_unused_pwa_extensions
        if ! is_true "$skip_cms"; then
            ensure_pwa_home_cms_page
            ensure_pwa_no_pb_cms_page
            log_pwa_home_identifier_hint
        else
            log_info "已根据参数跳过 CMS 模板同步，保留现有后台内容。"
        fi
        if is_true "$do_rebuild"; then
            cleanup_package_lock
            ensure_pwa_root_peer_dependencies
            if ensure_pwa_env_vars; then
                run_yarn_task "${PWA_STUDIO_INSTALL_COMMAND:-yarn install}"
                run_yarn_task "${PWA_STUDIO_BUILD_COMMAND:-yarn build}"
            else
                log_warning "缺少必需的 PWA 环境变量，已跳过 Yarn 构建。"
            fi
        fi
        ensure_pwa_service
        log_highlight "PWA 内容同步完成（${PWA_SITE_NAME}）"
    else
        log_warning "同步已结束，但 PWA Studio 目录仍不存在，请检查配置或使用 --pull 重新获取。"
    fi
}

remove_site() {
    local site="$1"
    local purge="$2"
    load_site_config "$site"

    local service_unit
    service_unit="$(pwa_service_unit)"
    local service_path
    service_path="$(pwa_service_path)"

    systemd_stop_unit "$service_unit"
    systemd_disable_unit "$service_unit"

    if [[ -f "$service_path" ]]; then
        rm -f "$service_path"
        log_info "已移除 systemd 服务文件: ${service_path}"
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi

    if is_true "$purge"; then
        if [[ -d "$PWA_STUDIO_DIR" ]]; then
            log_info "清理 PWA Studio 目录: ${PWA_STUDIO_DIR}"
            safe_remove_path "$PWA_STUDIO_DIR"
        else
            log_info "未检测到 PWA Studio 目录，无需清理。"
        fi
    else
        log_info "保留 PWA Studio 目录: ${PWA_STUDIO_DIR}"
    fi

    log_highlight "已完成 PWA 前端卸载（${PWA_SITE_NAME}）"
}

ACTION="${1:-}"
# ... (rest of case block identical to原)

ACTION="${1:-}"
case "$ACTION" in
    ""|"help"|"-h"|"--help")
        usage
        ;;
    "install")
        shift
        SITE=""
        PWA_OVERRIDE=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --with-pwa)
                    PWA_OVERRIDE="true"
                    shift
                    ;;
                --no-pwa)
                    PWA_OVERRIDE="false"
                    shift
                    ;;
                --help|-h)
                    usage
                    exit 0
                    ;;
                -*)
                    abort "未知参数: $1"
                    ;;
                *)
                    if [[ -z "$SITE" ]]; then
                        SITE="$1"
                    else
                        abort "检测到多余参数: $1"
                    fi
                    shift
                    ;;
            esac
        done
        if [[ -z "$SITE" ]]; then
            abort "请提供站点名称，例如: saltgoat pwa install pwa"
        fi
        install_site "$SITE" "$PWA_OVERRIDE"
        ;;
    "status")
        shift
        SITE=""
        STATUS_JSON="false"
        STATUS_CHECK="false"
        STATUS_GRAPHQL="true"
        STATUS_REACT="true"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --json)
                    STATUS_JSON="true"
                    shift
                    ;;
                --check)
                    STATUS_CHECK="true"
                    shift
                    ;;
                --no-graphql)
                    STATUS_GRAPHQL="false"
                    shift
                    ;;
                --no-react)
                    STATUS_REACT="false"
                    shift
                    ;;
                --help|-h)
                    usage
                    exit 0
                    ;;
                -*)
                    abort "未知参数: $1"
                    ;;
                *)
                    if [[ -z "$SITE" ]]; then
                        SITE="$1"
                    else
                        abort "检测到多余参数: $1"
                    fi
                    shift
                    ;;
            esac
        done
        if [[ -z "$SITE" ]]; then
            abort "请提供站点名称，例如: saltgoat pwa status pwa"
        fi
        status_site "$SITE" "$STATUS_JSON" "$STATUS_CHECK" "$STATUS_GRAPHQL" "$STATUS_REACT"
        ;;
    "doctor")
        shift
        SITE=""
        DO_GRAPHQL="true"
        DO_REACT="true"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --no-graphql)
                    DO_GRAPHQL="false"
                    shift
                    ;;
                --no-react)
                    DO_REACT="false"
                    shift
                    ;;
                --help|-h)
                    usage
                    exit 0
                    ;;
                -*)
                    abort "未知参数: $1"
                    ;;
                *)
                    if [[ -z "$SITE" ]]; then
                        SITE="$1"
                    else
                        abort "检测到多余参数: $1"
                    fi
                    shift
                    ;;
            esac
        done
        if [[ -z "$SITE" ]]; then
            abort "请提供站点名称，例如: saltgoat pwa doctor pwa"
        fi
        doctor_site "$SITE" "$DO_GRAPHQL" "$DO_REACT"
        ;;
    "sync-content")
        shift
        SITE=""
        DO_PULL="false"
        DO_REBUILD="false"
        SKIP_CMS="false"
        USE_ALT_HOME="false"
        CUSTOM_HOME_IDENTIFIER=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --pull)
                    DO_PULL="true"
                    shift
                    ;;
                --rebuild)
                    DO_REBUILD="true"
                    shift
                    ;;
                --skip-cms)
                    SKIP_CMS="true"
                    shift
                    ;;
                --no-pb)
                    USE_ALT_HOME="true"
                    shift
                    ;;
                --home-id)
                    if [[ -z "${2:-}" ]]; then
                        abort "--home-id 需要一个参数"
                    fi
                    CUSTOM_HOME_IDENTIFIER="$2"
                    shift 2
                    ;;
                --help|-h)
                    usage
                    exit 0
                    ;;
                -*)
                    abort "未知参数: $1"
                    ;;
                *)
                    if [[ -z "$SITE" ]]; then
                        SITE="$1"
                    else
                        abort "检测到多余参数: $1"
                    fi
                    shift
                    ;;
            esac
        done
        if [[ -z "$SITE" ]]; then
            abort "请提供站点名称，例如: saltgoat pwa sync-content pwa"
        fi
        sync_site_content "$SITE" "$DO_PULL" "$DO_REBUILD" "$SKIP_CMS" "$USE_ALT_HOME" "$CUSTOM_HOME_IDENTIFIER"
        ;;
    "remove")
        shift
        SITE=""
        PURGE="false"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --purge)
                    PURGE="true"
                    shift
                    ;;
                --help|-h)
                    usage
                    exit 0
                    ;;
                -*)
                    abort "未知参数: $1"
                    ;;
                *)
                    if [[ -z "$SITE" ]]; then
                        SITE="$1"
                    else
                        abort "检测到多余参数: $1"
                    fi
                    shift
                    ;;
            esac
        done
        if [[ -z "$SITE" ]]; then
            abort "请提供站点名称，例如: saltgoat pwa remove pwa"
        fi
        remove_site "$SITE" "$PURGE"
        ;;
    *)
        abort "未知操作: ${ACTION}。支持: install, status, sync-content, remove, help"
        ;;
esac

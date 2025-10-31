#!/bin/bash
# Magento 工具集
# modules/magetools/magetools.sh

: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# 模块化拆分后的辅助脚本列表
MAGETOOLS_HELPER_FILES=(
    "install-tools.sh"
    "templates.sh"
    "deploy-maintenance.sh"
    "permissions.sh"
)

magetools_load_helpers() {
    if [[ -n "${MAGETOOLS_HELPERS_LOADED:-}" ]]; then
        return
    fi

    local helper_dir="${SCRIPT_DIR}/modules/magetools"
    for helper in "${MAGETOOLS_HELPER_FILES[@]}"; do
        local helper_path="${helper_dir}/${helper}"
        if [[ -f "$helper_path" ]]; then
            # shellcheck disable=SC1090
            source "$helper_path"
        else
            log_warning "magetools helper 缺失: $helper_path"
        fi
    done

    MAGETOOLS_HELPERS_LOADED=1
}

# Magento 工具主函数
magetools_handler() {
    magetools_load_helpers

    case "$1" in
        "install")
            install_magento_tool "$2"
            ;;
        "template")
            case "$2" in
                "create")
                    create_magento_template "$3"
                    ;;
                "list")
                    list_magento_templates
                    ;;
                *)
                    log_error "未知的模板操作: $2"
                    log_info "支持: create, list"
                    exit 1
                    ;;
            esac
            ;;
        "deploy")
            deploy_magento
            ;;
        "backup")
            case "$2" in
                "mysql")
                    shift 2
                    log_warning "命令已更名为 'saltgoat magetools xtrabackup mysql ...'，当前调用将继续执行但建议尽快迁移"
                    MAGETOOLS_MYSQL_BACKUP_ALIAS=backup "${SCRIPT_DIR}/modules/magetools/mysql-backup.sh" "$@"
                    ;;
                "restic")
                    shift 2
                    "${SCRIPT_DIR}/modules/magetools/backup-restic.sh" "$@"
                    ;;
                ""|"magento")
                    backup_magento
                    ;;
                *)
                    log_error "未知的备份类型: $2"
                    log_info "支持: mysql, restic, magento"
                    exit 1
                    ;;
            esac
            ;;
        "xtrabackup")
            case "$2" in
                "mysql")
                    shift 2
                    "${SCRIPT_DIR}/modules/magetools/mysql-backup.sh" "$@"
                    ;;
                *)
                    log_error "未知的 xtrabackup 操作: ${2:-<empty>}"
                    log_info "支持: mysql"
                    exit 1
                    ;;
            esac
            ;;
        "mysql")
            shift
            "${SCRIPT_DIR}/modules/magetools/mysql-manage.sh" "$@"
            ;;
        "restore")
            restore_magento "$2"
            ;;
        "performance")
            analyze_magento_performance
            ;;
        "security")
            scan_magento_security
            ;;
        "update")
            update_magento
            ;;
        "permissions")
            case "$2" in
                "fix")
                    fix_magento_permissions "$3"
                    ;;
                "check")
                    check_magento_permissions "$3"
                    ;;
                "reset")
                    reset_magento_permissions "$3"
                    ;;
                *)
                    log_error "未知的权限操作: $2"
                    log_info "支持: fix, check, reset"
                    exit 1
                    ;;
            esac
            ;;
        "valkey-renew")
            # 调用 valkey-renew 脚本
            "${SCRIPT_DIR}/modules/magetools/valkey-renew.sh" "$2" "$3"
            ;;
        "valkey-setup")
            # 调用 valkey-setup 脚本 (Salt 原生版本)
            shift
            local forwarded=()
            for arg in "$@"; do
                [[ -z "$arg" ]] && continue
                forwarded+=("$arg")
            done
            "${SCRIPT_DIR}/modules/magetools/valkey-setup.sh" "${forwarded[@]}"
            ;;
        "valkey-check")
            shift
            "${SCRIPT_DIR}/modules/magetools/valkey-check.sh" "$@"
            ;;
        "rabbitmq")
            case "$2" in
                "all"|"smart")
                    # 调用 rabbitmq 脚本
                    sudo "${SCRIPT_DIR}/modules/magetools/rabbitmq.sh" "$2" "$3" "${4:-1}"
                    ;;
                "check")
                    # 检查 rabbitmq 状态
                    "${SCRIPT_DIR}/modules/magetools/rabbitmq-check.sh" "$3"
                    ;;
                *)
                    log_error "未知的 RabbitMQ 操作: $2"
                    log_info "支持的操作: all, smart, check"
                    exit 1
                    ;;
            esac
            ;;
        "rabbitmq-salt")
            # 使用 Salt 原生管理 RabbitMQ/消费者
            shift
            "${SCRIPT_DIR}/modules/magetools/rabbitmq-salt.sh" "$@"
            ;;
        "api")
            case "$2" in
                "watch")
                    shift 2
                    "${SCRIPT_DIR}/modules/magetools/magento_api_watch.py" "$@"
                    ;;
                *)
                    log_error "未知的 API 操作: ${2:-<empty>}"
                    log_info "支持: api watch --site <name> [--kinds orders,customers] [--auth-mode auto|bearer|oauth1]"
                    exit 1
                    ;;
            esac
            ;;
        "stats")
            shift
            "${SCRIPT_DIR}/modules/magetools/magento_summary.py" "$@"
            ;;
        "opensearch")
            # 调用 opensearch 认证配置脚本
            "${SCRIPT_DIR}/modules/magetools/opensearch-auth.sh" "$2"
            ;;
        "maintenance")
            shift
            "${SCRIPT_DIR}/modules/magetools/maintenance.sh" "$@"
            ;;
        "cron")
            # 调用定时任务管理脚本
            "${SCRIPT_DIR}/modules/magetools/magento-cron.sh" "$2" "$3"
            ;;
        "salt-schedule")
            # 调用 Salt Schedule 管理脚本
            "${SCRIPT_DIR}/modules/magetools/magento-salt-schedule.sh" "$2" "$3"
            ;;
        "pwa")
            shift
            log_warning "命令已迁移至 'saltgoat pwa'，当前调用将继续执行但建议尽快使用新命名空间"
            require_module "pwa"
            pwa_handler "$@"
            ;;
        "varnish")
            shift
            "${SCRIPT_DIR}/modules/magetools/varnish.sh" "$@"
            ;;
        "migrate")
            local site_path="$2"
            local site_name="$3"
            local action="${4:-detect}"

            if [[ -z "$site_path" || -z "$site_name" ]]; then
                log_error "用法: saltgoat magetools migrate <site_path> <site_name> [action]"
                log_info "操作: detect (检测), fix (修复)"
                log_info "示例: saltgoat magetools migrate /var/www/tank tank detect"
                exit 1
            fi

            "${SCRIPT_DIR}/modules/magetools/migrate-detect.sh" "$site_path" "$site_name" "$action"
            ;;
        "help"|"--help"|"-h")
            show_magetools_help
            ;;
        *)
            log_error "未知的 magetools 子命令: ${1:-<empty>}"
            show_magetools_help
            exit 1
            ;;
    esac
}

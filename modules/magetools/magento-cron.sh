#!/bin/bash
# Magento 2 定时维护任务管理
# modules/magetools/magento-cron.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"

# 配置参数
SITE_NAME="${1:-tank}"
ACTION="${2:-status}"

sync_salt_modules() {
    if command -v salt-call >/dev/null 2>&1; then
        sudo salt-call --local saltutil.sync_modules >/dev/null 2>&1 || true
    fi
}

# 显示帮助信息
show_help() {
    echo "Magento 2 定时维护任务管理"
    echo ""
    echo "用法: $0 <site_name> <action>"
    echo ""
    echo "参数:"
    echo "  site_name    站点名称 (默认: tank)"
    echo "  action       操作类型"
    echo ""
    echo "操作类型:"
    echo "  status        - 查看当前定时任务状态"
    echo "  install       - 安装定时维护任务"
    echo "  uninstall     - 卸载定时维护任务"
    echo "  test          - 测试定时任务"
    echo "  logs          - 查看定时任务日志"
    echo ""
    echo "示例:"
    echo "  $0 tank status"
    echo "  $0 tank install"
    echo "  $0 tank test"
}

# 检查参数
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
    exit 0
fi

if [[ ! -d "/var/www/$SITE_NAME" ]]; then
    log_error "站点目录不存在: /var/www/$SITE_NAME"
    exit 1
fi

log_highlight "Magento 2 定时维护任务管理: $SITE_NAME"
log_info "操作: $ACTION"
echo ""

# 检查当前定时任务状态
check_cron_status() {
    log_info "检查当前定时任务状态..."
    echo ""
    
    local schedule_output
    schedule_output=$(salt-call --local schedule.list --out=yaml 2>/dev/null)
    
    log_info "Salt Schedule 任务:"
    if echo "$schedule_output" | grep -q "magento"; then
        log_success "[SUCCESS] 已检测到 Magento 相关任务"
        echo "$schedule_output" | grep "magento-" -A3
    else
        log_warning "[WARNING] 未发现 Magento 计划任务"
        log_info "使用 'saltgoat magetools cron $SITE_NAME install' 安装 Salt Schedule 任务"
    fi
    
    if [[ -f /etc/cron.d/magento-maintenance ]]; then
        echo ""
        log_info "检测到系统 Cron 计划 (/etc/cron.d/magento-maintenance):"
        cat /etc/cron.d/magento-maintenance
    fi
    
    echo ""
    log_info "salt-minion 服务状态:"
    if systemctl is-active --quiet salt-minion; then
        log_success "[SUCCESS] salt-minion 正在运行"
    else
        log_error "[ERROR] salt-minion 未运行，Salt Schedule 将无法执行"
    fi
}

# 安装定时维护任务
install_cron_tasks() {
    log_info "通过 Salt Schedule 安装定时维护任务..."
    
    sync_salt_modules
    local install_output
    install_output=$(sudo salt-call --local saltgoat.magento_schedule_install site="$SITE_NAME" 2>&1)
    echo "$install_output"

    if echo "$install_output" | grep -q "'mode': 'cron'"; then
        log_warning "[WARNING] salt-minion 服务不可用，已回退到系统 Cron 计划 (/etc/cron.d/magento-maintenance)"
    else
        log_success "[SUCCESS] Salt Schedule 已配置 Magento 维护任务"
    fi

    log_info "使用 'saltgoat magetools cron $SITE_NAME status' 查看详情"
}

# 卸载定时维护任务
uninstall_cron_tasks() {
    log_info "移除 SaltGoat 定时维护计划..."

    sync_salt_modules
    local uninstall_output
    uninstall_output=$(sudo salt-call --local saltgoat.magento_schedule_uninstall site="$SITE_NAME" 2>&1)
    echo "$uninstall_output"

    if echo "$uninstall_output" | grep -q "cron_removed': True"; then
        log_info "[INFO] 已删除系统 Cron 计划: /etc/cron.d/magento-maintenance"
    fi

    log_success "[SUCCESS] 定时维护计划已移除"
}

# 测试定时任务
test_cron_tasks() {
    log_info "测试定时任务..."
    echo ""
    
    if [[ -f /etc/cron.d/magento-maintenance ]]; then
        log_warning "当前使用系统 Cron 管理维护计划，Salt Schedule 测试跳过"
        log_info "可手动执行: saltgoat magetools maintenance $SITE_NAME daily"
        return 0
    fi

    sync_salt_modules
    local test_jobs=("magento-cron" "magento-daily-maintenance")
    for job in "${test_jobs[@]}"; do
        log_info "触发 Salt Schedule 任务: $job"
        if salt-call --local schedule.run_job "$job" >/dev/null 2>&1; then
            log_success "[SUCCESS] 任务 $job 触发成功"
        else
            log_error "[ERROR] 任务 $job 触发失败"
        fi
        echo ""
    done
    
    log_info "触发健康检查任务:"
    if salt-call --local schedule.run_job magento-health-check >/dev/null 2>&1; then
        log_success "[SUCCESS] 健康检查任务触发成功"
    else
        log_error "[ERROR] 健康检查任务触发失败"
    fi
}

# 查看定时任务日志
view_cron_logs() {
    log_info "查看定时任务日志..."
    echo ""
    
    # 查看维护日志
    log_info "1. 维护任务日志:"
    if [[ -f "/var/log/magento-maintenance.log" ]]; then
        log_info "最近10行维护日志:"
        tail -10 /var/log/magento-maintenance.log
    else
        log_warning "[WARNING] 维护日志文件不存在"
    fi
    echo ""
    
    # 查看健康检查日志
    log_info "2. 健康检查日志:"
    if [[ -f "/var/log/magento-health.log" ]]; then
        log_info "最近10行健康检查日志:"
        tail -10 /var/log/magento-health.log
    else
        log_warning "[WARNING] 健康检查日志文件不存在"
    fi
    echo ""
    
    # 查看系统 cron 日志
    log_info "3. 系统 Cron 日志:"
    if [[ -f "/var/log/cron.log" ]]; then
        log_info "最近5行系统 cron 日志:"
        tail -5 /var/log/cron.log | grep -i magento || log_info "未找到 Magento 相关日志"
    else
        log_warning "[WARNING] 系统 cron 日志文件不存在"
    fi
}

# 主程序
case "$ACTION" in
    "status")
        check_cron_status
        ;;
    "install")
        install_cron_tasks
        ;;
    "uninstall")
        uninstall_cron_tasks
        ;;
    "test")
        test_cron_tasks
        ;;
    "logs")
        view_cron_logs
        ;;
    *)
        log_error "未知的操作: $ACTION"
        echo ""
        show_help
        exit 1
        ;;
esac

#!/bin/bash
# Magento 2 Salt Schedule 管理
# modules/magetools/magento-salt-schedule.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"

# 配置参数
SITE_NAME="${1:-tank}"
ACTION="${2:-status}"

# 显示帮助信息
show_help() {
    echo "Magento 2 Salt Schedule 管理"
    echo ""
    echo "用法: $0 <site_name> <action>"
    echo ""
    echo "参数:"
    echo "  site_name    站点名称 (默认: tank)"
    echo "  action       操作类型"
    echo ""
    echo "操作类型:"
    echo "  status        - 查看当前 Salt Schedule 状态"
    echo "  install       - 安装 Salt Schedule 任务"
    echo "  uninstall     - 卸载 Salt Schedule 任务"
    echo "  test          - 测试 Salt Schedule 任务"
    echo "  logs          - 查看 Salt Schedule 日志"
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

log_highlight "Magento 2 Salt Schedule 管理: $SITE_NAME"
log_info "操作: $ACTION"
echo ""

# 检查当前 Salt Schedule 状态
check_salt_schedule_status() {
    log_info "检查当前 Salt Schedule 状态..."
    echo ""
    
    # 检查 Magento 维护脚本
    log_info "1. Magento 维护脚本:"
    if [[ -f "/usr/local/bin/magento-maintenance-salt" ]]; then
        log_success "[SUCCESS] Magento 维护脚本已安装"
    else
        log_warning "[WARNING] Magento 维护脚本未安装"
    fi
    echo ""
    
    # 检查定时任务配置
    log_info "2. 定时任务配置:"
    if [[ -f "/etc/cron.d/magento-maintenance" ]]; then
        log_success "[SUCCESS] 定时任务配置文件存在"
        cat /etc/cron.d/magento-maintenance
    else
        log_warning "[WARNING] 定时任务配置文件不存在"
    fi
    echo ""
    
    # 检查 Cron 服务
    log_info "3. Cron 服务状态:"
    if systemctl is-active --quiet cron; then
        log_success "[SUCCESS] Cron 服务运行正常"
    else
        log_error "[ERROR] Cron 服务未运行"
    fi
    echo ""
    
    # 检查日志文件
    log_info "4. 日志文件:"
    if [[ -f "/var/log/magento-maintenance.log" ]]; then
        log_success "[SUCCESS] 维护日志文件存在"
    else
        log_warning "[WARNING] 维护日志文件不存在"
    fi
    
    if [[ -f "/var/log/magento-health.log" ]]; then
        log_success "[SUCCESS] 健康检查日志文件存在"
    else
        log_warning "[WARNING] 健康检查日志文件不存在"
    fi
}

# 安装 Salt Schedule 任务
install_salt_schedule() {
    log_info "安装 Salt Schedule 任务..."
    
    # 应用 Salt Schedule 状态
    if sudo salt-call state.apply optional.magento-schedule pillar='{"site_name": "'$SITE_NAME'"}'; then
        log_success "[SUCCESS] Salt Schedule 任务安装完成"
    else
        log_error "[ERROR] Salt Schedule 任务安装失败"
        return 1
    fi
    
    log_success "[SUCCESS] Salt Schedule 任务安装完成"
}

# 卸载 Salt Schedule 任务
uninstall_salt_schedule() {
    log_info "卸载 Salt Schedule 任务..."
    
    # 删除定时任务配置文件
    if [[ -f "/etc/cron.d/magento-maintenance" ]]; then
        sudo rm -f /etc/cron.d/magento-maintenance
        log_success "[SUCCESS] 删除定时任务配置文件"
    fi
    
    # 删除维护脚本
    if [[ -f "/usr/local/bin/magento-maintenance-salt" ]]; then
        sudo rm -f /usr/local/bin/magento-maintenance-salt
        log_success "[SUCCESS] 删除维护脚本"
    fi
    
    # 重启 cron 服务
    if systemctl restart cron; then
        log_success "[SUCCESS] Cron 服务重启完成"
    else
        log_warning "[WARNING] Cron 服务重启失败"
    fi
    
    log_success "[SUCCESS] Salt Schedule 任务卸载完成"
}

# 测试 Salt Schedule 任务
test_salt_schedule() {
    log_info "测试 Salt Schedule 任务..."
    echo ""
    
    # 测试维护脚本
    log_info "1. 测试维护脚本:"
    if [[ -f "/usr/local/bin/magento-maintenance-salt" ]]; then
        if /usr/local/bin/magento-maintenance-salt "$SITE_NAME" health; then
            log_success "[SUCCESS] 维护脚本测试通过"
        else
            log_error "[ERROR] 维护脚本测试失败"
        fi
    else
        log_error "[ERROR] 维护脚本不存在"
    fi
    echo ""
    
    # 测试定时任务配置
    log_info "2. 测试定时任务配置:"
    if [[ -f "/etc/cron.d/magento-maintenance" ]]; then
        log_success "[SUCCESS] 定时任务配置文件存在"
        log_info "配置文件内容:"
        cat /etc/cron.d/magento-maintenance
    else
        log_error "[ERROR] 定时任务配置文件不存在"
    fi
    echo ""
    
    # 测试权限
    log_info "3. 测试权限:"
    if sudo -u www-data test -r "/var/www/$SITE_NAME/bin/magento"; then
        log_success "[SUCCESS] 权限测试通过"
    else
        log_error "[ERROR] 权限测试失败"
    fi
}

# 查看 Salt Schedule 日志
view_salt_schedule_logs() {
    log_info "查看 Salt Schedule 日志..."
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
    
    # 查看 Cron 日志
    log_info "3. Cron 日志:"
    if [[ -f "/var/log/cron.log" ]]; then
        log_info "最近5行 Cron 日志:"
        tail -5 /var/log/cron.log | grep -i magento || log_info "未找到 Magento 相关日志"
    else
        log_warning "[WARNING] Cron 日志文件不存在"
    fi
}

# 主程序
case "$ACTION" in
    "status")
        check_salt_schedule_status
        ;;
    "install")
        install_salt_schedule
        ;;
    "uninstall")
        uninstall_salt_schedule
        ;;
    "test")
        test_salt_schedule
        ;;
    "logs")
        view_salt_schedule_logs
        ;;
    *)
        log_error "未知的操作: $ACTION"
        echo ""
        show_help
        exit 1
        ;;
esac

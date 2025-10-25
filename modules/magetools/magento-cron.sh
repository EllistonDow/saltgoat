#!/bin/bash
# Magento 2 定时维护任务管理
# modules/magetools/magento-cron.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"

# 配置参数
SITE_NAME="${1:-tank}"
ACTION="${2:-status}"

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
    
    # 检查 Magento cron 任务
    log_info "1. Magento Cron 任务:"
    if crontab -u www-data -l 2>/dev/null | grep -q "magento cron:run"; then
        log_success "[SUCCESS] Magento cron 任务已安装"
        crontab -u www-data -l | grep "magento cron:run"
    else
        log_warning "[WARNING] Magento cron 任务未安装"
    fi
    echo ""
    
    # 检查维护任务
    log_info "2. 维护任务:"
    if crontab -u www-data -l 2>/dev/null | grep -q "magento-maintenance"; then
        log_success "[SUCCESS] 维护任务已安装"
        crontab -u www-data -l | grep "magento-maintenance"
    else
        log_warning "[WARNING] 维护任务未安装"
    fi
    echo ""
    
    # 检查系统 cron 服务
    log_info "3. Cron 服务状态:"
    if systemctl is-active --quiet cron; then
        log_success "[SUCCESS] Cron 服务运行正常"
    else
        log_error "[ERROR] Cron 服务未运行"
    fi
}

# 安装定时维护任务
install_cron_tasks() {
    log_info "安装定时维护任务..."
    
    # 创建临时 crontab 文件
    local temp_cron="/tmp/magento_cron_${SITE_NAME}_$$"
    
    # 获取现有的 crontab
    crontab -u www-data -l 2>/dev/null > "$temp_cron"
    
    # 添加 Magento cron 任务（每5分钟）
    if ! grep -q "magento cron:run" "$temp_cron"; then
        echo "# Magento cron 任务 - 每5分钟执行" >> "$temp_cron"
        echo "*/5 * * * * cd /var/www/$SITE_NAME && sudo -u www-data php bin/magento cron:run" >> "$temp_cron"
        log_success "[SUCCESS] 添加 Magento cron 任务"
    else
        log_info "[INFO] Magento cron 任务已存在"
    fi
    
    # 添加每日维护任务（每天凌晨2点）
    if ! grep -q "magento-maintenance.*daily" "$temp_cron"; then
        echo "# 每日维护任务 - 每天凌晨2点执行" >> "$temp_cron"
        echo "0 2 * * * $SCRIPT_DIR/modules/magetools/magento-maintenance.sh $SITE_NAME daily >> /var/log/magento-maintenance.log 2>&1" >> "$temp_cron"
        log_success "[SUCCESS] 添加每日维护任务"
    else
        log_info "[INFO] 每日维护任务已存在"
    fi
    
    # 添加每周维护任务（每周日凌晨3点）
    if ! grep -q "magento-maintenance.*weekly" "$temp_cron"; then
        echo "# 每周维护任务 - 每周日凌晨3点执行" >> "$temp_cron"
        echo "0 3 * * 0 $SCRIPT_DIR/modules/magetools/magento-maintenance.sh $SITE_NAME weekly >> /var/log/magento-maintenance.log 2>&1" >> "$temp_cron"
        log_success "[SUCCESS] 添加每周维护任务"
    else
        log_info "[INFO] 每周维护任务已存在"
    fi
    
    # 添加每月维护任务（每月1日凌晨4点）
    if ! grep -q "magento-maintenance.*monthly" "$temp_cron"; then
        echo "# 每月维护任务 - 每月1日凌晨4点执行" >> "$temp_cron"
        echo "0 4 1 * * $SCRIPT_DIR/modules/magetools/magento-maintenance.sh $SITE_NAME monthly >> /var/log/magento-maintenance.log 2>&1" >> "$temp_cron"
        log_success "[SUCCESS] 添加每月维护任务"
    else
        log_info "[INFO] 每月维护任务已存在"
    fi
    
    # 添加健康检查任务（每小时执行）
    if ! grep -q "magento-maintenance.*health" "$temp_cron"; then
        echo "# 健康检查任务 - 每小时执行" >> "$temp_cron"
        echo "0 * * * * $SCRIPT_DIR/modules/magetools/magento-maintenance.sh $SITE_NAME health >> /var/log/magento-health.log 2>&1" >> "$temp_cron"
        log_success "[SUCCESS] 添加健康检查任务"
    else
        log_info "[INFO] 健康检查任务已存在"
    fi
    
    # 安装 crontab
    if crontab -u www-data "$temp_cron"; then
        log_success "[SUCCESS] 定时任务安装完成"
    else
        log_error "[ERROR] 定时任务安装失败"
        rm -f "$temp_cron"
        return 1
    fi
    
    # 清理临时文件
    rm -f "$temp_cron"
    
    # 创建日志文件
    sudo touch /var/log/magento-maintenance.log /var/log/magento-health.log
    sudo chown www-data:www-data /var/log/magento-maintenance.log /var/log/magento-health.log
    sudo chmod 644 /var/log/magento-maintenance.log /var/log/magento-health.log
    
    log_success "[SUCCESS] 定时维护任务安装完成"
}

# 卸载定时维护任务
uninstall_cron_tasks() {
    log_info "卸载定时维护任务..."
    
    # 创建临时 crontab 文件
    local temp_cron="/tmp/magento_cron_${SITE_NAME}_$$"
    
    # 获取现有的 crontab，过滤掉 Magento 相关任务
    crontab -u www-data -l 2>/dev/null | grep -v "magento cron:run" | grep -v "magento-maintenance" > "$temp_cron"
    
    # 安装清理后的 crontab
    if crontab -u www-data "$temp_cron"; then
        log_success "[SUCCESS] 定时任务卸载完成"
    else
        log_error "[ERROR] 定时任务卸载失败"
        rm -f "$temp_cron"
        return 1
    fi
    
    # 清理临时文件
    rm -f "$temp_cron"
    
    log_success "[SUCCESS] 定时维护任务卸载完成"
}

# 测试定时任务
test_cron_tasks() {
    log_info "测试定时任务..."
    echo ""
    
    # 测试 Magento cron
    log_info "1. 测试 Magento cron 任务:"
    if cd "/var/www/$SITE_NAME" && sudo -u www-data php bin/magento cron:run; then
        log_success "[SUCCESS] Magento cron 任务测试通过"
    else
        log_error "[ERROR] Magento cron 任务测试失败"
    fi
    echo ""
    
    # 测试维护任务
    log_info "2. 测试维护任务:"
    if "$SCRIPT_DIR/modules/magetools/magento-maintenance.sh" "$SITE_NAME" health; then
        log_success "[SUCCESS] 维护任务测试通过"
    else
        log_error "[ERROR] 维护任务测试失败"
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

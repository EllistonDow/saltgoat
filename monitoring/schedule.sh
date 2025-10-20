#!/bin/bash
# 定时任务模块
# monitoring/schedule.sh

# 定时任务处理函数
schedule_handler() {
    case "$2" in
        "enable")
            log_highlight "启用 SaltGoat 定时任务..."
            schedule_enable
            ;;
        "disable")
            log_highlight "禁用 SaltGoat 定时任务..."
            schedule_disable
            ;;
        "status")
            log_highlight "查看定时任务状态..."
            schedule_status
            ;;
        "list")
            log_highlight "列出所有定时任务..."
            schedule_list
            ;;
        "test")
            log_highlight "测试定时任务配置..."
            schedule_test
            ;;
        *)
            log_error "未知的 Schedule 操作: $2"
            log_info "支持: enable, disable, status, list, test"
            exit 1
            ;;
    esac
}

# 启用定时任务
schedule_enable() {
    log_info "启用 SaltGoat 定时任务..."
    
    # 创建系统级定时任务
    echo "# SaltGoat 定时任务配置" | sudo tee /etc/cron.d/saltgoat-tasks > /dev/null
    echo "# 内存监控 - 每5分钟" | sudo tee -a /etc/cron.d/saltgoat-tasks > /dev/null
    echo "*/5 * * * * root saltgoat memory monitor" | sudo tee -a /etc/cron.d/saltgoat-tasks > /dev/null
    echo "" | sudo tee -a /etc/cron.d/saltgoat-tasks > /dev/null
    
    echo "# 系统更新检查 - 每周日凌晨3点" | sudo tee -a /etc/cron.d/saltgoat-tasks > /dev/null
    echo "0 3 * * 0 root saltgoat system update-check" | sudo tee -a /etc/cron.d/saltgoat-tasks > /dev/null
    echo "" | sudo tee -a /etc/cron.d/saltgoat-tasks > /dev/null
    
    echo "# 日志清理 - 每周日凌晨1点" | sudo tee -a /etc/cron.d/saltgoat-tasks > /dev/null
    echo "0 1 * * 0 root find /var/log -name \"*.log\" -mtime +7 -delete" | sudo tee -a /etc/cron.d/saltgoat-tasks > /dev/null
    echo "" | sudo tee -a /etc/cron.d/saltgoat-tasks > /dev/null
    
    echo "# 服务健康检查 - 每10分钟" | sudo tee -a /etc/cron.d/saltgoat-tasks > /dev/null
    echo "*/10 * * * * root saltgoat system health-check" | sudo tee -a /etc/cron.d/saltgoat-tasks > /dev/null
    
    log_success "SaltGoat 定时任务已启用"
    log_info "已创建 /etc/cron.d/saltgoat-tasks"
}

# 禁用定时任务
schedule_disable() {
    log_info "禁用 SaltGoat 定时任务..."
    
    # 删除系统级定时任务文件
    if [[ -f /etc/cron.d/saltgoat-tasks ]]; then
        sudo rm /etc/cron.d/saltgoat-tasks
        log_success "已删除 /etc/cron.d/saltgoat-tasks"
    else
        log_info "SaltGoat 定时任务文件不存在"
    fi
    
    log_success "SaltGoat 定时任务已禁用"
}

# 查看定时任务状态
schedule_status() {
    log_info "查看定时任务状态..."
    
    if [[ -f /etc/cron.d/saltgoat-tasks ]]; then
        echo "SaltGoat 定时任务状态: 已启用"
        echo "配置文件: /etc/cron.d/saltgoat-tasks"
        echo ""
        echo "任务列表:"
        grep -v "^#" /etc/cron.d/saltgoat-tasks | grep -v "^$" | while read line; do
            if [[ -n "$line" ]]; then
                echo "  $line"
            fi
        done
    else
        echo "SaltGoat 定时任务状态: 未启用"
        echo "运行 'saltgoat schedule enable' 来启用定时任务"
    fi
}

# 列出所有定时任务
schedule_list() {
    log_info "系统定时任务 (crontab):"
    echo "=========================================="
    
    # 显示 root 用户的 cron 任务
    if sudo crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$"; then
        echo "Root 用户定时任务:"
        sudo crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$"
    else
        echo "Root 用户无定时任务"
    fi
    
    echo ""
    echo "当前用户定时任务:"
    if crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$"; then
        crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$"
    else
        echo "当前用户无定时任务"
    fi
    
    echo ""
    echo "系统级定时任务 (/etc/cron.d/):"
    if [[ -d /etc/cron.d ]]; then
        for file in /etc/cron.d/*; do
            if [[ -f "$file" ]]; then
                echo "文件: $(basename "$file")"
                grep -v "^#" "$file" | grep -v "^$" | sed 's/^/  /'
                echo ""
            fi
        done
    fi
    
    echo ""
    log_info "Salt Schedule 状态:"
    salt-call --local schedule.list
}

# 测试定时任务配置
schedule_test() {
    log_info "测试内存监控..."
    memory_monitor
    echo
    
    log_info "测试服务状态..."
    echo "Nginx 状态:"
    salt-call --local service.status nginx
    echo "MySQL 状态:"
    salt-call --local service.status mysql
    echo "PHP-FPM 状态:"
    salt-call --local service.status php8.3-fpm
    echo "Valkey 状态:"
    salt-call --local service.status valkey
    echo "OpenSearch 状态:"
    salt-call --local service.status opensearch
    echo "RabbitMQ 状态:"
    salt-call --local service.status rabbitmq
    echo
    
    log_info "测试磁盘使用..."
    salt-call --local disk.usage
    echo
    
    log_success "定时任务配置测试完成"
}

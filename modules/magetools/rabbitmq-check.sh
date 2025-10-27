#!/bin/bash
# RabbitMQ 状态检查脚本
# modules/magetools/rabbitmq-check.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../lib/logger.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"

# 检查 RabbitMQ 消费者状态
check_rabbitmq_consumers() {
    local site_name="$1"
    
    if [[ -z "$site_name" ]]; then
        log_error "用法: $0 <site_name>"
        exit 1
    fi
    
    log_highlight "检查 RabbitMQ 消费者状态: $site_name"
    
    # 检查 RabbitMQ 服务状态
    log_info "检查 RabbitMQ 服务状态..."
    if systemctl is-active --quiet rabbitmq; then
        log_success "RabbitMQ 服务运行正常"
    else
        log_error "RabbitMQ 服务未运行"
        return 1
    fi
    
    # 检查消费者服务
    log_info "检查消费者服务状态..."
    local total_services=0
    local running_services=0
    local failed_services=0
    local restarting_services=0
    
    # 获取所有相关的消费者服务
    local services
    services=$(systemctl list-units --type=service | grep "magento-consumer-$site_name-" | awk '{print $1}')
    
    if [[ -z "$services" ]]; then
        log_warning "未找到 $site_name 的消费者服务"
        return 1
    fi
    
    echo ""
    log_info "消费者服务状态:"
    echo "----------------------------------------"
    
    for service in $services; do
        local status
        status=$(systemctl is-active "$service" 2>/dev/null)
        local restart_count
        restart_count=$(systemctl show "$service" --property=ExecMainStatus --value 2>/dev/null)
        
        total_services=$((total_services + 1))
        
        case "$status" in
            "active")
                running_services=$((running_services + 1))
                echo "[OK] $service: 运行中"
                ;;
            "failed")
                failed_services=$((failed_services + 1))
                echo "[FAIL] $service: 失败"
                ;;
            "activating")
                restarting_services=$((restarting_services + 1))
                echo "[RESTART] $service: 重启中"
                ;;
            *)
                echo "[WARN] $service: $status"
                ;;
        esac
        
        # 显示重启次数
        if [[ -n "$restart_count" && "$restart_count" != "0" ]]; then
            echo "   重启次数: $restart_count"
        fi
    done
    
    echo "----------------------------------------"
    echo "总服务数: $total_services"
    echo "运行中: $running_services"
    echo "失败: $failed_services"
    echo "重启中: $restarting_services"
    echo ""
    
    # 检查队列状态
    log_info "检查队列状态..."
    local vhost="/$site_name"
    local queue_output
    queue_output=$(sudo rabbitmqctl list_queues -p "$vhost" 2>/dev/null)
    
    if echo "$queue_output" | grep -q "Timeout"; then
        log_warning "RabbitMQ 连接超时"
    elif echo "$queue_output" | grep -q "Error"; then
        log_error "RabbitMQ 连接错误"
    else
        local queue_count
        queue_count=$(echo "$queue_output" | wc -l)
        if [[ "$queue_count" -gt 1 ]]; then
            log_success "发现 $((queue_count-1)) 个队列"
            echo "$queue_output" | head -10
        else
            log_info "暂无队列消息（这是正常的，队列只有在有消息时才会被创建）"
        fi
    fi
    
    # 显示失败服务的日志
    if [[ "$failed_services" -gt 0 ]]; then
        echo ""
        log_info "失败服务日志:"
        echo "----------------------------------------"
        for service in $services; do
            local status
            status=$(systemctl is-active "$service" 2>/dev/null)
            if [[ "$status" == "failed" ]]; then
                echo "服务: $service"
                sudo journalctl -u "$service" --no-pager -n 5
                echo ""
            fi
        done
    fi
    
    # 总结
    echo ""
    if [[ "$failed_services" -gt 0 ]]; then
        log_error "发现 $failed_services 个失败的服务"
        log_info "建议检查服务日志并修复配置"
    elif [[ "$restarting_services" -gt 0 ]]; then
        log_warning "发现 $restarting_services 个重启中的服务"
        log_info "这通常是正常的，服务在等待队列消息"
    else
        log_success "所有消费者服务状态正常"
    fi
}

# 主函数
main() {
    if [[ $# -lt 1 ]]; then
        log_error "用法: $0 <site_name>"
        echo ""
        echo "示例:"
        echo "  $0 tank"
        exit 1
    fi
    
    check_rabbitmq_consumers "$1"
}

# 如果直接运行脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

#!/bin/bash

# 检查 RabbitMQ 状态
check_rabbitmq_status() {
    local site_name="${1:-tank}"
    
    log_highlight "检查 RabbitMQ 消费者状态: $site_name"
    echo ""
    
    # 检查 RabbitMQ 服务状态
    log_info "1. RabbitMQ 服务状态:"
    if systemctl is-active --quiet rabbitmq; then
        log_success "RabbitMQ 服务正常运行"
    else
        log_error "RabbitMQ 服务未运行"
        return 1
    fi
    
    echo ""
    
    # 检查消费者服务状态
    log_info "2. 消费者服务状态:"
    local services
    services=$(systemctl list-units --type=service | grep "magento-consumer-$site_name" | awk '{print $1}' | sed 's/\.service$//')
    
    if [[ -z "$services" ]]; then
        log_warning "未找到 $site_name 的消费者服务"
        return 1
    fi
    
    local total_services=0
    local running_services=0
    local failed_services=0
    local restarting_services=0
    
    # 使用数组处理服务列表
    local service_array=()
    while IFS= read -r service; do
        if [[ -n "$service" ]]; then
            service_array+=("$service")
        fi
    done <<< "$services"
    
    for service in "${service_array[@]}"; do
        ((total_services++))
        local status
        status=$(systemctl is-active "$service" 2>/dev/null)
        local state
        state=$(systemctl show "$service" --property=ActiveState --value 2>/dev/null)
        local restart_count
        restart_count=$(systemctl show "$service" --property=NRestarts --value 2>/dev/null)
        
        case "$status" in
            "active")
                log_success "[SUCCESS] $service (运行中)"
                ((running_services++))
                ;;
            "failed")
                log_error "[ERROR] $service (失败)"
                ((failed_services++))
                ;;
            *)
                if [[ "$state" == "activating" ]]; then
                    log_warning "[WARNING] $service (重启中)"
                    ((restarting_services++))
                else
                    log_warning "[WARNING] $service ($status)"
                fi
                ;;
        esac
        
        # 显示重启次数
        if [[ "$restart_count" -gt 0 ]]; then
            echo "   重启次数: $restart_count"
        fi
    done
    
    echo ""
    log_info "3. 服务统计:"
    echo "   总服务数: $total_services"
    echo "   运行中: $running_services"
    echo "   失败: $failed_services"
    echo "   重启中: $restarting_services"
    
    echo ""
    
    # 检查队列状态
    log_info "4. RabbitMQ 队列状态:"
    local vhost="/$site_name"
    if sudo rabbitmqctl list_queues -p "$vhost" 2>/dev/null | grep -q "Timeout"; then
        log_warning "队列查询超时，可能 RabbitMQ 服务繁忙"
    else
        local queue_count
        queue_count=$(sudo rabbitmqctl list_queues -p "$vhost" 2>/dev/null | wc -l)
        if [[ "$queue_count" -gt 1 ]]; then
            log_success "发现 $((queue_count-1)) 个队列"
            sudo rabbitmqctl list_queues -p "$vhost" 2>/dev/null | head -10
        else
            log_info "暂无队列消息"
        fi
    fi
    
    echo ""
    
    # 检查最近日志
    log_info "5. 最近服务日志 (失败的服务):"
    local failed_services_list
    failed_services_list=$(systemctl list-units --type=service | grep "magento-consumer-$site_name" | grep "failed\|activating" | awk '{print $1}')
    
    if [[ -n "$failed_services_list" ]]; then
        while IFS= read -r service; do
            if [[ -n "$service" ]]; then
                echo ""
                log_warning "服务: $service"
                sudo journalctl -u "$service" --no-pager -n 5 2>/dev/null | tail -3
            fi
        done <<< "$failed_services_list"
    else
        log_success "所有服务运行正常"
    fi
    
    echo ""
    
    # 总结
    if [[ "$failed_services" -eq 0 && "$restarting_services" -eq 0 ]]; then
        log_success "[SUCCESS] RabbitMQ 消费者状态良好"
    elif [[ "$failed_services" -gt 0 ]]; then
        log_error "[ERROR] 发现 $failed_services 个失败的服务，需要检查"
    else
        log_warning "[WARNING] 有 $restarting_services 个服务在重启，请关注"
    fi
}

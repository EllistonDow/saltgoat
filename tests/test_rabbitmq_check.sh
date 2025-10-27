#!/bin/bash

# 测试 RabbitMQ 检查功能
# shellcheck disable=SC1091
source lib/logger.sh

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
    
    echo "Debug: services variable content:"
    echo "$services"
    echo "Debug: services count: $(echo "$services" | wc -l)"
    
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
    
    echo "Debug: service_array length: ${#service_array[@]}"
    
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
                log_success "[OK] $service (运行中)"
                ((running_services++))
                ;;
            "failed")
                log_error "[FAIL] $service (失败)"
                ((failed_services++))
                ;;
            *)
                if [[ "$state" == "activating" ]]; then
                    log_warning "[RESTART] $service (重启中)"
                    ((restarting_services++))
                else
                    log_warning "[WARN] $service ($status)"
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
}

check_rabbitmq_status "$1"

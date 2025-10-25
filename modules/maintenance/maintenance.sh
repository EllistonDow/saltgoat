#!/bin/bash
# 系统维护模块 - 全部使用 Salt 原生功能
# services/maintenance.sh

# 系统更新管理
maintenance_update() {
    case "$1" in
        "check")
            log_highlight "检查系统更新..."
            
            # 直接使用apt命令，避免Salt超时
            if sudo apt update >/dev/null 2>&1; then
                local updates
                updates=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || echo "0")
                
                if [[ "$updates" -gt 0 ]]; then
                    log_info "发现 $updates 个可更新的包"
                    
                    # 显示可更新的包
                    echo "可更新的包:"
                    echo "----------------------------------------"
                    apt list --upgradable 2>/dev/null | head -20
                    
                    if [[ "$updates" -gt 20 ]]; then
                        echo "... 还有 $((updates - 20)) 个包"
                    fi
                else
                    log_success "系统已是最新版本"
                fi
            else
                log_error "无法检查系统更新"
                exit 1
            fi
            ;;
        "upgrade")
            log_highlight "执行系统更新..."
            
            # 使用 Salt 原生功能更新包列表
            salt-call --local pkg.refresh_db 2>/dev/null
            
            # 使用 Salt 原生功能执行更新
            salt-call --local pkg.upgrade 2>/dev/null
            
            log_success "系统更新完成"
            ;;
        "dist-upgrade")
            log_highlight "执行系统升级..."
            
            # 使用 Salt 原生功能更新包列表
            salt-call --local pkg.refresh_db 2>/dev/null
            
            # 使用 Salt 原生功能执行升级
            salt-call --local pkg.upgrade dist_upgrade=True 2>/dev/null
            
            log_success "系统升级完成"
            ;;
        "autoremove")
            log_highlight "清理不需要的包..."
            
            # 使用 Salt 原生功能自动移除不需要的包
            salt-call --local pkg.autoremove 2>/dev/null
            
            log_success "包清理完成"
            ;;
        "clean")
            log_highlight "清理包缓存..."
            
            # 使用 Salt 原生功能清理包缓存
            salt-call --local pkg.clean_metadata 2>/dev/null
            
            log_success "包缓存清理完成"
            ;;
        *)
            log_error "未知的更新操作: $1"
            log_info "支持的操作: check, upgrade, dist-upgrade, autoremove, clean"
            exit 1
            ;;
    esac
}

# 服务管理 - 全部使用 Salt 原生功能
maintenance_service() {
    case "$1" in
        "restart")
            if [[ -z "$2" ]]; then
                log_error "用法: saltgoat maintenance service restart <service_name>"
                exit 1
            fi
            
            local service="$2"
            log_highlight "重启服务: $service"
            
            # 直接使用systemctl，避免Salt警告
            if sudo systemctl restart "$service" 2>/dev/null; then
                log_success "服务 $service 重启完成"
            else
                log_error "服务 $service 重启失败"
                exit 1
            fi
            ;;
        "start")
            if [[ -z "$2" ]]; then
                log_error "用法: saltgoat maintenance service start <service_name>"
                exit 1
            fi
            
            local service="$2"
            log_highlight "启动服务: $service"
            
            if sudo systemctl start "$service" 2>/dev/null; then
                log_success "服务 $service 启动完成"
            else
                log_error "服务 $service 启动失败"
                exit 1
            fi
            ;;
        "stop")
            if [[ -z "$2" ]]; then
                log_error "用法: saltgoat maintenance service stop <service_name>"
                exit 1
            fi
            
            local service="$2"
            log_highlight "停止服务: $service"
            
            if sudo systemctl stop "$service" 2>/dev/null; then
                log_success "服务 $service 停止完成"
            else
                log_error "服务 $service 停止失败"
                exit 1
            fi
            ;;
        "reload")
            if [[ -z "$2" ]]; then
                log_error "用法: saltgoat maintenance service reload <service_name>"
                exit 1
            fi
            
            local service="$2"
            log_highlight "重载服务配置: $service"
            
            if sudo systemctl reload "$service" 2>/dev/null; then
                log_success "服务 $service 配置重载完成"
            else
                log_error "服务 $service 配置重载失败"
                exit 1
            fi
            ;;
        "status")
            if [[ -z "$2" ]]; then
                log_error "用法: saltgoat maintenance service status <service_name>"
                exit 1
            fi
            
            local service="$2"
            log_highlight "检查服务状态: $service"
            
            local status
            status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
            if [[ "$status" == "active" ]]; then
                log_success "服务 $service 正在运行"
            else
                log_error "服务 $service 未运行"
                exit 1
            fi
            ;;
        *)
            log_error "未知的服务操作: $1"
            log_info "支持的操作: restart, start, stop, reload, status"
            exit 1
            ;;
    esac
}

# 系统清理 - 全部使用 Salt 原生功能
maintenance_cleanup() {
    case "$1" in
        "logs")
            log_highlight "清理系统日志..."
            
            # 使用 Salt 原生功能清理系统日志
            salt-call --local cmd.run "journalctl --vacuum-time=7d" 2>/dev/null
            
            # 使用 Salt 原生功能查找和删除旧日志文件
            salt-call --local file.find /var/log name="*.log.*" mtime=+7 2>/dev/null | while read -r file; do
                salt-call --local file.remove "$file" 2>/dev/null
            done
            
            salt-call --local file.find /var/log name="*.gz" mtime=+30 2>/dev/null | while read -r file; do
                salt-call --local file.remove "$file" 2>/dev/null
            done
            
            log_success "日志清理完成"
            ;;
        "temp")
            log_highlight "清理临时文件..."
            
            # 使用 Salt 原生功能查找和删除临时文件
            salt-call --local file.find /tmp type=f mtime=+7 2>/dev/null | while read -r file; do
                salt-call --local file.remove "$file" 2>/dev/null
            done
            
            salt-call --local file.find /var/tmp type=f mtime=+7 2>/dev/null | while read -r file; do
                salt-call --local file.remove "$file" 2>/dev/null
            done
            
            log_success "临时文件清理完成"
            ;;
        "cache")
            log_highlight "清理系统缓存..."
            
            # 使用 Salt 原生功能清理包缓存
            salt-call --local pkg.clean_metadata 2>/dev/null
            
            # 使用 Salt 原生功能清理用户缓存
            salt-call --local file.remove /home/*/.*cache/* 2>/dev/null || true
            
            log_success "缓存清理完成"
            ;;
        "all")
            log_highlight "执行完整系统清理..."
            
            maintenance_cleanup logs
            maintenance_cleanup temp
            maintenance_cleanup cache
            
            log_success "完整系统清理完成"
            ;;
        *)
            log_error "未知的清理操作: $1"
            log_info "支持的操作: logs, temp, cache, all"
            exit 1
            ;;
    esac
}

# 磁盘空间管理 - 全部使用 Salt 原生功能
maintenance_disk() {
    case "$1" in
        "usage")
            log_highlight "磁盘使用情况..."
            
            echo "磁盘使用统计:"
            echo "=========================================="
            salt-call --local disk.usage 2>/dev/null
            
            echo ""
            echo "目录大小统计 (前10个最大目录):"
            echo "----------------------------------------"
            du -h / 2>/dev/null | sort -h -r | head -10
            ;;
        "find-large")
            local size="${2:-100M}"
            log_highlight "查找大于 $size 的文件..."
            
            echo "大于 $size 的文件:"
            echo "=========================================="
            # 使用 Salt 原生功能查找大文件
            salt-call --local file.find / type=f size=+"$size" 2>/dev/null | head -20
            ;;
        "cleanup-large")
            local size="${2:-100M}"
            local days="${3:-30}"
            log_highlight "清理大于 $size 且超过 $days 天的文件..."
            
            # 使用 Salt 原生功能查找大文件
            local files
            files=$(salt-call --local file.find /tmp,/var/tmp type=f size=+"$size" mtime=+"$days" 2>/dev/null)
            
            if [[ -n "$files" ]]; then
                echo "找到以下文件:"
                echo "$files"
                echo ""
                log_info "正在删除这些文件..."
                
                # 使用 Salt 原生功能删除文件
                echo "$files" | while read -r file; do
                    salt-call --local file.remove "$file" 2>/dev/null
                done
                
                log_success "大文件清理完成"
            else
                log_info "没有找到符合条件的文件"
            fi
            ;;
        *)
            log_error "未知的磁盘操作: $1"
            log_info "支持的操作: usage, find-large [size], cleanup-large [size] [days]"
            exit 1
            ;;
    esac
}

# 系统健康检查 - 全部使用 Salt 原生功能
maintenance_health() {
    log_highlight "系统健康检查..."
    
    echo "系统健康状态:"
    echo "=========================================="
    
    # 检查磁盘空间
    echo "磁盘空间检查:"
    echo "----------------------------------------"
    local disk_usage
    disk_usage=$(salt-call --local disk.usage / 2>/dev/null | grep -o '[0-9]*%' | sed 's/%//' | head -1)
    
    if [[ "$disk_usage" -gt 90 ]]; then
        log_error "磁盘空间不足: ${disk_usage}%"
    elif [[ "$disk_usage" -gt 80 ]]; then
        log_warning "磁盘空间警告: ${disk_usage}%"
    else
        log_success "磁盘空间正常: ${disk_usage}%"
    fi
    
    # 检查内存使用
    echo ""
    echo "内存使用检查:"
    echo "----------------------------------------"
    local mem_info
    mem_info=$(salt-call --local status.meminfo 2>/dev/null)
    local mem_total
    mem_total=$(echo "$mem_info" | grep MemTotal | grep -o '[0-9]*')
    local mem_available
    mem_available=$(echo "$mem_info" | grep MemAvailable | grep -o '[0-9]*')
    
    if [[ -n "$mem_total" && -n "$mem_available" ]]; then
        local mem_usage=$(( (mem_total - mem_available) * 100 / mem_total ))
        
        if [[ "$mem_usage" -gt 90 ]]; then
            log_error "内存使用过高: ${mem_usage}%"
        elif [[ "$mem_usage" -gt 80 ]]; then
            log_warning "内存使用警告: ${mem_usage}%"
        else
            log_success "内存使用正常: ${mem_usage}%"
        fi
    fi
    
    # 检查系统负载
    echo ""
    echo "系统负载检查:"
    echo "----------------------------------------"
    local load_avg
    load_avg=$(salt-call --local status.loadavg 2>/dev/null)
    local cpu_cores
    cpu_cores=$(salt-call --local grains.get num_cpus 2>/dev/null)
    
    log_info "系统负载: $load_avg"
    log_info "CPU 核心数: $cpu_cores"
    
    # 检查服务状态
    echo ""
    echo "关键服务状态:"
    echo "----------------------------------------"
    local services=("nginx" "mysql" "php8.3-fpm" "valkey" "rabbitmq")
    
    for service in "${services[@]}"; do
        local status
        status=$(salt-call --local service.status "$service" 2>/dev/null | grep -o "True\|False")
        if [[ "$status" == "True" ]]; then
            log_success "✅ $service: 运行中"
        else
            log_error "❌ $service: 未运行"
        fi
    done
    
    # 检查系统更新
    echo ""
    echo "系统更新检查:"
    echo "----------------------------------------"
    local updates
    updates=$(salt-call --local pkg.list_upgrades 2>/dev/null | grep -c ":" 2>/dev/null | tr -d '\n' || echo "0")
    
    if [[ "$updates" -gt 0 ]]; then
        log_warning "有 $updates 个包可更新"
    else
        log_success "系统已是最新版本"
    fi
}

# 系统维护主函数
maintenance_handler() {
    case "$1" in
        "update")
            maintenance_update "$2"
            ;;
        "service")
            maintenance_service "$2" "$3"
            ;;
        "cleanup")
            maintenance_cleanup "$2"
            ;;
        "disk")
            maintenance_disk "$2" "$3" "$4"
            ;;
        "health")
            maintenance_health
            ;;
        *)
            log_error "未知的维护操作: $1"
            log_info "支持的操作:"
            log_info "  update <check|upgrade|dist-upgrade|autoremove|clean>"
            log_info "  service <restart|start|stop|reload|status> <service_name>"
            log_info "  cleanup <logs|temp|cache|all>"
            log_info "  disk <usage|find-large|cleanup-large> [size] [days]"
            log_info "  health"
            exit 1
            ;;
    esac
}

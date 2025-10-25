#!/bin/bash
# 日志管理模块 - 完全 Salt 原生功能
# services/logs.sh

# 日志目录配置
LOG_DIRS=(
    "/var/log/nginx"
    "/var/log/mysql"
    "/var/log/php8.3-fpm.log"
    "/var/log/valkey"
    "/var/log/rabbitmq"
    "/var/log/opensearch"
    "/var/log/salt"
    "/var/log/syslog"
    "/var/log/auth.log"
    "/var/log/kern.log"
)

# 查看日志文件
log_view() {
    local log_type="$1"
    local lines="${2:-50}"
    
    if [[ -z "$log_type" ]]; then
        log_error "用法: saltgoat logs view <log_type> [lines]"
        log_info "支持的日志类型: nginx, mysql, php, valkey, rabbitmq, opensearch, salt, syslog, auth, kern, all"
        log_info "示例: saltgoat logs view nginx 100"
        exit 1
    fi
    
    log_highlight "查看 $log_type 日志（最近 $lines 行）..."
    
    case "$log_type" in
        "nginx")
            if salt-call --local file.file_exists "/var/log/nginx/error.log" --out=txt 2>/dev/null | grep -q "True"; then
                log_info "=== Nginx Error Log ==="
                salt-call --local cmd.run "sudo tail -n $lines /var/log/nginx/error.log" 2>/dev/null
            fi
            if salt-call --local file.file_exists "/var/log/nginx/access.log" --out=txt 2>/dev/null | grep -q "True"; then
                log_info "=== Nginx Access Log ==="
                salt-call --local cmd.run "sudo tail -n $lines /var/log/nginx/access.log" 2>/dev/null
            fi
            ;;
        "mysql")
            if salt-call --local file.file_exists "/var/log/mysql/error.log" --out=txt 2>/dev/null | grep -q "True"; then
                log_info "=== MySQL Error Log ==="
                salt-call --local cmd.run "sudo tail -n $lines /var/log/mysql/error.log" 2>/dev/null
            fi
            ;;
        "php")
            if salt-call --local file.file_exists "/var/log/php8.3-fpm.log" --out=txt 2>/dev/null | grep -q "True"; then
                log_info "=== PHP-FPM Log ==="
                salt-call --local cmd.run "sudo tail -n $lines /var/log/php8.3-fpm.log" 2>/dev/null
            fi
            ;;
        "valkey")
            if salt-call --local file.file_exists "/var/log/valkey/valkey.log" --out=txt 2>/dev/null | grep -q "True"; then
                log_info "=== Valkey Log ==="
                salt-call --local cmd.run "sudo tail -n $lines /var/log/valkey/valkey.log" 2>/dev/null
            fi
            ;;
        "rabbitmq")
            if salt-call --local file.file_exists "/var/log/rabbitmq/rabbit@$(hostname).log" --out=txt 2>/dev/null | grep -q "True"; then
                log_info "=== RabbitMQ Log ==="
                salt-call --local cmd.run "sudo tail -n $lines /var/log/rabbitmq/rabbit@$(hostname).log" 2>/dev/null
            fi
            ;;
        "opensearch")
            if salt-call --local file.file_exists "/var/log/opensearch/opensearch.log" --out=txt 2>/dev/null | grep -q "True"; then
                log_info "=== OpenSearch Log ==="
                salt-call --local cmd.run "sudo tail -n $lines /var/log/opensearch/opensearch.log" 2>/dev/null
            fi
            ;;
        "salt")
            if salt-call --local file.file_exists "/var/log/salt/minion" --out=txt 2>/dev/null | grep -q "True"; then
                log_info "=== Salt Minion Log ==="
                salt-call --local cmd.run "sudo tail -n $lines /var/log/salt/minion" 2>/dev/null
            fi
            ;;
        "syslog")
            if salt-call --local file.file_exists "/var/log/syslog" --out=txt 2>/dev/null | grep -q "True"; then
                log_info "=== System Log ==="
                salt-call --local cmd.run "sudo tail -n $lines /var/log/syslog" 2>/dev/null
            fi
            ;;
        "auth")
            if salt-call --local file.file_exists "/var/log/auth.log" --out=txt 2>/dev/null | grep -q "True"; then
                log_info "=== Authentication Log ==="
                salt-call --local cmd.run "sudo tail -n $lines /var/log/auth.log" 2>/dev/null
            fi
            ;;
        "kern")
            if salt-call --local file.file_exists "/var/log/kern.log" --out=txt 2>/dev/null | grep -q "True"; then
                log_info "=== Kernel Log ==="
                salt-call --local cmd.run "sudo tail -n $lines /var/log/kern.log" 2>/dev/null
            fi
            ;;
        "all")
            log_info "=== 所有服务日志概览 ==="
            for log_dir in "${LOG_DIRS[@]}"; do
                if salt-call --local file.file_exists "$log_dir" --out=txt 2>/dev/null | grep -q "True"; then
                    log_info "--- $log_dir ---"
                    salt-call --local cmd.run "ls -la $log_dir 2>/dev/null | head -5" 2>/dev/null
                fi
            done
            ;;
        *)
            log_error "不支持的日志类型: $log_type"
            log_info "支持的日志类型: nginx, mysql, php, valkey, rabbitmq, opensearch, salt, syslog, auth, kern, all"
            exit 1
            ;;
    esac
}

# 清理日志文件
log_cleanup() {
    local log_type="$1"
    local days="${2:-7}"
    
    if [[ -z "$log_type" ]]; then
        log_error "用法: saltgoat logs cleanup <log_type> [days]"
        log_info "支持的日志类型: nginx, mysql, php, valkey, rabbitmq, opensearch, salt, syslog, auth, kern, all"
        log_info "示例: saltgoat logs cleanup nginx 30"
        exit 1
    fi
    
    log_highlight "清理 $log_type 日志（保留 $days 天）..."
    log_warning "这将删除超过 $days 天的日志文件，请确认是否继续？"
    read -r -p "输入 'yes' 确认继续: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "清理操作已取消"
        exit 0
    fi
    
    case "$log_type" in
        "nginx")
            salt-call --local cmd.run "find /var/log/nginx -name '*.log.*' -mtime +$days -delete 2>/dev/null || true"
            salt-call --local cmd.run "find /var/log/nginx -name '*.gz' -mtime +$days -delete 2>/dev/null || true"
            ;;
        "mysql")
            salt-call --local cmd.run "find /var/log/mysql -name '*.log.*' -mtime +$days -delete 2>/dev/null || true"
            salt-call --local cmd.run "find /var/log/mysql -name '*.gz' -mtime +$days -delete 2>/dev/null || true"
            ;;
        "php")
            salt-call --local cmd.run "find /var/log -name 'php*.log.*' -mtime +$days -delete 2>/dev/null || true"
            salt-call --local cmd.run "find /var/log -name 'php*.gz' -mtime +$days -delete 2>/dev/null || true"
            ;;
        "valkey")
            salt-call --local cmd.run "find /var/log/valkey -name '*.log.*' -mtime +$days -delete 2>/dev/null || true"
            salt-call --local cmd.run "find /var/log/valkey -name '*.gz' -mtime +$days -delete 2>/dev/null || true"
            ;;
        "rabbitmq")
            salt-call --local cmd.run "find /var/log/rabbitmq -name '*.log.*' -mtime +$days -delete 2>/dev/null || true"
            salt-call --local cmd.run "find /var/log/rabbitmq -name '*.gz' -mtime +$days -delete 2>/dev/null || true"
            ;;
        "opensearch")
            salt-call --local cmd.run "find /var/log/opensearch -name '*.log.*' -mtime +$days -delete 2>/dev/null || true"
            salt-call --local cmd.run "find /var/log/opensearch -name '*.gz' -mtime +$days -delete 2>/dev/null || true"
            ;;
        "salt")
            salt-call --local cmd.run "find /var/log/salt -name '*.log.*' -mtime +$days -delete 2>/dev/null || true"
            salt-call --local cmd.run "find /var/log/salt -name '*.gz' -mtime +$days -delete 2>/dev/null || true"
            ;;
        "syslog")
            salt-call --local cmd.run "find /var/log -name 'syslog.*' -mtime +$days -delete 2>/dev/null || true"
            salt-call --local cmd.run "find /var/log -name 'syslog.*.gz' -mtime +$days -delete 2>/dev/null || true"
            ;;
        "auth")
            salt-call --local cmd.run "find /var/log -name 'auth.log.*' -mtime +$days -delete 2>/dev/null || true"
            salt-call --local cmd.run "find /var/log -name 'auth.log.*.gz' -mtime +$days -delete 2>/dev/null || true"
            ;;
        "kern")
            salt-call --local cmd.run "find /var/log -name 'kern.log.*' -mtime +$days -delete 2>/dev/null || true"
            salt-call --local cmd.run "find /var/log -name 'kern.log.*.gz' -mtime +$days -delete 2>/dev/null || true"
            ;;
        "all")
            for log_dir in "${LOG_DIRS[@]}"; do
                if salt-call --local file.directory_exists "$log_dir" --out=txt 2>/dev/null | grep -q "True"; then
                    salt-call --local cmd.run "find $log_dir -name '*.log.*' -mtime +$days -delete 2>/dev/null || true"
                    salt-call --local cmd.run "find $log_dir -name '*.gz' -mtime +$days -delete 2>/dev/null || true"
                fi
            done
            ;;
        *)
            log_error "不支持的日志类型: $log_type"
            log_info "支持的日志类型: nginx, mysql, php, valkey, rabbitmq, opensearch, salt, syslog, auth, kern, all"
            exit 1
            ;;
    esac
    
    log_success "日志清理完成: $log_type"
}

# 轮转日志文件
log_rotate() {
    local log_type="$1"
    
    if [[ -z "$log_type" ]]; then
        log_error "用法: saltgoat logs rotate <log_type>"
        log_info "支持的日志类型: nginx, mysql, php, valkey, rabbitmq, opensearch, salt, syslog, auth, kern, all"
        log_info "示例: saltgoat logs rotate nginx"
        exit 1
    fi
    
    log_highlight "轮转 $log_type 日志..."
    
    case "$log_type" in
        "nginx")
            salt-call --local cmd.run "logrotate -f /etc/logrotate.d/nginx 2>/dev/null || true"
            ;;
        "mysql")
            salt-call --local cmd.run "logrotate -f /etc/logrotate.d/mysql-server 2>/dev/null || true"
            ;;
        "php")
            salt-call --local cmd.run "logrotate -f /etc/logrotate.d/php8.3-fpm 2>/dev/null || true"
            ;;
        "valkey")
            salt-call --local cmd.run "logrotate -f /etc/logrotate.d/valkey 2>/dev/null || true"
            ;;
        "rabbitmq")
            salt-call --local cmd.run "logrotate -f /etc/logrotate.d/rabbitmq-server 2>/dev/null || true"
            ;;
        "opensearch")
            salt-call --local cmd.run "logrotate -f /etc/logrotate.d/opensearch 2>/dev/null || true"
            ;;
        "salt")
            salt-call --local cmd.run "logrotate -f /etc/logrotate.d/salt-common 2>/dev/null || true"
            ;;
        "syslog")
            salt-call --local cmd.run "logrotate -f /etc/logrotate.d/rsyslog 2>/dev/null || true"
            ;;
        "auth")
            salt-call --local cmd.run "logrotate -f /etc/logrotate.d/rsyslog 2>/dev/null || true"
            ;;
        "kern")
            salt-call --local cmd.run "logrotate -f /etc/logrotate.d/rsyslog 2>/dev/null || true"
            ;;
        "all")
            salt-call --local cmd.run "logrotate -f /etc/logrotate.conf 2>/dev/null || true"
            ;;
        *)
            log_error "不支持的日志类型: $log_type"
            log_info "支持的日志类型: nginx, mysql, php, valkey, rabbitmq, opensearch, salt, syslog, auth, kern, all"
            exit 1
            ;;
    esac
    
    log_success "日志轮转完成: $log_type"
}

# 查看日志统计信息
log_stats() {
    log_highlight "日志文件统计信息..."
    
    echo "日志目录大小统计:"
    echo "=========================================="
    
    for log_dir in "${LOG_DIRS[@]}"; do
        if salt-call --local file.directory_exists "$log_dir" --out=txt 2>/dev/null | grep -q "True"; then
            local size
            size=$(du -sh "$log_dir" 2>/dev/null | awk '{print $1}')
            local files
            files=$(find "$log_dir" -type f 2>/dev/null | wc -l)
            echo "$log_dir: $size ($files 个文件)"
        fi
    done
    
    echo ""
    echo "系统日志总大小:"
    local total_size
    total_size=$(du -sh /var/log 2>/dev/null | awk '{print $1}')
    echo "/var/log: $total_size"
    
    echo ""
    echo "磁盘使用情况:"
    df -h /var/log
}

# 实时监控日志
log_monitor() {
    local log_type="$1"
    
    if [[ -z "$log_type" ]]; then
        log_error "用法: saltgoat logs monitor <log_type>"
        log_info "支持的日志类型: nginx, mysql, php, valkey, rabbitmq, opensearch, salt, syslog, auth, kern"
        log_info "示例: saltgoat logs monitor nginx"
        exit 1
    fi
    
    log_highlight "实时监控 $log_type 日志（按 Ctrl+C 退出）..."
    
    case "$log_type" in
        "nginx")
            if salt-call --local file.file_exists "/var/log/nginx/error.log" --out=txt 2>/dev/null | grep -q "True"; then
                salt-call --local cmd.run "tail -f /var/log/nginx/error.log" 2>/dev/null
            else
                log_error "Nginx 错误日志文件不存在"
            fi
            ;;
        "mysql")
            if salt-call --local file.file_exists "/var/log/mysql/error.log" --out=txt 2>/dev/null | grep -q "True"; then
                salt-call --local cmd.run "tail -f /var/log/mysql/error.log" 2>/dev/null
            else
                log_error "MySQL 错误日志文件不存在"
            fi
            ;;
        "php")
            if salt-call --local file.file_exists "/var/log/php8.3-fpm.log" --out=txt 2>/dev/null | grep -q "True"; then
                salt-call --local cmd.run "tail -f /var/log/php8.3-fpm.log" 2>/dev/null
            else
                log_error "PHP-FPM 日志文件不存在"
            fi
            ;;
        "valkey")
            if salt-call --local file.file_exists "/var/log/valkey/valkey.log" --out=txt 2>/dev/null | grep -q "True"; then
                salt-call --local cmd.run "tail -f /var/log/valkey/valkey.log" 2>/dev/null
            else
                log_error "Valkey 日志文件不存在"
            fi
            ;;
        "rabbitmq")
            if salt-call --local file.file_exists "/var/log/rabbitmq/rabbit@$(hostname).log" --out=txt 2>/dev/null | grep -q "True"; then
                salt-call --local cmd.run "tail -f /var/log/rabbitmq/rabbit@$(hostname).log" 2>/dev/null
            else
                log_error "RabbitMQ 日志文件不存在"
            fi
            ;;
        "opensearch")
            if salt-call --local file.file_exists "/var/log/opensearch/opensearch.log" --out=txt 2>/dev/null | grep -q "True"; then
                salt-call --local cmd.run "tail -f /var/log/opensearch/opensearch.log" 2>/dev/null
            else
                log_error "OpenSearch 日志文件不存在"
            fi
            ;;
        "salt")
            if salt-call --local file.file_exists "/var/log/salt/minion" --out=txt 2>/dev/null | grep -q "True"; then
                salt-call --local cmd.run "tail -f /var/log/salt/minion" 2>/dev/null
            else
                log_error "Salt Minion 日志文件不存在"
            fi
            ;;
        "syslog")
            if salt-call --local file.file_exists "/var/log/syslog" --out=txt 2>/dev/null | grep -q "True"; then
                salt-call --local cmd.run "tail -f /var/log/syslog" 2>/dev/null
            else
                log_error "系统日志文件不存在"
            fi
            ;;
        "auth")
            if salt-call --local file.file_exists "/var/log/auth.log" --out=txt 2>/dev/null | grep -q "True"; then
                salt-call --local cmd.run "tail -f /var/log/auth.log" 2>/dev/null
            else
                log_error "认证日志文件不存在"
            fi
            ;;
        "kern")
            if salt-call --local file.file_exists "/var/log/kern.log" --out=txt 2>/dev/null | grep -q "True"; then
                salt-call --local cmd.run "tail -f /var/log/kern.log" 2>/dev/null
            else
                log_error "内核日志文件不存在"
            fi
            ;;
        *)
            log_error "不支持的日志类型: $log_type"
            log_info "支持的日志类型: nginx, mysql, php, valkey, rabbitmq, opensearch, salt, syslog, auth, kern"
            exit 1
            ;;
    esac
}

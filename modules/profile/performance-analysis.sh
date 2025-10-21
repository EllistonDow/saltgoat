#!/bin/bash
# 性能分析模块
# services/performance-analysis.sh

# 性能分析类型
PERFORMANCE_TYPES=("system" "nginx" "mysql" "php" "memory" "disk" "network")

# 性能分析结果存储
PERFORMANCE_RESULTS=()

# 系统性能分析
analyze_system_performance() {
    log_info "开始系统性能分析..."
    
    local issues=()
    local recommendations=()
    local score=100
    
    # CPU使用率分析
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    if (( $(echo "$cpu_usage > 80" | bc -l) )); then
        issues+=("CPU使用率过高: ${cpu_usage}%")
        recommendations+=("检查CPU密集型进程，考虑优化或增加CPU资源")
        score=$((score - 20))
    elif (( $(echo "$cpu_usage > 60" | bc -l) )); then
        issues+=("CPU使用率较高: ${cpu_usage}%")
        recommendations+=("监控CPU使用情况，考虑优化应用程序")
        score=$((score - 10))
    fi
    
    # 内存使用率分析
    local mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [[ "$mem_usage" -gt 90 ]]; then
        issues+=("内存使用率过高: ${mem_usage}%")
        recommendations+=("增加内存或优化内存使用，检查内存泄漏")
        score=$((score - 25))
    elif [[ "$mem_usage" -gt 80 ]]; then
        issues+=("内存使用率较高: ${mem_usage}%")
        recommendations+=("监控内存使用，考虑优化应用程序")
        score=$((score - 15))
    fi
    
    # 系统负载分析
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_cores=$(nproc)
    local load_threshold=$(echo "$cpu_cores * 1.5" | bc)
    if (( $(echo "$load_avg > $load_threshold" | bc -l) )); then
        issues+=("系统负载过高: $load_avg (CPU核心数: $cpu_cores)")
        recommendations+=("检查系统负载，优化进程调度")
        score=$((score - 20))
    fi
    
    # 进程分析
    local top_processes=$(ps aux --sort=-%cpu | head -6 | tail -5)
    local high_cpu_processes=$(echo "$top_processes" | awk '$3 > 10.0 {print $2, $3, $11}' | wc -l)
    if [[ "$high_cpu_processes" -gt 0 ]]; then
        issues+=("发现 $high_cpu_processes 个高CPU使用进程")
        recommendations+=("检查高CPU使用进程，优化或限制资源使用")
        score=$((score - 10))
    fi
    
    # 输出分析结果
    echo "=========================================="
    log_info "系统性能分析结果:"
    echo "----------------------------------------"
    log_info "CPU使用率: ${cpu_usage}%"
    log_info "内存使用率: ${mem_usage}%"
    log_info "系统负载: $load_avg (CPU核心: $cpu_cores)"
    echo "----------------------------------------"
    
    if [[ ${#issues[@]} -eq 0 ]]; then
        log_success "系统性能良好，未发现问题"
    else
        log_warning "发现 ${#issues[@]} 个性能问题:"
        for i in "${!issues[@]}"; do
            log_error "  ${issues[$i]}"
            log_info "  建议: ${recommendations[$i]}"
        done
    fi
    
    echo "----------------------------------------"
    log_info "性能评分: $score/100"
    
    # 存储分析结果
    PERFORMANCE_RESULTS+=("system:$score:${#issues[@]}:${issues[*]}")
}

# Nginx性能分析
analyze_nginx_performance() {
    log_info "开始Nginx性能分析..."
    
    local issues=()
    local recommendations=()
    local score=100
    
    # 检查Nginx状态
    if ! systemctl is-active --quiet nginx 2>/dev/null; then
        issues+=("Nginx服务未运行")
        recommendations+=("启动Nginx服务: sudo systemctl start nginx")
        score=$((score - 50))
    else
        # 检查Nginx配置
        if command -v nginx >/dev/null 2>&1; then
            if ! nginx -t 2>/dev/null; then
                issues+=("Nginx配置有语法错误")
                recommendations+=("修复Nginx配置文件语法错误")
                score=$((score - 30))
            fi
        fi
        
        # 检查Nginx进程
        local nginx_processes=$(pgrep nginx | wc -l)
        if [[ "$nginx_processes" -lt 2 ]]; then
            issues+=("Nginx进程数量异常: $nginx_processes")
            recommendations+=("检查Nginx进程配置")
            score=$((score - 20))
        fi
        
        # 检查Nginx连接数
        if command -v ss >/dev/null 2>&1; then
            local nginx_connections=$(ss -tlnp | grep nginx | wc -l)
            if [[ "$nginx_connections" -gt 1000 ]]; then
                issues+=("Nginx连接数过多: $nginx_connections")
                recommendations+=("优化Nginx连接配置，增加worker_connections")
                score=$((score - 15))
            fi
        fi
        
        # 检查Nginx日志错误
        local nginx_error_log="/var/log/nginx/error.log"
        if [[ -f "$nginx_error_log" ]]; then
            local error_count=$(grep -c "ERROR\|FATAL" "$nginx_error_log" 2>/dev/null || echo "0")
            if [[ "$error_count" -gt 100 ]]; then
                issues+=("Nginx错误日志过多: $error_count 个错误")
                recommendations+=("检查Nginx错误日志，修复配置问题")
                score=$((score - 10))
            fi
        fi
    fi
    
    # 输出分析结果
    echo "=========================================="
    log_info "Nginx性能分析结果:"
    echo "----------------------------------------"
    
    if [[ ${#issues[@]} -eq 0 ]]; then
        log_success "Nginx性能良好，未发现问题"
    else
        log_warning "发现 ${#issues[@]} 个Nginx问题:"
        for i in "${!issues[@]}"; do
            log_error "  ${issues[$i]}"
            log_info "  建议: ${recommendations[$i]}"
        done
    fi
    
    echo "----------------------------------------"
    log_info "Nginx性能评分: $score/100"
    
    # 存储分析结果
    PERFORMANCE_RESULTS+=("nginx:$score:${#issues[@]}:${issues[*]}")
}

# MySQL性能分析
analyze_mysql_performance() {
    log_info "开始MySQL性能分析..."
    
    local issues=()
    local recommendations=()
    local score=100
    
    # 检查MySQL状态
    if ! systemctl is-active --quiet mysql 2>/dev/null; then
        issues+=("MySQL服务未运行")
        recommendations+=("启动MySQL服务: sudo systemctl start mysql")
        score=$((score - 50))
    else
        # 检查MySQL连接
        if ! mysql -e "SELECT 1;" 2>/dev/null; then
            issues+=("无法连接到MySQL数据库")
            recommendations+=("检查MySQL服务状态和用户权限")
            score=$((score - 30))
        else
            # 检查MySQL连接数
            local connections=$(mysql -e "SHOW STATUS LIKE 'Threads_connected';" 2>/dev/null | awk 'NR==2{print $2}')
            local max_connections=$(mysql -e "SHOW VARIABLES LIKE 'max_connections';" 2>/dev/null | awk 'NR==2{print $2}')
            if [[ -n "$connections" && -n "$max_connections" ]]; then
                local connection_usage=$((connections * 100 / max_connections))
                if [[ "$connection_usage" -gt 80 ]]; then
                    issues+=("MySQL连接数使用率过高: ${connection_usage}%")
                    recommendations+=("优化MySQL连接配置，增加max_connections")
                    score=$((score - 20))
                fi
            fi
            
            # 检查MySQL查询缓存
            local query_cache=$(mysql -e "SHOW VARIABLES LIKE 'query_cache%';" 2>/dev/null | grep -c "ON")
            if [[ "$query_cache" -eq 0 ]]; then
                issues+=("MySQL查询缓存未启用")
                recommendations+=("启用MySQL查询缓存以提高性能")
                score=$((score - 10))
            fi
            
            # 检查MySQL慢查询
            local slow_queries=$(mysql -e "SHOW STATUS LIKE 'Slow_queries';" 2>/dev/null | awk 'NR==2{print $2}')
            if [[ -n "$slow_queries" && "$slow_queries" -gt 100 ]]; then
                issues+=("MySQL慢查询过多: $slow_queries")
                recommendations+=("优化MySQL查询，启用慢查询日志分析")
                score=$((score - 15))
            fi
        fi
    fi
    
    # 输出分析结果
    echo "=========================================="
    log_info "MySQL性能分析结果:"
    echo "----------------------------------------"
    
    if [[ ${#issues[@]} -eq 0 ]]; then
        log_success "MySQL性能良好，未发现问题"
    else
        log_warning "发现 ${#issues[@]} 个MySQL问题:"
        for i in "${!issues[@]}"; do
            log_error "  ${issues[$i]}"
            log_info "  建议: ${recommendations[$i]}"
        done
    fi
    
    echo "----------------------------------------"
    log_info "MySQL性能评分: $score/100"
    
    # 存储分析结果
    PERFORMANCE_RESULTS+=("mysql:$score:${#issues[@]}:${issues[*]}")
}

# PHP性能分析
analyze_php_performance() {
    log_info "开始PHP性能分析..."
    
    local issues=()
    local recommendations=()
    local score=100
    
    # 检查PHP-FPM状态
    if ! systemctl is-active --quiet php8.3-fpm 2>/dev/null; then
        issues+=("PHP-FPM服务未运行")
        recommendations+=("启动PHP-FPM服务: sudo systemctl start php8.3-fpm")
        score=$((score - 50))
    else
        # 检查PHP-FPM进程
        local php_processes=$(pgrep php-fpm | wc -l)
        if [[ "$php_processes" -lt 2 ]]; then
            issues+=("PHP-FPM进程数量异常: $php_processes")
            recommendations+=("检查PHP-FPM进程配置")
            score=$((score - 20))
        fi
        
        # 检查PHP内存限制
        local memory_limit=$(php -r "echo ini_get('memory_limit');" 2>/dev/null)
        if [[ -n "$memory_limit" ]]; then
            local memory_mb=$(echo "$memory_limit" | sed 's/M//')
            if [[ "$memory_mb" -lt 128 ]]; then
                issues+=("PHP内存限制过低: ${memory_limit}")
                recommendations+=("增加PHP内存限制到至少128M")
                score=$((score - 15))
            fi
        fi
        
        # 检查PHP OPcache
        local opcache_enabled=$(php -r "echo ini_get('opcache.enable');" 2>/dev/null)
        if [[ "$opcache_enabled" != "1" ]]; then
            issues+=("PHP OPcache未启用")
            recommendations+=("启用PHP OPcache以提高性能")
            score=$((score - 20))
        fi
        
        # 检查PHP错误日志
        local php_log="/var/log/php8.3-fpm.log"
        if [[ -f "$php_log" ]]; then
            local error_count=$(grep -c "ERROR\|FATAL" "$php_log" 2>/dev/null || echo "0")
            if [[ "$error_count" -gt 50 ]]; then
                issues+=("PHP错误日志过多: $error_count 个错误")
                recommendations+=("检查PHP错误日志，修复代码问题")
                score=$((score - 10))
            fi
        fi
    fi
    
    # 输出分析结果
    echo "=========================================="
    log_info "PHP性能分析结果:"
    echo "----------------------------------------"
    
    if [[ ${#issues[@]} -eq 0 ]]; then
        log_success "PHP性能良好，未发现问题"
    else
        log_warning "发现 ${#issues[@]} 个PHP问题:"
        for i in "${!issues[@]}"; do
            log_error "  ${issues[$i]}"
            log_info "  建议: ${recommendations[$i]}"
        done
    fi
    
    echo "----------------------------------------"
    log_info "PHP性能评分: $score/100"
    
    # 存储分析结果
    PERFORMANCE_RESULTS+=("php:$score:${#issues[@]}:${issues[*]}")
}

# 内存性能分析
analyze_memory_performance() {
    log_info "开始内存性能分析..."
    
    local issues=()
    local recommendations=()
    local score=100
    
    # 内存使用分析
    local mem_info=$(free -m)
    local total_mem=$(echo "$mem_info" | awk 'NR==2{print $2}')
    local used_mem=$(echo "$mem_info" | awk 'NR==2{print $3}')
    local free_mem=$(echo "$mem_info" | awk 'NR==2{print $4}')
    local available_mem=$(echo "$mem_info" | awk 'NR==2{print $7}')
    
    local mem_usage=$((used_mem * 100 / total_mem))
    local mem_available=$((available_mem * 100 / total_mem))
    
    if [[ "$mem_usage" -gt 90 ]]; then
        issues+=("内存使用率过高: ${mem_usage}%")
        recommendations+=("增加内存或优化内存使用")
        score=$((score - 30))
    elif [[ "$mem_usage" -gt 80 ]]; then
        issues+=("内存使用率较高: ${mem_usage}%")
        recommendations+=("监控内存使用，考虑优化")
        score=$((score - 15))
    fi
    
    if [[ "$mem_available" -lt 10 ]]; then
        issues+=("可用内存不足: ${available_mem}MB")
        recommendations+=("释放内存或增加系统内存")
        score=$((score - 25))
    fi
    
    # 交换空间分析
    local swap_used=$(echo "$mem_info" | awk 'NR==3{print $3}')
    if [[ "$swap_used" -gt 0 ]]; then
        issues+=("系统正在使用交换空间: ${swap_used}MB")
        recommendations+=("优化内存使用，减少交换空间使用")
        score=$((score - 20))
    fi
    
    # 内存泄漏检查
    local high_mem_processes=$(ps aux --sort=-%mem | awk '$4 > 10.0 {count++} END {print count+0}')
    if [[ "$high_mem_processes" -gt 0 ]]; then
        issues+=("发现 $high_mem_processes 个高内存使用进程")
        recommendations+=("检查高内存使用进程，优化内存使用")
        score=$((score - 15))
    fi
    
    # 输出分析结果
    echo "=========================================="
    log_info "内存性能分析结果:"
    echo "----------------------------------------"
    log_info "总内存: ${total_mem}MB"
    log_info "已使用: ${used_mem}MB (${mem_usage}%)"
    log_info "可用内存: ${available_mem}MB (${mem_available}%)"
    log_info "交换空间: ${swap_used}MB"
    echo "----------------------------------------"
    
    if [[ ${#issues[@]} -eq 0 ]]; then
        log_success "内存性能良好，未发现问题"
    else
        log_warning "发现 ${#issues[@]} 个内存问题:"
        for i in "${!issues[@]}"; do
            log_error "  ${issues[$i]}"
            log_info "  建议: ${recommendations[$i]}"
        done
    fi
    
    echo "----------------------------------------"
    log_info "内存性能评分: $score/100"
    
    # 存储分析结果
    PERFORMANCE_RESULTS+=("memory:$score:${#issues[@]}:${issues[*]}")
}

# 磁盘性能分析
analyze_disk_performance() {
    log_info "开始磁盘性能分析..."
    
    local issues=()
    local recommendations=()
    local score=100
    
    # 磁盘使用率分析
    local disk_usage=$(df / | awk 'NR==2{print $5}' | sed 's/%//')
    if [[ "$disk_usage" -gt 90 ]]; then
        issues+=("根分区磁盘使用率过高: ${disk_usage}%")
        recommendations+=("清理磁盘空间或增加磁盘容量")
        score=$((score - 30))
    elif [[ "$disk_usage" -gt 80 ]]; then
        issues+=("根分区磁盘使用率较高: ${disk_usage}%")
        recommendations+=("监控磁盘使用，考虑清理")
        score=$((score - 15))
    fi
    
    # 磁盘I/O分析
    if command -v iostat >/dev/null 2>&1; then
        local iostat_output=$(iostat -x 1 1 2>/dev/null | tail -n +4)
        local avg_await=$(echo "$iostat_output" | awk '{sum+=$10} END {print sum/NR}')
        if (( $(echo "$avg_await > 100" | bc -l) )); then
            issues+=("磁盘I/O等待时间过长: ${avg_await}ms")
            recommendations+=("优化磁盘I/O，考虑使用SSD")
            score=$((score - 20))
        fi
    fi
    
    # 检查大文件
    local large_files=$(find / -type f -size +100M 2>/dev/null | wc -l)
    if [[ "$large_files" -gt 10 ]]; then
        issues+=("发现 $large_files 个大文件 (>100MB)")
        recommendations+=("检查大文件，考虑清理或移动")
        score=$((score - 10))
    fi
    
    # 检查日志文件大小
    local log_size=$(du -sh /var/log 2>/dev/null | awk '{print $1}')
    if [[ -n "$log_size" ]]; then
        local log_size_mb=$(echo "$log_size" | sed 's/M//')
        if [[ "$log_size_mb" -gt 1000 ]]; then
            issues+=("日志文件过大: ${log_size}")
            recommendations+=("清理旧日志文件")
            score=$((score - 10))
        fi
    fi
    
    # 输出分析结果
    echo "=========================================="
    log_info "磁盘性能分析结果:"
    echo "----------------------------------------"
    log_info "根分区使用率: ${disk_usage}%"
    log_info "大文件数量: $large_files"
    log_info "日志目录大小: ${log_size:-未知}"
    echo "----------------------------------------"
    
    if [[ ${#issues[@]} -eq 0 ]]; then
        log_success "磁盘性能良好，未发现问题"
    else
        log_warning "发现 ${#issues[@]} 个磁盘问题:"
        for i in "${!issues[@]}"; do
            log_error "  ${issues[$i]}"
            log_info "  建议: ${recommendations[$i]}"
        done
    fi
    
    echo "----------------------------------------"
    log_info "磁盘性能评分: $score/100"
    
    # 存储分析结果
    PERFORMANCE_RESULTS+=("disk:$score:${#issues[@]}:${issues[*]}")
}

# 网络性能分析
analyze_network_performance() {
    log_info "开始网络性能分析..."
    
    local issues=()
    local recommendations=()
    local score=100
    
    # 网络连接数分析
    if command -v ss >/dev/null 2>&1; then
        local total_connections=$(ss -tuln | wc -l)
        if [[ "$total_connections" -gt 1000 ]]; then
            issues+=("网络连接数过多: $total_connections")
            recommendations+=("检查网络连接，优化连接管理")
            score=$((score - 20))
        fi
        
        # 检查TIME_WAIT连接
        local time_wait=$(ss -tuln | grep TIME_WAIT | wc -l)
        if [[ "$time_wait" -gt 100 ]]; then
            issues+=("TIME_WAIT连接过多: $time_wait")
            recommendations+=("优化TCP连接配置")
            score=$((score - 15))
        fi
    fi
    
    # 网络延迟测试
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        local ping_time=$(ping -c 1 8.8.8.8 2>/dev/null | grep "time=" | awk '{print $7}' | cut -d'=' -f2)
        if [[ -n "$ping_time" ]]; then
            local ping_ms=$(echo "$ping_time" | sed 's/ms//')
            if (( $(echo "$ping_ms > 100" | bc -l) )); then
                issues+=("网络延迟过高: ${ping_ms}ms")
                recommendations+=("检查网络连接质量")
                score=$((score - 10))
            fi
        fi
    else
        issues+=("无法连接到外网")
        recommendations+=("检查网络连接配置")
        score=$((score - 30))
    fi
    
    # 检查网络接口状态
    local network_interfaces=$(ip link show | grep -c "state UP")
    if [[ "$network_interfaces" -lt 1 ]]; then
        issues+=("没有活跃的网络接口")
        recommendations+=("检查网络接口配置")
        score=$((score - 40))
    fi
    
    # 输出分析结果
    echo "=========================================="
    log_info "网络性能分析结果:"
    echo "----------------------------------------"
    log_info "总连接数: ${total_connections:-未知}"
    log_info "TIME_WAIT连接: ${time_wait:-未知}"
    log_info "网络延迟: ${ping_ms:-未知}ms"
    log_info "活跃接口: ${network_interfaces:-未知}"
    echo "----------------------------------------"
    
    if [[ ${#issues[@]} -eq 0 ]]; then
        log_success "网络性能良好，未发现问题"
    else
        log_warning "发现 ${#issues[@]} 个网络问题:"
        for i in "${!issues[@]}"; do
            log_error "  ${issues[$i]}"
            log_info "  建议: ${recommendations[$i]}"
        done
    fi
    
    echo "----------------------------------------"
    log_info "网络性能评分: $score/100"
    
    # 存储分析结果
    PERFORMANCE_RESULTS+=("network:$score:${#issues[@]}:${issues[*]}")
}

# 显示性能分析摘要
show_performance_summary() {
    log_info "性能分析摘要:"
    echo "=========================================="
    
    local total_score=0
    local total_issues=0
    local analysis_count=0
    
    for result in "${PERFORMANCE_RESULTS[@]}"; do
        local type=$(echo "$result" | cut -d':' -f1)
        local score=$(echo "$result" | cut -d':' -f2)
        local issues=$(echo "$result" | cut -d':' -f3)
        
        total_score=$((total_score + score))
        total_issues=$((total_issues + issues))
        analysis_count=$((analysis_count + 1))
        
        if [[ "$score" -ge 90 ]]; then
            log_success "$type: $score/100 (优秀)"
        elif [[ "$score" -ge 80 ]]; then
            log_info "$type: $score/100 (良好)"
        elif [[ "$score" -ge 70 ]]; then
            log_warning "$type: $score/100 (一般)"
        else
            log_error "$type: $score/100 (需要优化)"
        fi
    done
    
    local average_score=$((total_score / analysis_count))
    
    echo "=========================================="
    log_info "总体性能评分: $average_score/100"
    log_info "发现总问题数: $total_issues"
    
    if [[ "$average_score" -ge 90 ]]; then
        log_success "系统性能优秀，运行良好"
    elif [[ "$average_score" -ge 80 ]]; then
        log_info "系统性能良好，有优化空间"
    elif [[ "$average_score" -ge 70 ]]; then
        log_warning "系统性能一般，建议优化"
    else
        log_error "系统性能较差，需要重点优化"
    fi
    
    echo "=========================================="
    log_info "优化建议:"
    log_info "1. 定期运行性能分析: saltgoat performance analyze all"
    log_info "2. 监控系统资源使用情况"
    log_info "3. 根据分析结果进行针对性优化"
    log_info "4. 考虑使用监控工具进行持续监控"
}

# 性能分析主函数
performance_analyze_handler() {
    case "$1" in
        "system")
            analyze_system_performance
            ;;
        "nginx")
            analyze_nginx_performance
            ;;
        "mysql")
            analyze_mysql_performance
            ;;
        "php")
            analyze_php_performance
            ;;
        "memory")
            analyze_memory_performance
            ;;
        "disk")
            analyze_disk_performance
            ;;
        "network")
            analyze_network_performance
            ;;
        "all")
            log_info "开始完整性能分析..."
            analyze_system_performance
            analyze_nginx_performance
            analyze_mysql_performance
            analyze_php_performance
            analyze_memory_performance
            analyze_disk_performance
            analyze_network_performance
            show_performance_summary
            ;;
        *)
            log_error "未知的性能分析类型: $1"
            log_info "支持的类型: system, nginx, mysql, php, memory, disk, network, all"
            return 1
            ;;
    esac
}

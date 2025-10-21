#!/bin/bash
# 智能优化建议模块 - 完全使用 Salt 原生功能
# services/optimize.sh

# 智能优化建议
optimize() {
    log_highlight "SaltGoat 智能优化建议..."
    
    echo "系统分析和优化建议"
    echo "=========================================="
    
    # 收集系统信息
    local system_info=$(collect_system_info)
    
    # 分析各个组件
    analyze_nginx "$system_info"
    analyze_mysql "$system_info"
    analyze_php "$system_info"
    analyze_valkey "$system_info"
    analyze_system "$system_info"
    
    # 生成优化建议
    generate_optimization_recommendations
    
    echo ""
    echo "优化建议总结:"
    echo "=========================================="
    display_optimization_summary
}

# 收集系统信息
collect_system_info() {
    local cpu_cores=$(nproc)
    local total_memory=$(free -m | awk 'NR==2{print $2}')
    local disk_space=$(df / | awk 'NR==2{print $2}')
    local load_avg=$(uptime | grep -o 'load average:.*' | cut -d: -f2)
    
    # 返回系统信息（用|分隔）
    echo "$cpu_cores|$total_memory|$disk_space|$load_avg"
}

# 分析 Nginx 配置
analyze_nginx() {
    local system_info="$1"
    local cpu_cores=$(echo "$system_info" | cut -d'|' -f1)
    local total_memory=$(echo "$system_info" | cut -d'|' -f2)
    
    echo ""
    echo "Nginx 配置分析:"
    echo "----------------------------------------"
    
    # 检查 Nginx 配置
    local nginx_config="/etc/nginx/nginx.conf"
    if [[ -f "$nginx_config" ]]; then
        local current_workers=$(grep 'worker_processes' "$nginx_config" 2>/dev/null | grep -o '[0-9]*' | head -1)
        local current_connections=$(grep 'worker_connections' "$nginx_config" 2>/dev/null | grep -o '[0-9]*' | head -1)
        
        echo "  当前 worker_processes: $current_workers"
        echo "  当前 worker_connections: $current_connections"
        
        # 优化建议
        local optimal_workers=$cpu_cores
        local optimal_connections=1024
        
        if [[ $total_memory -gt 8192 ]]; then
            optimal_connections=2048
        elif [[ $total_memory -gt 4096 ]]; then
            optimal_connections=1536
        fi
        
        if [[ "$current_workers" != "$optimal_workers" ]]; then
            echo "  🔧 建议: worker_processes 设置为 $optimal_workers (当前: $current_workers)"
        fi
        
        if [[ "$current_connections" != "$optimal_connections" ]]; then
            echo "  🔧 建议: worker_connections 设置为 $optimal_connections (当前: $current_connections)"
        fi
        
        # 检查其他优化项
        check_nginx_optimizations "$nginx_config"
    else
        echo "  ⚠️  Nginx 配置文件未找到"
    fi
}

# 检查 Nginx 其他优化项
check_nginx_optimizations() {
    local nginx_config="$1"
    
    # 检查 gzip 压缩
    if ! salt-call --local cmd.run "grep -q 'gzip on' $nginx_config" 2>/dev/null; then
        echo "  🔧 建议: 启用 gzip 压缩以提高传输效率"
    fi
    
    # 检查缓存配置
    if ! salt-call --local cmd.run "grep -q 'proxy_cache' $nginx_config" 2>/dev/null; then
        echo "  🔧 建议: 配置代理缓存以提高性能"
    fi
    
    # 检查 keepalive
    if ! salt-call --local cmd.run "grep -q 'keepalive_timeout' $nginx_config" 2>/dev/null; then
        echo "  🔧 建议: 配置 keepalive_timeout 以优化连接"
    fi
}

# 分析 MySQL 配置
analyze_mysql() {
    local system_info="$1"
    local cpu_cores=$(echo "$system_info" | cut -d'|' -f1)
    local total_memory=$(echo "$system_info" | cut -d'|' -f2)
    
    echo ""
    echo "MySQL 配置分析:"
    echo "----------------------------------------"
    
    # 检查 MySQL 服务状态
    local mysql_status=$(salt-call --local service.status mysql 2>/dev/null | grep -o "True\|False")
    
    if [[ "$mysql_status" == "True" ]]; then
        # 获取当前配置
        local current_buffer_pool=$(salt-call --local cmd.run "mysql -e 'SHOW VARIABLES LIKE \"innodb_buffer_pool_size\"'" 2>/dev/null | awk 'NR==2 {print $2}')
        local current_max_connections=$(salt-call --local cmd.run "mysql -e 'SHOW VARIABLES LIKE \"max_connections\"'" 2>/dev/null | awk 'NR==2 {print $2}')
        
        echo "  当前 innodb_buffer_pool_size: $current_buffer_pool"
        echo "  当前 max_connections: $current_max_connections"
        
        # 优化建议
        local optimal_buffer_pool=$((total_memory * 70 / 100))
        local optimal_max_connections=100
        
        if [[ $cpu_cores -gt 8 ]]; then
            optimal_max_connections=200
        elif [[ $cpu_cores -gt 4 ]]; then
            optimal_max_connections=150
        fi
        
        if [[ $current_buffer_pool -lt $optimal_buffer_pool ]]; then
            echo "  🔧 建议: innodb_buffer_pool_size 设置为 ${optimal_buffer_pool}M (当前: $current_buffer_pool)"
        fi
        
        if [[ $current_max_connections -lt $optimal_max_connections ]]; then
            echo "  🔧 建议: max_connections 设置为 $optimal_max_connections (当前: $current_max_connections)"
        fi
        
        # 检查其他优化项
        check_mysql_optimizations
    else
        echo "  ⚠️  MySQL 服务未运行"
    fi
}

# 检查 MySQL 其他优化项
check_mysql_optimizations() {
    # 检查查询缓存
    local query_cache=$(salt-call --local cmd.run "mysql -e 'SHOW VARIABLES LIKE \"query_cache_size\"'" 2>/dev/null | awk 'NR==2 {print $2}')
    if [[ "$query_cache" == "0" ]]; then
        echo "  🔧 建议: 启用查询缓存以提高查询性能"
    fi
    
    # 检查慢查询日志
    local slow_query_log=$(salt-call --local cmd.run "mysql -e 'SHOW VARIABLES LIKE \"slow_query_log\"'" 2>/dev/null | awk 'NR==2 {print $2}')
    if [[ "$slow_query_log" == "OFF" ]]; then
        echo "  🔧 建议: 启用慢查询日志以识别性能问题"
    fi
    
    # 检查 InnoDB 配置
    local innodb_log_file_size=$(salt-call --local cmd.run "mysql -e 'SHOW VARIABLES LIKE \"innodb_log_file_size\"'" 2>/dev/null | awk 'NR==2 {print $2}')
    if [[ $innodb_log_file_size -lt 256 ]]; then
        echo "  🔧 建议: 增加 innodb_log_file_size 到 256M 或更高"
    fi
}

# 分析 PHP-FPM 配置
analyze_php() {
    local system_info="$1"
    local cpu_cores=$(echo "$system_info" | cut -d'|' -f1)
    local total_memory=$(echo "$system_info" | cut -d'|' -f2)
    
    echo ""
    echo "PHP-FPM 配置分析:"
    echo "----------------------------------------"
    
    # 检查 PHP-FPM 配置
    local php_config="/etc/php/8.3/fpm/pool.d/www.conf"
    if [[ -f "$php_config" ]]; then
        local current_pm=$(salt-call --local cmd.run "grep 'pm =' $php_config" 2>/dev/null | awk '{print $3}')
        local current_max_children=$(salt-call --local cmd.run "grep 'pm.max_children' $php_config" 2>/dev/null | awk '{print $3}')
        
        echo "  当前 pm 模式: $current_pm"
        echo "  当前 pm.max_children: $current_max_children"
        
        # 优化建议
        local optimal_pm="dynamic"
        local optimal_max_children=$((cpu_cores * 2))
        
        if [[ $total_memory -lt 2048 ]]; then
            optimal_pm="ondemand"
        elif [[ $total_memory -gt 8192 ]]; then
            optimal_pm="static"
            optimal_max_children=$((cpu_cores * 4))
        fi
        
        if [[ "$current_pm" != "$optimal_pm" ]]; then
            echo "  🔧 建议: pm 模式设置为 $optimal_pm (当前: $current_pm)"
        fi
        
        if [[ $current_max_children -lt $optimal_max_children ]]; then
            echo "  🔧 建议: pm.max_children 设置为 $optimal_max_children (当前: $current_max_children)"
        fi
        
        # 检查其他优化项
        check_php_optimizations "$php_config"
    else
        echo "  ⚠️  PHP-FPM 配置文件未找到"
    fi
}

# 检查 PHP 其他优化项
check_php_optimizations() {
    local php_config="$1"
    
    # 检查内存限制
    local memory_limit=$(salt-call --local cmd.run "grep 'memory_limit' $php_config" 2>/dev/null | awk '{print $3}')
    if [[ -z "$memory_limit" ]]; then
        echo "  🔧 建议: 设置合适的 memory_limit"
    fi
    
    # 检查执行时间
    local max_execution_time=$(salt-call --local cmd.run "grep 'max_execution_time' $php_config" 2>/dev/null | awk '{print $3}')
    if [[ "$max_execution_time" == "0" ]]; then
        echo "  🔧 建议: 设置合理的 max_execution_time"
    fi
}

# 分析 Valkey 配置
analyze_valkey() {
    local system_info="$1"
    local total_memory=$(echo "$system_info" | cut -d'|' -f2)
    
    echo ""
    echo "Valkey 配置分析:"
    echo "----------------------------------------"
    
    # 检查 Valkey 服务状态
    local valkey_status=$(salt-call --local service.status valkey 2>/dev/null | grep -o "True\|False")
    
    if [[ "$valkey_status" == "True" ]]; then
        # 获取当前配置
        local current_maxmemory=$(salt-call --local cmd.run "valkey-cli config get maxmemory" 2>/dev/null | tail -1)
        local current_policy=$(salt-call --local cmd.run "valkey-cli config get maxmemory-policy" 2>/dev/null | tail -1)
        
        echo "  当前 maxmemory: $current_maxmemory"
        echo "  当前 maxmemory-policy: $current_policy"
        
        # 优化建议
        local optimal_maxmemory=$((total_memory / 4))
        
        if [[ "$current_maxmemory" == "0" ]]; then
            echo "  🔧 建议: 设置 maxmemory 为 ${optimal_maxmemory}mb"
        fi
        
        if [[ "$current_policy" != "allkeys-lru" ]]; then
            echo "  🔧 建议: 设置 maxmemory-policy 为 allkeys-lru"
        fi
        
        # 检查其他优化项
        check_valkey_optimizations
    else
        echo "  ⚠️  Valkey 服务未运行"
    fi
}

# 检查 Valkey 其他优化项
check_valkey_optimizations() {
    # 检查持久化配置
    local save_config=$(salt-call --local cmd.run "valkey-cli config get save" 2>/dev/null | tail -1)
    if [[ "$save_config" == '""' ]]; then
        echo "  🔧 建议: 配置合适的持久化策略"
    fi
    
    # 检查 TCP keepalive
    local tcp_keepalive=$(salt-call --local cmd.run "valkey-cli config get tcp-keepalive" 2>/dev/null | tail -1)
    if [[ "$tcp_keepalive" == "0" ]]; then
        echo "  🔧 建议: 启用 TCP keepalive"
    fi
}

# 分析系统配置
analyze_system() {
    local system_info="$1"
    local load_avg=$(echo "$system_info" | cut -d'|' -f4)
    
    echo ""
    echo "系统配置分析:"
    echo "----------------------------------------"
    
    # 分析系统负载
    local load_avg_num=$(echo "$load_avg" | awk '{print $1}' | sed 's/,//')
    local cpu_cores=$(echo "$system_info" | cut -d'|' -f1)
    
    if (( $(echo "$load_avg_num > $cpu_cores" | bc -l) )); then
        echo "  ⚠️  系统负载较高: $load_avg (CPU核心数: $cpu_cores)"
        echo "  🔧 建议: 检查是否有资源密集型进程运行"
    else
        echo "  ✅ 系统负载正常: $load_avg"
    fi
    
    # 检查磁盘使用率
    local disk_usage=$(salt-call --local cmd.run "df -h /" 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 80 ]]; then
        echo "  ⚠️  磁盘使用率较高: ${disk_usage}%"
        echo "  🔧 建议: 清理不必要的文件或增加磁盘空间"
    else
        echo "  ✅ 磁盘使用率正常: ${disk_usage}%"
    fi
    
    # 检查内存使用率
    local memory_usage=$(salt-call --local cmd.run "free | awk 'NR==2{printf \"%.0f\", \$3/\$2*100}'" 2>/dev/null)
    if [[ $memory_usage -gt 85 ]]; then
        echo "  ⚠️  内存使用率较高: ${memory_usage}%"
        echo "  🔧 建议: 检查内存泄漏或增加内存"
    else
        echo "  ✅ 内存使用率正常: ${memory_usage}%"
    fi
}

# 生成优化建议
generate_optimization_recommendations() {
    echo ""
    echo "优化建议生成:"
    echo "----------------------------------------"
    
    # 创建优化建议文件
    local recommendations_file="/tmp/saltgoat_optimization_recommendations.txt"
    
    cat > "$recommendations_file" << EOF
SaltGoat 智能优化建议
生成时间: $(date)
==========================================

基于系统资源分析的优化建议:

1. 系统资源优化:
   - 根据 CPU 核心数和内存大小调整各服务配置
   - 监控系统负载和资源使用率
   - 定期清理日志和临时文件

2. Nginx 优化:
   - 调整 worker_processes 和 worker_connections
   - 启用 gzip 压缩和缓存
   - 配置合适的 keepalive_timeout

3. MySQL 优化:
   - 调整 innodb_buffer_pool_size
   - 设置合适的 max_connections
   - 启用查询缓存和慢查询日志

4. PHP-FPM 优化:
   - 选择合适的 pm 模式
   - 调整 pm.max_children
   - 设置合理的内存和执行时间限制

5. Valkey 优化:
   - 设置合适的 maxmemory
   - 配置内存淘汰策略
   - 启用 TCP keepalive

建议使用 'saltgoat auto-tune' 命令自动应用这些优化配置。
EOF
    
    echo "  ✅ 优化建议已生成: $recommendations_file"
}

# 显示优化建议总结
display_optimization_summary() {
    echo "📊 优化建议总结:"
    echo ""
    echo "🔧 配置优化:"
    echo "  - 使用 'saltgoat auto-tune' 自动调优配置"
    echo "  - 根据系统资源调整各服务参数"
    echo ""
    echo "📈 性能优化:"
    echo "  - 启用缓存和压缩功能"
    echo "  - 优化数据库查询和索引"
    echo "  - 调整进程和连接数限制"
    echo ""
    echo "🔍 监控优化:"
    echo "  - 使用 'saltgoat benchmark' 进行性能测试"
    echo "  - 定期检查系统负载和资源使用"
    echo "  - 监控服务状态和错误日志"
    echo ""
    echo "💡 建议操作:"
    echo "  1. 运行 'saltgoat auto-tune' 应用自动调优"
    echo "  2. 运行 'saltgoat benchmark' 测试性能"
    echo "  3. 定期运行 'saltgoat optimize' 检查优化状态"
}

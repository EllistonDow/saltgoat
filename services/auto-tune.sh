#!/bin/bash
# 自动调优模块 - 完全使用 Salt 原生功能
# services/auto-tune.sh

# 自动调优配置
auto_tune() {
    log_highlight "SaltGoat 自动调优配置..."
    
    echo "系统资源分析:"
    echo "=========================================="
    
    # 获取系统资源信息
    local cpu_cores=$(nproc)
    local total_memory=$(free -m | awk 'NR==2{print $2}')
    local disk_space=$(df / | awk 'NR==2{print $2}')
    
    echo "CPU 核心数: $cpu_cores"
    echo "总内存: $total_memory MB"
    echo "磁盘空间: $((disk_space / 1024 / 1024)) GB"
    
    echo ""
    echo "自动调优建议:"
    echo "=========================================="
    
    # Nginx 调优
    auto_tune_nginx "$cpu_cores" "$total_memory"
    
    # MySQL 调优
    auto_tune_mysql "$cpu_cores" "$total_memory"
    
    # PHP-FPM 调优
    auto_tune_php "$cpu_cores" "$total_memory"
    
    # Valkey 调优
    auto_tune_valkey "$total_memory"
    
    echo ""
    echo "应用调优配置:"
    echo "=========================================="
    
    # 询问是否应用配置
    read -p "是否应用这些优化配置？(y/N): " apply_config
    if [[ "$apply_config" == "y" || "$apply_config" == "Y" ]]; then
        apply_auto_tune_config
    else
        log_info "调优配置已生成但未应用"
    fi
}

# Nginx 自动调优
auto_tune_nginx() {
    local cpu_cores="$1"
    local total_memory="$2"
    
    echo "Nginx 调优建议:"
    echo "----------------------------------------"
    
    # Worker 进程数
    local worker_processes=$cpu_cores
    echo "  worker_processes: $worker_processes"
    
    # Worker 连接数
    local worker_connections=1024
    if [[ $total_memory -gt 8192 ]]; then
        worker_connections=2048
    elif [[ $total_memory -gt 4096 ]]; then
        worker_connections=1536
    fi
    echo "  worker_connections: $worker_connections"
    
    # 缓存配置
    local proxy_cache_size="1g"
    if [[ $total_memory -gt 8192 ]]; then
        proxy_cache_size="2g"
    fi
    echo "  proxy_cache_size: $proxy_cache_size"
    
    # 保存配置到 Pillar
    cat > /tmp/nginx_auto_tune.sls << EOF
nginx_auto_tune:
  nginx:
    worker_processes: $worker_processes
    worker_connections: $worker_connections
    proxy_cache_size: $proxy_cache_size
    gzip_comp_level: 6
    gzip_min_length: 1024
    keepalive_timeout: 65
    client_max_body_size: 64m
EOF
    
    echo "  ✅ Nginx 配置已生成"
}

# MySQL 自动调优
auto_tune_mysql() {
    local cpu_cores="$1"
    local total_memory="$2"
    
    echo ""
    echo "MySQL 调优建议:"
    echo "----------------------------------------"
    
    # InnoDB 缓冲池大小 (总内存的 70-80%)
    local innodb_buffer_pool_size=$((total_memory * 70 / 100))
    echo "  innodb_buffer_pool_size: ${innodb_buffer_pool_size}M"
    
    # 最大连接数
    local max_connections=100
    if [[ $cpu_cores -gt 8 ]]; then
        max_connections=200
    elif [[ $cpu_cores -gt 4 ]]; then
        max_connections=150
    fi
    echo "  max_connections: $max_connections"
    
    # 查询缓存
    local query_cache_size="32M"
    if [[ $total_memory -gt 8192 ]]; then
        query_cache_size="64M"
    fi
    echo "  query_cache_size: $query_cache_size"
    
    # 保存配置到 Pillar
    cat > /tmp/mysql_auto_tune.sls << EOF
mysql_auto_tune:
  mysql:
    innodb_buffer_pool_size: ${innodb_buffer_pool_size}M
    max_connections: $max_connections
    query_cache_size: $query_cache_size
    innodb_log_file_size: 256M
    innodb_log_buffer_size: 16M
    key_buffer_size: 32M
    sort_buffer_size: 2M
    read_buffer_size: 2M
    read_rnd_buffer_size: 8M
    myisam_sort_buffer_size: 64M
    thread_cache_size: 8
    table_open_cache: 400
EOF
    
    echo "  ✅ MySQL 配置已生成"
}

# PHP-FPM 自动调优
auto_tune_php() {
    local cpu_cores="$1"
    local total_memory="$2"
    
    echo ""
    echo "PHP-FPM 调优建议:"
    echo "----------------------------------------"
    
    # PM 模式选择
    local pm_mode="dynamic"
    if [[ $total_memory -lt 2048 ]]; then
        pm_mode="ondemand"
    elif [[ $total_memory -gt 8192 ]]; then
        pm_mode="static"
    fi
    echo "  pm: $pm_mode"
    
    # 进程数量
    local max_children=$((cpu_cores * 2))
    if [[ $pm_mode == "static" ]]; then
        max_children=$((cpu_cores * 4))
    fi
    echo "  pm.max_children: $max_children"
    
    # 内存限制
    local memory_limit="256M"
    if [[ $total_memory -gt 8192 ]]; then
        memory_limit="512M"
    elif [[ $total_memory -lt 2048 ]]; then
        memory_limit="128M"
    fi
    echo "  memory_limit: $memory_limit"
    
    # 保存配置到 Pillar
    cat > /tmp/php_auto_tune.sls << EOF
php_auto_tune:
  php:
    pm: $pm_mode
    pm_max_children: $max_children
    pm_start_servers: $((max_children / 2))
    pm_min_spare_servers: $((max_children / 4))
    pm_max_spare_servers: $((max_children * 3 / 4))
    memory_limit: $memory_limit
    max_execution_time: 300
    max_input_time: 300
    post_max_size: 64M
    upload_max_filesize: 64M
EOF
    
    echo "  ✅ PHP-FPM 配置已生成"
}

# Valkey 自动调优
auto_tune_valkey() {
    local total_memory="$1"
    
    echo ""
    echo "Valkey 调优建议:"
    echo "----------------------------------------"
    
    # 最大内存
    local maxmemory=$((total_memory / 4))
    echo "  maxmemory: ${maxmemory}mb"
    
    # 淘汰策略
    local maxmemory_policy="allkeys-lru"
    echo "  maxmemory-policy: $maxmemory_policy"
    
    # 保存配置
    cat > /tmp/valkey_auto_tune.sls << EOF
valkey_auto_tune:
  valkey:
    maxmemory: ${maxmemory}mb
    maxmemory_policy: $maxmemory_policy
    tcp_keepalive: 300
    timeout: 300
    tcp_backlog: 511
EOF
    
    echo "  ✅ Valkey 配置已生成"
}

# 应用自动调优配置
apply_auto_tune_config() {
    log_highlight "应用自动调优配置..."
    
    # 创建调优 Pillar 文件
    local pillar_dir="/etc/salt/pillar"
    sudo mkdir -p "$pillar_dir"
    
    # 合并所有调优配置
    cat > /tmp/auto_tune_pillar.sls << EOF
# SaltGoat 自动调优配置
# 基于系统资源自动生成的优化配置

EOF
    
    # 添加各个组件的配置
    if [[ -f /tmp/nginx_auto_tune.sls ]]; then
        cat /tmp/nginx_auto_tune.sls >> /tmp/auto_tune_pillar.sls
        echo "" >> /tmp/auto_tune_pillar.sls
    fi
    
    if [[ -f /tmp/mysql_auto_tune.sls ]]; then
        cat /tmp/mysql_auto_tune.sls >> /tmp/auto_tune_pillar.sls
        echo "" >> /tmp/auto_tune_pillar.sls
    fi
    
    if [[ -f /tmp/php_auto_tune.sls ]]; then
        cat /tmp/php_auto_tune.sls >> /tmp/auto_tune_pillar.sls
        echo "" >> /tmp/php_auto_tune_pillar.sls
    fi
    
    if [[ -f /tmp/valkey_auto_tune.sls ]]; then
        cat /tmp/valkey_auto_tune.sls >> /tmp/auto_tune_pillar.sls
        echo "" >> /tmp/auto_tune_pillar.sls
    fi
    
    # 复制到 Pillar 目录
    sudo cp /tmp/auto_tune_pillar.sls "$pillar_dir/"
    
    # 应用配置
    log_info "应用 Nginx 调优配置..."
    salt-call --local state.apply nginx.auto_tune 2>/dev/null || log_warning "Nginx 调优配置应用失败"
    
    log_info "应用 MySQL 调优配置..."
    salt-call --local state.apply mysql.auto_tune 2>/dev/null || log_warning "MySQL 调优配置应用失败"
    
    log_info "应用 PHP-FPM 调优配置..."
    salt-call --local state.apply php.auto_tune 2>/dev/null || log_warning "PHP-FPM 调优配置应用失败"
    
    log_info "应用 Valkey 调优配置..."
    salt-call --local state.apply valkey.auto_tune 2>/dev/null || log_warning "Valkey 调优配置应用失败"
    
    # 重启服务
    log_info "重启服务以应用新配置..."
    sudo systemctl reload nginx 2>/dev/null || true
    sudo systemctl reload php8.3-fpm 2>/dev/null || true
    sudo systemctl restart valkey 2>/dev/null || true
    
    log_success "自动调优配置应用完成！"
    
    # 清理临时文件
    rm -f /tmp/*_auto_tune.sls /tmp/auto_tune_pillar.sls
}

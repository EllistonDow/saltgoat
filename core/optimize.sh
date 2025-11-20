#!/bin/bash
# 优化管理模块
# core/optimize.sh

# Magento 优化配置文件路径
MAGENTO_OPTIMIZE_PILLAR="${SCRIPT_DIR}/salt/pillar/magento-optimize.sls"
MAGENTO_OPTIMIZE_REPORT="/var/lib/saltgoat/reports/magento-optimize-summary.txt"
MAGENTO_SEARCH_ROOTS=("/var/www" "/srv" "/opt/magento")
MAGENTO_SITE_STATUS="unknown"
MAGENTO_SITE_ROOT=""
MAGENTO_ENV_PATH=""
MAGENTO_SITE_LABEL=""

escape_yaml_value() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

magento_env_from_hint() {
    local hint="$1"

    [[ -z "$hint" ]] && return 1

    if [[ -f "$hint" ]]; then
        echo "$hint"
        return 0
    fi

    if [[ -d "$hint" && -f "$hint/app/etc/env.php" ]]; then
        echo "$hint/app/etc/env.php"
        return 0
    fi

    if [[ "$hint" == /* ]]; then
        local candidate="$hint"
        if [[ "${candidate##*/}" != "env.php" ]]; then
            candidate="${hint%/}/app/etc/env.php"
        fi
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    fi

    local base
    for base in "${MAGENTO_SEARCH_ROOTS[@]}"; do
        if [[ -d "${base}/${hint}" && -f "${base}/${hint}/app/etc/env.php" ]]; then
            echo "${base}/${hint}/app/etc/env.php"
            return 0
        fi
    done

    return 1
}

detect_magento_site() {
    local hint="$1"
    MAGENTO_SITE_STATUS="unknown"
    MAGENTO_SITE_ROOT=""
    MAGENTO_ENV_PATH=""
    MAGENTO_SITE_LABEL=""

    if [[ -n "$hint" ]]; then
        local resolved=""
        if resolved=$(magento_env_from_hint "$hint"); then
            MAGENTO_ENV_PATH="$resolved"
            MAGENTO_SITE_ROOT="$(dirname "$(dirname "$(dirname "$resolved")")")"
            MAGENTO_SITE_LABEL="$(basename "$MAGENTO_SITE_ROOT")"
            MAGENTO_SITE_STATUS="found"
            return 0
        fi

        log_error "未找到 Magento env.php 文件（参数: ${hint})"
        log_info "可以传入站点名称（如 shop01）、站点目录（/var/www/shop01）或 env.php 的绝对路径。"
        MAGENTO_SITE_STATUS="missing"
        return 1
    fi

    local -a search_dirs=()
    local dir
    for dir in "${MAGENTO_SEARCH_ROOTS[@]}"; do
        [[ -d "$dir" ]] && search_dirs+=("$dir")
    done

    if ((${#search_dirs[@]} == 0)); then
        MAGENTO_SITE_STATUS="missing"
        return 0
    fi

    local -a env_candidates=()
    local root
    for root in "${search_dirs[@]}"; do
        while IFS= read -r path; do
            env_candidates+=("$path")
        done < <(find "$root" -maxdepth 5 -path '*/app/etc/env.php' -type f 2>/dev/null | sort -u || true)
    done

    local count=${#env_candidates[@]}
    if (( count == 1 )); then
        MAGENTO_ENV_PATH="${env_candidates[0]}"
        MAGENTO_SITE_ROOT="$(dirname "$(dirname "$(dirname "$MAGENTO_ENV_PATH")")")"
        MAGENTO_SITE_LABEL="$(basename "$MAGENTO_SITE_ROOT")"
        MAGENTO_SITE_STATUS="found"
        return 0
    elif (( count == 0 )); then
        MAGENTO_SITE_STATUS="missing"
        return 0
    fi

    MAGENTO_SITE_STATUS="ambiguous"
    log_warning "检测到多个 Magento 站点:"
    local path
    for path in "${env_candidates[@]}"; do
        log_warning "  - ${path}"
    done
    log_error "请使用 '--site <站点名称|绝对路径|env.php 文件>' 指定目标站点后再运行。"
    return 1
}

update_magento_optimize_pillar() {
    local profile="${1:-auto}"
    local site="${2:-}"
    local env_path="${3:-}"
    local site_root="${4:-}"
    local detection_status="${5:-unknown}"
    local site_hint="${6:-}"

    mkdir -p "${SCRIPT_DIR}/salt/pillar"
    mkdir -p "$(dirname "$MAGENTO_OPTIMIZE_REPORT")"

    cat >"$MAGENTO_OPTIMIZE_PILLAR" <<EOF
magento_optimize:
  profile: "$(escape_yaml_value "$profile")"
  site: "$(escape_yaml_value "$site")"
  site_hint: "$(escape_yaml_value "$site_hint")"
  env_path: "$(escape_yaml_value "$env_path")"
  site_root: "$(escape_yaml_value "$site_root")"
  detection_status: "$(escape_yaml_value "$detection_status")"
  overrides: {}
EOF

    log_info "已更新 Magento 优化配置: profile=${profile:-auto} site=${site:-<none>}"
}

show_magento_optimize_report() {
    if [[ -f "$MAGENTO_OPTIMIZE_REPORT" ]]; then
        log_highlight "Magento 优化报告:"
        cat "$MAGENTO_OPTIMIZE_REPORT"
    else
        log_warning "尚未找到 Magento 优化报告 (期待位置: ${MAGENTO_OPTIMIZE_REPORT})"
    fi
}

# Magento 优化
optimize_magento() {
    local profile="auto"
    local site=""
    local dry_run=false
    local show_results=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile)
                profile="$2"
                shift 2
                ;;
            --site)
                site="$2"
                shift 2
                ;;
            --dry-run|--plan)
                dry_run=true
                shift
                ;;
            --show-results)
                show_results=true
                shift
                ;;
            --help|-h)
                cat <<'USAGE'
用法: saltgoat optimize magento [选项]
  --profile <auto|low|standard|medium|high|enterprise>  指定优化档位 (默认: auto)
  --site <name>                                         可选，记录当前站点
  --dry-run | --plan                                    仅模拟执行，不修改系统
  --show-results                                        优化结束后打印报告
USAGE
                return 0
                ;;
            *)
                log_warning "忽略未知参数: $1"
                shift
                ;;
        esac
    done

    local original_site="$site"
    if ! detect_magento_site "$site"; then
        return 1
    fi

    local display_site="$site"
    if [[ -z "$display_site" && -n "$MAGENTO_SITE_LABEL" ]]; then
        display_site="$MAGENTO_SITE_LABEL"
    fi

    update_magento_optimize_pillar "$profile" "$display_site" "$MAGENTO_ENV_PATH" "$MAGENTO_SITE_ROOT" "$MAGENTO_SITE_STATUS" "$original_site"

    case "$MAGENTO_SITE_STATUS" in
        found)
            log_highlight "Magento 站点: ${display_site:-$MAGENTO_SITE_LABEL} (${MAGENTO_SITE_ROOT})"
            log_info "env.php 路径: ${MAGENTO_ENV_PATH}"
            ;;
        missing)
            log_warning "未检测到 Magento env.php，仍将应用系统级优化。"
            ;;
    esac

    local state_cmd=(salt-call --local state.apply optional.magento-optimization)
    if [[ "$dry_run" == true ]]; then
        log_highlight "以 dry-run 模式执行 Magento 优化 (不做更改)..."
        state_cmd+=("test=True")
    else
        log_info "开始优化 Magento 配置..."
    fi

    "${state_cmd[@]}"

    if [[ "$dry_run" == true ]]; then
        log_success "Magento 优化 dry-run 完成 (未做更改)"
    else
        log_success "Magento 优化完成"
    fi

    if [[ "$show_results" == true ]]; then
        show_magento_optimize_report
    else
        log_info "可使用 '--show-results' 查看最近的优化报告"
    fi
}


# ----- 智能优化建议（原 modules/optimization/optimize.sh） -----

# 智能优化建议模块 - 完全使用 Salt 原生功能
# services/optimize.sh

# 智能优化建议
optimize() {
    log_highlight "SaltGoat 智能优化建议..."
    
    echo "系统分析和优化建议"
    echo "=========================================="
    
    # 收集系统信息
    local system_info
    system_info=$(collect_system_info)
    
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
    local cpu_cores
    cpu_cores=$(nproc)
    local total_memory
    total_memory=$(free -m | awk 'NR==2{print $2}')
    local disk_space
    disk_space=$(df / | awk 'NR==2{print $2}')
    local load_avg
    load_avg=$(uptime | grep -o 'load average:.*' | cut -d: -f2)
    
    # 返回系统信息（用|分隔）
    echo "$cpu_cores|$total_memory|$disk_space|$load_avg"
}

# 分析 Nginx 配置
analyze_nginx() {
    local system_info="$1"
    local cpu_cores
    cpu_cores=$(echo "$system_info" | cut -d'|' -f1)
    local total_memory
    total_memory=$(echo "$system_info" | cut -d'|' -f2)
    
    echo ""
    echo "Nginx 配置分析:"
    echo "----------------------------------------"
    
    # 检查 Nginx 配置
    local nginx_config="/etc/nginx/nginx.conf"
    if [[ -f "$nginx_config" ]]; then
        local current_workers
        current_workers=$(grep 'worker_processes' "$nginx_config" 2>/dev/null | grep -o '[0-9]*' | head -1)
        local current_connections
        current_connections=$(grep 'worker_connections' "$nginx_config" 2>/dev/null | grep -o '[0-9]*' | head -1)
        
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
            echo "  建议: worker_processes 设置为 $optimal_workers (当前: $current_workers)"
        fi
        
        if [[ "$current_connections" != "$optimal_connections" ]]; then
            echo "  建议: worker_connections 设置为 $optimal_connections (当前: $current_connections)"
        fi
        
        # 检查其他优化项
        check_nginx_optimizations "$nginx_config"
    else
        echo "  WARN: Nginx 配置文件未找到"
    fi
}

# 检查 Nginx 其他优化项
check_nginx_optimizations() {
    local nginx_config="$1"
    
    # 检查 gzip 压缩
    if ! salt-call --local cmd.run "grep -q 'gzip on' $nginx_config" 2>/dev/null; then
        echo "  建议: 启用 gzip 压缩以提高传输效率"
    fi
    
    # 检查缓存配置
    if ! salt-call --local cmd.run "grep -q 'proxy_cache' $nginx_config" 2>/dev/null; then
        echo "  建议: 配置代理缓存以提高性能"
    fi
    
    # 检查 keepalive
    if ! salt-call --local cmd.run "grep -q 'keepalive_timeout' $nginx_config" 2>/dev/null; then
        echo "  建议: 配置 keepalive_timeout 以优化连接"
    fi
}

# 分析 MySQL 配置
analyze_mysql() {
    local system_info="$1"
    local cpu_cores
    cpu_cores=$(echo "$system_info" | cut -d'|' -f1)
    local total_memory
    total_memory=$(echo "$system_info" | cut -d'|' -f2)
    
    echo ""
    echo "MySQL 配置分析:"
    echo "----------------------------------------"
    
    # 检查 MySQL 服务状态
    local mysql_status
    mysql_status=$(salt-call --local service.status mysql 2>/dev/null | grep -o "True\|False")
    
    if [[ "$mysql_status" == "True" ]]; then
        # 获取当前配置
        local current_buffer_pool
        current_buffer_pool=$(salt-call --local cmd.run "mysql -e 'SHOW VARIABLES LIKE \"innodb_buffer_pool_size\"'" 2>/dev/null | awk 'NR==2 {print $2}')
        local current_max_connections
        current_max_connections=$(salt-call --local cmd.run "mysql -e 'SHOW VARIABLES LIKE \"max_connections\"'" 2>/dev/null | awk 'NR==2 {print $2}')
        
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
            echo "  建议: innodb_buffer_pool_size 设置为 ${optimal_buffer_pool}M (当前: $current_buffer_pool)"
        fi
        
        if [[ $current_max_connections -lt $optimal_max_connections ]]; then
            echo "  建议: max_connections 设置为 $optimal_max_connections (当前: $current_max_connections)"
        fi
        
        # 检查其他优化项
        check_mysql_optimizations
    else
        echo "  WARN: MySQL 服务未运行"
    fi
}

# 检查 MySQL 其他优化项
check_mysql_optimizations() {
    # 检查查询缓存
    local query_cache
    query_cache=$(salt-call --local cmd.run "mysql -e 'SHOW VARIABLES LIKE \"query_cache_size\"'" 2>/dev/null | awk 'NR==2 {print $2}')
    if [[ "$query_cache" == "0" ]]; then
        echo "  建议: 启用查询缓存以提高查询性能"
    fi
    
    # 检查慢查询日志
    local slow_query_log
    slow_query_log=$(salt-call --local cmd.run "mysql -e 'SHOW VARIABLES LIKE \"slow_query_log\"'" 2>/dev/null | awk 'NR==2 {print $2}')
    if [[ "$slow_query_log" == "OFF" ]]; then
        echo "  建议: 启用慢查询日志以识别性能问题"
    fi
    
    # 检查 InnoDB 配置
    local innodb_log_file_size
    innodb_log_file_size=$(salt-call --local cmd.run "mysql -e 'SHOW VARIABLES LIKE \"innodb_log_file_size\"'" 2>/dev/null | awk 'NR==2 {print $2}')
    if [[ $innodb_log_file_size -lt 256 ]]; then
        echo "  建议: 增加 innodb_log_file_size 到 256M 或更高"
    fi
}

# 分析 PHP-FPM 配置
analyze_php() {
    local system_info="$1"
    local cpu_cores
    cpu_cores=$(echo "$system_info" | cut -d'|' -f1)
    local total_memory
    total_memory=$(echo "$system_info" | cut -d'|' -f2)
    
    echo ""
    echo "PHP-FPM 配置分析:"
    echo "----------------------------------------"
    
    local pool_dir="/etc/php/8.3/fpm/pool.d"
    if [[ ! -d "$pool_dir" ]]; then
        echo "  WARN: PHP-FPM 池目录不存在 ($pool_dir)"
        return
    fi

    mapfile -t pool_files < <(find "$pool_dir" -maxdepth 1 -type f -name '*.conf' -print 2>/dev/null | sort)
    if [[ ${#pool_files[@]} -eq 0 ]]; then
        echo "  WARN: 未检测到任何 PHP-FPM 池配置"
        return
    fi

    local reserve_mb=4096
    if [[ $total_memory -lt $reserve_mb ]]; then
        reserve_mb=$((total_memory / 2))
    fi
    local available_mb=$((total_memory - reserve_mb))
    if [[ $available_mb -le 0 ]]; then
        available_mb=$total_memory
    fi
    local pool_count=${#pool_files[@]}
    if [[ $pool_count -eq 0 ]]; then
        pool_count=1
    fi
    local per_pool_budget=$((available_mb / pool_count))
    if [[ $per_pool_budget -le 0 ]]; then
        per_pool_budget=$available_mb
    fi

    echo "  检测到 ${pool_count} 个 PHP-FPM 池 (可分配内存约 ${available_mb}MB)"

    local recommended_pm="dynamic"
    if [[ $total_memory -lt 2048 ]]; then
        recommended_pm="ondemand"
    fi

    local conf
    for conf in "${pool_files[@]}"; do
        [[ -f "$conf" ]] || continue
        local pool_name
        pool_name=$(grep -E '^\s*\[.+\]' "$conf" | head -1 | tr -d '[:space:]\[\]')
        if [[ -z "$pool_name" ]]; then
            pool_name=$(basename "$conf" .conf)
        fi
        local current_pm
        current_pm=$(grep -E '^\s*pm\s*=' "$conf" | tail -1 | awk -F'= *' '{print $2}')
        local current_max_children
        current_max_children=$(grep -E '^\s*pm\.max_children' "$conf" | tail -1 | awk -F'= *' '{print $2}')
        local memory_limit
        memory_limit=$(grep -E '^\s*php_admin_value\[memory_limit\]' "$conf" | tail -1 | awk -F'= *' '{print $2}')

        local estimated_child_mb=2048
        if [[ -n "$memory_limit" && "$memory_limit" =~ ^([0-9]+)([mMgG])$ ]]; then
            local mem_value=${BASH_REMATCH[1]}
            local mem_unit=${BASH_REMATCH[2]}
            if [[ "$mem_unit" == "g" || "$mem_unit" == "G" ]]; then
                estimated_child_mb=$((mem_value * 1024))
            else
                estimated_child_mb=$mem_value
            fi
        fi

        local cpu_cap=$(( (cpu_cores * 2) / pool_count ))
        if [[ $cpu_cap -lt 1 ]]; then
            cpu_cap=1
        fi
        local recommended_children=$((per_pool_budget / estimated_child_mb))
        if [[ $recommended_children -lt 1 ]]; then
            recommended_children=1
        fi
        if [[ $recommended_children -gt $cpu_cap ]]; then
            recommended_children=$cpu_cap
        fi

        echo "  池 ${pool_name}:"
        echo "    配置文件: $conf"
        echo "    pm: ${current_pm:-unknown}"
        echo "    pm.max_children: ${current_max_children:-unknown}"
        echo "    memory_limit: ${memory_limit:-未设置} (估算单进程约 ${estimated_child_mb}MB)"

        if [[ -n "$current_pm" && "$current_pm" != "$recommended_pm" ]]; then
            echo "    建议: 将 pm 模式调整为 ${recommended_pm}（当前: $current_pm）"
        fi

        if [[ -n "$current_max_children" ]]; then
            if [[ "$current_max_children" =~ ^[0-9]+$ && $current_max_children -lt $recommended_children ]]; then
                echo "    建议: 将 pm.max_children 至少提升至 ${recommended_children}（当前: $current_max_children）"
            fi
        else
            echo "    建议: 为该池显式设置 pm.max_children，推荐值 ≥ ${recommended_children}"
        fi

        check_php_optimizations "$conf"
    done
}

# 检查 PHP 其他优化项
check_php_optimizations() {
    local php_config="$1"
    
    # 检查内存限制
    local memory_limit
    memory_limit=$(salt-call --local cmd.run "grep 'memory_limit' $php_config" 2>/dev/null | awk '{print $3}')
    if [[ -z "$memory_limit" ]]; then
        echo "  建议: 设置合适的 memory_limit"
    fi
    
    # 检查执行时间
    local max_execution_time
    max_execution_time=$(salt-call --local cmd.run "grep 'max_execution_time' $php_config" 2>/dev/null | awk '{print $3}')
    if [[ "$max_execution_time" == "0" ]]; then
        echo "  建议: 设置合理的 max_execution_time"
    fi
}

# 分析 Valkey 配置
analyze_valkey() {
    local system_info="$1"
    local total_memory
    total_memory=$(echo "$system_info" | cut -d'|' -f2)
    
    echo ""
    echo "Valkey 配置分析:"
    echo "----------------------------------------"
    
    # 检查 Valkey 服务状态
    local valkey_status
    valkey_status=$(salt-call --local service.status valkey 2>/dev/null | grep -o "True\|False")
    
    if [[ "$valkey_status" == "True" ]]; then
        # 获取当前配置
        local current_maxmemory
        current_maxmemory=$(salt-call --local cmd.run "valkey-cli config get maxmemory" 2>/dev/null | tail -1)
        local current_policy
        current_policy=$(salt-call --local cmd.run "valkey-cli config get maxmemory-policy" 2>/dev/null | tail -1)
        
        echo "  当前 maxmemory: $current_maxmemory"
        echo "  当前 maxmemory-policy: $current_policy"
        
        # 优化建议
        local optimal_maxmemory=$((total_memory / 4))
        
        if [[ "$current_maxmemory" == "0" ]]; then
            echo "  建议: 设置 maxmemory 为 ${optimal_maxmemory}mb"
        fi
        
        if [[ "$current_policy" != "allkeys-lru" ]]; then
            echo "  建议: 设置 maxmemory-policy 为 allkeys-lru"
        fi
        
        # 检查其他优化项
        check_valkey_optimizations
    else
        echo "  WARN: Valkey 服务未运行"
    fi
}

# 检查 Valkey 其他优化项
check_valkey_optimizations() {
    # 检查持久化配置
    local save_config
    save_config=$(salt-call --local cmd.run "valkey-cli config get save" 2>/dev/null | tail -1)
    if [[ "$save_config" == '""' ]]; then
        echo "  建议: 配置合适的持久化策略"
    fi
    
    # 检查 TCP keepalive
    local tcp_keepalive
    tcp_keepalive=$(salt-call --local cmd.run "valkey-cli config get tcp-keepalive" 2>/dev/null | tail -1)
    if [[ "$tcp_keepalive" == "0" ]]; then
        echo "  建议: 启用 TCP keepalive"
    fi
}

# 分析系统配置
analyze_system() {
    local system_info="$1"
    local load_avg
    load_avg=$(echo "$system_info" | cut -d'|' -f4)
    
    echo ""
    echo "系统配置分析:"
    echo "----------------------------------------"
    
    # 分析系统负载
    local load_avg_num
    load_avg_num=$(echo "$load_avg" | awk '{print $1}' | sed 's/,//')
    local cpu_cores
    cpu_cores=$(echo "$system_info" | cut -d'|' -f1)
    
    if (( $(echo "$load_avg_num > $cpu_cores" | bc -l) )); then
        echo "  WARN: 系统负载较高: $load_avg (CPU核心数: $cpu_cores)"
        echo "  建议: 检查是否有资源密集型进程运行"
    else
        echo "  OK: 系统负载正常: $load_avg"
    fi
    
    # 检查磁盘使用率
    local disk_usage
    disk_usage=$(salt-call --local cmd.run "df -h /" 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 80 ]]; then
        echo "  WARN: 磁盘使用率较高: ${disk_usage}%"
        echo "  建议: 清理不必要的文件或增加磁盘空间"
    else
        echo "  OK: 磁盘使用率正常: ${disk_usage}%"
    fi
    
    # 检查内存使用率
    local memory_usage
    memory_usage=$(free | awk 'NR==2{printf "%.0f", $3/$2*100}')
    if [[ $memory_usage -gt 85 ]]; then
        echo "  WARN: 内存使用率较高: ${memory_usage}%"
        echo "  建议: 检查内存泄漏或增加内存"
    else
        echo "  OK: 内存使用率正常: ${memory_usage}%"
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
    
    echo "  OK: 优化建议已生成: $recommendations_file"
}

# 显示优化建议总结
display_optimization_summary() {
    echo "优化建议总结:"
    echo ""
    echo "配置优化:"
    echo "  - 使用 'saltgoat auto-tune' 自动调优配置"
    echo "  - 根据系统资源调整各服务参数"
    echo ""
    echo "性能优化:"
    echo "  - 启用缓存和压缩功能"
    echo "  - 优化数据库查询和索引"
    echo "  - 调整进程和连接数限制"
    echo ""
    echo "监控优化:"
    echo "  - 使用 'saltgoat benchmark' 进行性能测试"
    echo "  - 定期检查系统负载和资源使用"
    echo "  - 监控服务状态和错误日志"
    echo ""
    echo "建议操作:"
    echo "  1. 运行 'saltgoat auto-tune' 应用自动调优"
    echo "  2. 运行 'saltgoat benchmark' 测试性能"
    echo "  3. 定期运行 'saltgoat optimize' 检查优化状态"
}

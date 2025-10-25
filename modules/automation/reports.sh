#!/bin/bash
# 报告生成模块 - 全部使用 Salt 原生功能
# services/reports.sh

# 报告配置
REPORT_BASE_DIR="$HOME/saltgoat_reports"

# 确保报告目录存在
ensure_report_dirs() {
    salt-call --local file.mkdir "$REPORT_BASE_DIR" 2>/dev/null || true
    salt-call --local file.mkdir "$REPORT_BASE_DIR/system" 2>/dev/null || true
    salt-call --local file.mkdir "$REPORT_BASE_DIR/performance" 2>/dev/null || true
    salt-call --local file.mkdir "$REPORT_BASE_DIR/security" 2>/dev/null || true
    salt-call --local file.mkdir "$REPORT_BASE_DIR/maintenance" 2>/dev/null || true
}

get_service_status_flag() {
    local service="$1"
    local raw_status
    raw_status="$(salt-call --local service.status "$service" 2>/dev/null | grep -o "True\|False")"
    if [[ "$raw_status" == "True" ]]; then
        printf 'True\n'
    else
        printf 'False\n'
    fi
}

count_available_updates() {
    local updates
    updates="$(salt-call --local pkg.list_upgrades 2>/dev/null | grep -c ":" 2>/dev/null | tr -d '\n')"
    if [[ -z "$updates" ]]; then
        updates='0'
    fi
    printf '%s\n' "$updates"
}

# 系统健康报告
report_system_health() {
    local format="${1:-text}"
    local output_file="${2:-$REPORT_BASE_DIR/system/health_$(date +%Y%m%d_%H%M%S).$format}"
    
    log_highlight "生成系统健康报告..."
    ensure_report_dirs
    
    case "$format" in
        "text")
            generate_system_health_text "$output_file"
            ;;
        "json")
            generate_system_health_json "$output_file"
            ;;
        "html")
            generate_system_health_html "$output_file"
            ;;
        *)
            log_error "不支持的格式: $format"
            log_info "支持的格式: text, json, html"
            exit 1
            ;;
    esac
    
    log_success "系统健康报告已生成: $output_file"
}

# 生成文本格式系统健康报告
generate_system_health_text() {
    local output_file="$1"
    
    {
        echo "=========================================="
        echo "SaltGoat 系统健康报告"
        echo "生成时间: $(date)"
        echo "=========================================="
        echo ""
        
        echo "系统基本信息:"
        echo "----------------------------------------"
        echo "主机名: $(salt-call --local grains.get host 2>/dev/null)"
        echo "操作系统: $(salt-call --local grains.get osfullname 2>/dev/null)"
        echo "内核版本: $(salt-call --local grains.get kernelrelease 2>/dev/null)"
        echo "CPU 核心数: $(salt-call --local grains.get num_cpus 2>/dev/null)"
        echo "内存总量: $(salt-call --local grains.get mem_total 2>/dev/null) MB"
        echo ""
        
        echo "系统负载:"
        echo "----------------------------------------"
        salt-call --local status.loadavg 2>/dev/null
        echo ""
        
        echo "磁盘使用情况:"
        echo "----------------------------------------"
        salt-call --local disk.usage 2>/dev/null
        echo ""
        
        echo "内存使用情况:"
        echo "----------------------------------------"
        salt-call --local status.meminfo 2>/dev/null
        echo ""
        
        echo "关键服务状态:"
        echo "----------------------------------------"
        local services=("nginx" "mysql" "php8.3-fpm" "valkey" "rabbitmq" "opensearch")
        for service in "${services[@]}"; do
            local status
            status="$(get_service_status_flag "$service")"
            if [[ "$status" == "True" ]]; then
                echo "✅ $service: 运行中"
            else
                echo "❌ $service: 未运行"
            fi
        done
        echo ""
        
        echo "系统更新状态:"
        echo "----------------------------------------"
        local updates
        updates="$(count_available_updates)"
        if [[ "$updates" -gt 0 ]]; then
            echo "⚠️  有 $updates 个包可更新"
        else
            echo "✅ 系统已是最新版本"
        fi
        echo ""
        
        echo "网络连接状态:"
        echo "----------------------------------------"
        salt-call --local network.active_tcp 2>/dev/null | head -10
        echo ""
        
        echo "报告生成完成"
        echo "=========================================="
        
    } > "$output_file"
}

# 生成JSON格式系统健康报告
generate_system_health_json() {
    local output_file="$1"
    
    {
        echo "{"
        echo "  \"report_type\": \"system_health\","
        echo "  \"generated_at\": \"$(date -Iseconds)\","
        echo "  \"hostname\": \"$(salt-call --local grains.get host 2>/dev/null)\","
        echo "  \"os\": \"$(salt-call --local grains.get osfullname 2>/dev/null)\","
        echo "  \"kernel\": \"$(salt-call --local grains.get kernelrelease 2>/dev/null)\","
        echo "  \"cpu_cores\": $(salt-call --local grains.get num_cpus 2>/dev/null),"
        echo "  \"memory_total\": $(salt-call --local grains.get mem_total 2>/dev/null),"
        echo "  \"load_average\": $(salt-call --local status.loadavg 2>/dev/null | jq -c . 2>/dev/null || echo '{}'),"
        echo "  \"disk_usage\": $(salt-call --local disk.usage 2>/dev/null | jq -c . 2>/dev/null || echo '{}'),"
        echo "  \"memory_info\": $(salt-call --local status.meminfo 2>/dev/null | jq -c . 2>/dev/null || echo '{}'),"
        echo "  \"services\": {"
        
        local services=("nginx" "mysql" "php8.3-fpm" "valkey" "rabbitmq" "opensearch")
        local first=true
        for service in "${services[@]}"; do
            local status
            status="$(get_service_status_flag "$service")"
            local status_value
            if [[ "$status" == "True" ]]; then
                status_value="true"
            else
                status_value="false"
            fi
            if [[ "$first" == "true" ]]; then
                first=false
            else
                printf ',\n'
            fi
            printf '    "%s": %s' "$service" "$status_value"
        done
        printf '\n'
        echo "  },"
        
        local updates
        updates="$(count_available_updates)"
        echo "  \"updates_available\": $updates"
        echo "}"
        
    } > "$output_file"
}

# 生成HTML格式系统健康报告
generate_system_health_html() {
    local output_file="$1"
    
    {
        echo "<!DOCTYPE html>"
        echo "<html>"
        echo "<head>"
        echo "  <title>SaltGoat 系统健康报告</title>"
        echo "  <style>"
        echo "    body { font-family: Arial, sans-serif; margin: 20px; }"
        echo "    .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }"
        echo "    .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }"
        echo "    .success { color: green; }"
        echo "    .warning { color: orange; }"
        echo "    .error { color: red; }"
        echo "    table { border-collapse: collapse; width: 100%; }"
        echo "    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }"
        echo "    th { background-color: #f2f2f2; }"
        echo "  </style>"
        echo "</head>"
        echo "<body>"
        echo "  <div class='header'>"
        echo "    <h1>SaltGoat 系统健康报告</h1>"
        echo "    <p>生成时间: $(date)</p>"
        echo "  </div>"
        echo ""
        echo "  <div class='section'>"
        echo "    <h2>系统基本信息</h2>"
        echo "    <table>"
        echo "      <tr><th>项目</th><th>值</th></tr>"
        echo "      <tr><td>主机名</td><td>$(salt-call --local grains.get host 2>/dev/null)</td></tr>"
        echo "      <tr><td>操作系统</td><td>$(salt-call --local grains.get osfullname 2>/dev/null)</td></tr>"
        echo "      <tr><td>内核版本</td><td>$(salt-call --local grains.get kernelrelease 2>/dev/null)</td></tr>"
        echo "      <tr><td>CPU 核心数</td><td>$(salt-call --local grains.get num_cpus 2>/dev/null)</td></tr>"
        echo "      <tr><td>内存总量</td><td>$(salt-call --local grains.get mem_total 2>/dev/null) MB</td></tr>"
        echo "    </table>"
        echo "  </div>"
        echo ""
        echo "  <div class='section'>"
        echo "    <h2>关键服务状态</h2>"
        echo "    <table>"
        echo "      <tr><th>服务</th><th>状态</th></tr>"
        
        local services=("nginx" "mysql" "php8.3-fpm" "valkey" "rabbitmq" "opensearch")
        for service in "${services[@]}"; do
            local status
            status="$(get_service_status_flag "$service")"
            if [[ "$status" == "True" ]]; then
                echo "      <tr><td>$service</td><td class='success'>✅ 运行中</td></tr>"
            else
                echo "      <tr><td>$service</td><td class='error'>❌ 未运行</td></tr>"
            fi
        done
        
        echo "    </table>"
        echo "  </div>"
        echo ""
        echo "  <div class='section'>"
        echo "    <h2>系统更新状态</h2>"
        local updates
        updates="$(count_available_updates)"
        if [[ "$updates" -gt 0 ]]; then
            echo "    <p class='warning'>⚠️ 有 $updates 个包可更新</p>"
        else
            echo "    <p class='success'>✅ 系统已是最新版本</p>"
        fi
        echo "  </div>"
        echo ""
        echo "</body>"
        echo "</html>"
        
    } > "$output_file"
}

# 性能分析报告
report_performance() {
    local format="${1:-text}"
    local output_file="${2:-$REPORT_BASE_DIR/performance/performance_$(date +%Y%m%d_%H%M%S).$format}"
    
    log_highlight "生成性能分析报告..."
    ensure_report_dirs
    
    case "$format" in
        "text")
            generate_performance_text "$output_file"
            ;;
        "json")
            generate_performance_json "$output_file"
            ;;
        "html")
            generate_performance_html "$output_file"
            ;;
        *)
            log_error "不支持的格式: $format"
            log_info "支持的格式: text, json, html"
            exit 1
            ;;
    esac
    
    log_success "性能分析报告已生成: $output_file"
}

# 生成文本格式性能报告
generate_performance_text() {
    local output_file="$1"
    
    {
        echo "=========================================="
        echo "SaltGoat 性能分析报告"
        echo "生成时间: $(date)"
        echo "=========================================="
        echo ""
        
        echo "CPU 性能:"
        echo "----------------------------------------"
        echo "CPU 核心数: $(salt-call --local grains.get num_cpus 2>/dev/null)"
        echo "CPU 型号: $(salt-call --local grains.get cpu_model 2>/dev/null)"
        echo "系统负载:"
        salt-call --local status.loadavg 2>/dev/null
        echo ""
        
        echo "内存性能:"
        echo "----------------------------------------"
        salt-call --local status.meminfo 2>/dev/null
        echo ""
        
        echo "磁盘性能:"
        echo "----------------------------------------"
        salt-call --local disk.usage 2>/dev/null
        echo ""
        
        echo "网络性能:"
        echo "----------------------------------------"
        salt-call --local network.active_tcp 2>/dev/null | head -10
        echo ""
        
        echo "进程性能 (CPU 使用率前10):"
        echo "----------------------------------------"
        salt-call --local cmd.run "ps aux --sort=-%cpu | head -11" 2>/dev/null
        echo ""
        
        echo "进程性能 (内存使用率前10):"
        echo "----------------------------------------"
        salt-call --local cmd.run "ps aux --sort=-%mem | head -11" 2>/dev/null
        echo ""
        
        echo "报告生成完成"
        echo "=========================================="
        
    } > "$output_file"
}

# 生成JSON格式性能报告
generate_performance_json() {
    local output_file="$1"
    
    {
        echo "{"
        echo "  \"report_type\": \"performance\","
        echo "  \"generated_at\": \"$(date -Iseconds)\","
        echo "  \"cpu\": {"
        echo "    \"cores\": $(salt-call --local grains.get num_cpus 2>/dev/null),"
        echo "    \"model\": \"$(salt-call --local grains.get cpu_model 2>/dev/null)\","
        echo "    \"load_average\": $(salt-call --local status.loadavg 2>/dev/null | jq -c . 2>/dev/null || echo '{}')"
        echo "  },"
        echo "  \"memory\": $(salt-call --local status.meminfo 2>/dev/null | jq -c . 2>/dev/null || echo '{}'),"
        echo "  \"disk\": $(salt-call --local disk.usage 2>/dev/null | jq -c . 2>/dev/null || echo '{}'),"
        echo "  \"network\": $(salt-call --local network.active_tcp 2>/dev/null | jq -c . 2>/dev/null || echo '{}')"
        echo "}"
        
    } > "$output_file"
}

# 生成HTML格式性能报告
generate_performance_html() {
    local output_file="$1"
    
    {
        echo "<!DOCTYPE html>"
        echo "<html>"
        echo "<head>"
        echo "  <title>SaltGoat 性能分析报告</title>"
        echo "  <style>"
        echo "    body { font-family: Arial, sans-serif; margin: 20px; }"
        echo "    .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }"
        echo "    .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }"
        echo "    table { border-collapse: collapse; width: 100%; }"
        echo "    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }"
        echo "    th { background-color: #f2f2f2; }"
        echo "  </style>"
        echo "</head>"
        echo "<body>"
        echo "  <div class='header'>"
        echo "    <h1>SaltGoat 性能分析报告</h1>"
        echo "    <p>生成时间: $(date)</p>"
        echo "  </div>"
        echo ""
        echo "  <div class='section'>"
        echo "    <h2>CPU 性能</h2>"
        echo "    <p>CPU 核心数: $(salt-call --local grains.get num_cpus 2>/dev/null)</p>"
        echo "    <p>CPU 型号: $(salt-call --local grains.get cpu_model 2>/dev/null)</p>"
        echo "    <p>系统负载: $(salt-call --local status.loadavg 2>/dev/null)</p>"
        echo "  </div>"
        echo ""
        echo "  <div class='section'>"
        echo "    <h2>内存性能</h2>"
        echo "    <pre>$(salt-call --local status.meminfo 2>/dev/null)</pre>"
        echo "  </div>"
        echo ""
        echo "  <div class='section'>"
        echo "    <h2>磁盘性能</h2>"
        echo "    <pre>$(salt-call --local disk.usage 2>/dev/null)</pre>"
        echo "  </div>"
        echo ""
        echo "</body>"
        echo "</html>"
        
    } > "$output_file"
}

# 安全评估报告
report_security() {
    local format="${1:-text}"
    local output_file="${2:-$REPORT_BASE_DIR/security/security_$(date +%Y%m%d_%H%M%S).$format}"
    
    log_highlight "生成安全评估报告..."
    ensure_report_dirs
    
    case "$format" in
        "text")
            generate_security_text "$output_file"
            ;;
        "json")
            generate_security_json "$output_file"
            ;;
        "html")
            generate_security_html "$output_file"
            ;;
        *)
            log_error "不支持的格式: $format"
            log_info "支持的格式: text, json, html"
            exit 1
            ;;
    esac
    
    log_success "安全评估报告已生成: $output_file"
}

# 生成文本格式安全报告
generate_security_text() {
    local output_file="$1"
    
    {
        echo "=========================================="
        echo "SaltGoat 安全评估报告"
        echo "生成时间: $(date)"
        echo "=========================================="
        echo ""
        
        echo "开放端口扫描:"
        echo "----------------------------------------"
        salt-call --local network.active_tcp 2>/dev/null | head -20
        echo ""
        
        echo "服务安全状态:"
        echo "----------------------------------------"
        local services=("nginx" "mysql" "php8.3-fpm" "valkey" "rabbitmq" "opensearch")
        for service in "${services[@]}"; do
            local status
            status="$(get_service_status_flag "$service")"
            if [[ "$status" == "True" ]]; then
                echo "✅ $service: 运行中"
            else
                echo "❌ $service: 未运行"
            fi
        done
        echo ""
        
        echo "系统更新状态:"
        echo "----------------------------------------"
        local updates
        updates="$(count_available_updates)"
        if [[ "$updates" -gt 0 ]]; then
            echo "⚠️  有 $updates 个包可更新"
        else
            echo "✅ 系统已是最新版本"
        fi
        echo ""
        
        echo "用户安全状态:"
        echo "----------------------------------------"
        salt-call --local cmd.run "who" 2>/dev/null
        echo ""
        
        echo "最近登录记录:"
        echo "----------------------------------------"
        salt-call --local cmd.run "last -5" 2>/dev/null
        echo ""
        
        echo "报告生成完成"
        echo "=========================================="
        
    } > "$output_file"
}

# 生成JSON格式安全报告
generate_security_json() {
    local output_file="$1"
    
    {
        echo "{"
        echo "  \"report_type\": \"security\","
        echo "  \"generated_at\": \"$(date -Iseconds)\","
        echo "  \"open_ports\": $(salt-call --local network.active_tcp 2>/dev/null | jq -c . 2>/dev/null || echo '{}'),"
        echo "  \"services\": {"
        
        local services=("nginx" "mysql" "php8.3-fpm" "valkey" "rabbitmq" "opensearch")
        local first=true
        for service in "${services[@]}"; do
            local status
            status="$(get_service_status_flag "$service")"
            local status_value
            if [[ "$status" == "True" ]]; then
                status_value="true"
            else
                status_value="false"
            fi
            if [[ "$first" == "true" ]]; then
                first=false
            else
                printf ',\n'
            fi
            printf '    "%s": %s' "$service" "$status_value"
        done
        printf '\n'
        echo "  },"
        
        local updates
        updates="$(count_available_updates)"
        echo "  \"updates_available\": $updates"
        echo "}"
        
    } > "$output_file"
}

# 生成HTML格式安全报告
generate_security_html() {
    local output_file="$1"
    
    {
        echo "<!DOCTYPE html>"
        echo "<html>"
        echo "<head>"
        echo "  <title>SaltGoat 安全评估报告</title>"
        echo "  <style>"
        echo "    body { font-family: Arial, sans-serif; margin: 20px; }"
        echo "    .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }"
        echo "    .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }"
        echo "    .success { color: green; }"
        echo "    .warning { color: orange; }"
        echo "    .error { color: red; }"
        echo "    table { border-collapse: collapse; width: 100%; }"
        echo "    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }"
        echo "    th { background-color: #f2f2f2; }"
        echo "  </style>"
        echo "</head>"
        echo "<body>"
        echo "  <div class='header'>"
        echo "    <h1>SaltGoat 安全评估报告</h1>"
        echo "    <p>生成时间: $(date)</p>"
        echo "  </div>"
        echo ""
        echo "  <div class='section'>"
        echo "    <h2>服务安全状态</h2>"
        echo "    <table>"
        echo "      <tr><th>服务</th><th>状态</th></tr>"
        
        local services=("nginx" "mysql" "php8.3-fpm" "valkey" "rabbitmq" "opensearch")
        for service in "${services[@]}"; do
            local status
            status="$(get_service_status_flag "$service")"
            if [[ "$status" == "True" ]]; then
                echo "      <tr><td>$service</td><td class='success'>✅ 运行中</td></tr>"
            else
                echo "      <tr><td>$service</td><td class='error'>❌ 未运行</td></tr>"
            fi
        done
        
        echo "    </table>"
        echo "  </div>"
        echo ""
        echo "  <div class='section'>"
        echo "    <h2>系统更新状态</h2>"
        local updates
        updates="$(count_available_updates)"
        if [[ "$updates" -gt 0 ]]; then
            echo "    <p class='warning'>⚠️ 有 $updates 个包可更新</p>"
        else
            echo "    <p class='success'>✅ 系统已是最新版本</p>"
        fi
        echo "  </div>"
        echo ""
        echo "</body>"
        echo "</html>"
        
    } > "$output_file"
}

# 列出报告
report_list() {
    local report_type="${1:-all}"
    
    log_highlight "列出报告文件..."
    ensure_report_dirs
    
    case "$report_type" in
        "all")
            echo "所有报告文件:"
            echo "=========================================="
            salt-call --local file.find "$REPORT_BASE_DIR" type=f 2>/dev/null | sort -r
            ;;
        "system")
            echo "系统健康报告:"
            echo "=========================================="
            salt-call --local file.find "$REPORT_BASE_DIR/system" type=f 2>/dev/null | sort -r
            ;;
        "performance")
            echo "性能分析报告:"
            echo "=========================================="
            salt-call --local file.find "$REPORT_BASE_DIR/performance" type=f 2>/dev/null | sort -r
            ;;
        "security")
            echo "安全评估报告:"
            echo "=========================================="
            salt-call --local file.find "$REPORT_BASE_DIR/security" type=f 2>/dev/null | sort -r
            ;;
        *)
            log_error "未知的报告类型: $report_type"
            log_info "支持的类型: all, system, performance, security"
            exit 1
            ;;
    esac
}

# 清理报告
report_cleanup() {
    local days="${1:-30}"
    
    log_highlight "清理 $days 天前的报告文件..."
    ensure_report_dirs
    
    # 查找并删除旧报告
    salt-call --local file.find "$REPORT_BASE_DIR" type=f mtime=+"$days" 2>/dev/null | while read -r file; do
        salt-call --local file.remove "$file" 2>/dev/null
        echo "已删除: $file"
    done
    
    log_success "报告清理完成"
}

# 报告生成主函数
report_handler() {
    case "$1" in
        "system")
            report_system_health "$2" "$3"
            ;;
        "performance")
            report_performance "$2" "$3"
            ;;
        "security")
            report_security "$2" "$3"
            ;;
        "list")
            report_list "$2"
            ;;
        "cleanup")
            report_cleanup "$2"
            ;;
        *)
            log_error "未知的报告操作: $1"
            log_info "支持的操作:"
            log_info "  system [format] [output_file] - 生成系统健康报告"
            log_info "  performance [format] [output_file] - 生成性能分析报告"
            log_info "  security [format] [output_file] - 生成安全评估报告"
            log_info "  list [type] - 列出报告文件"
            log_info "  cleanup [days] - 清理旧报告"
            log_info ""
            log_info "支持的格式: text, json, html"
            log_info "支持的类型: all, system, performance, security"
            exit 1
            ;;
    esac
}

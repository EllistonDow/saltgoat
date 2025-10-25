#!/bin/bash
# 故障诊断模块
# services/diagnose.sh

# 诊断结果存储
DIAGNOSE_RESULTS=()

# 诊断Nginx
diagnose_nginx() {
    log_info "开始诊断 Nginx..."
    
    local issues=()
    local fixes=()
    
    # 检查Nginx是否运行
    # 检查Nginx服务状态 - 支持源码编译和包管理器安装
    if systemctl is-active --quiet nginx 2>/dev/null; then
        log_success "Nginx: 运行中 (systemd)"
    elif command -v nginx >/dev/null 2>&1 && pgrep -f "nginx: master process" >/dev/null 2>&1; then
        log_success "Nginx: 运行中 (手动启动)"
    else
        issues+=("Nginx服务未运行")
        fixes+=("sudo systemctl start nginx")
    fi
    
    # 检查Nginx配置
    if command -v nginx >/dev/null 2>&1; then
        if ! nginx -t -c /etc/nginx/nginx.conf 2>/dev/null; then
            issues+=("Nginx配置文件有语法错误")
            fixes+=("检查 /etc/nginx/nginx.conf 和 sites-enabled/ 目录下的配置文件")
        fi
    fi
    
    # 检查端口占用
    if ss -tlnp | grep -q ":80 "; then
        local port80_process
        port80_process="$(ss -tlnp | grep ":80 " | awk '{print $NF}' | cut -d',' -f2 | cut -d'=' -f2)"
        if [[ "$port80_process" != "nginx"* ]]; then
            issues+=("端口80被其他进程占用: $port80_process")
            fixes+=("检查并停止占用端口80的进程")
        fi
    fi
    
    # 检查日志文件
    local nginx_log_dir="/var/log/nginx"
    if [[ -d "$nginx_log_dir" ]]; then
        if [[ ! -f "$nginx_log_dir/error.log" ]]; then
            issues+=("Nginx错误日志文件不存在")
            fixes+=("检查Nginx日志配置")
        fi
    fi
    
    # 输出诊断结果
    if [[ ${#issues[@]} -eq 0 ]]; then
        log_success "Nginx诊断完成 - 未发现问题"
    else
        log_warning "Nginx诊断完成 - 发现 ${#issues[@]} 个问题:"
        for i in "${!issues[@]}"; do
            log_error "  ${issues[$i]}"
            log_info "  建议修复: ${fixes[$i]}"
        done
    fi
    
    # 存储诊断结果
    DIAGNOSE_RESULTS+=("nginx:${#issues[@]}:${issues[*]}")
}

# 诊断MySQL
diagnose_mysql() {
    log_info "开始诊断 MySQL..."
    
    local issues=()
    local fixes=()
    
    # 检查MySQL是否运行
    if ! systemctl is-active --quiet mysql 2>/dev/null; then
        issues+=("MySQL服务未运行")
        fixes+=("sudo systemctl start mysql")
    fi
    
    # 检查MySQL连接
    if ! mysql -e "SELECT 1;" 2>/dev/null; then
        issues+=("无法连接到MySQL数据库")
        fixes+=("检查MySQL服务状态和用户权限")
    fi
    
    # 检查MySQL配置
    local mysql_config="/etc/mysql/mysql.conf.d/mysqld.cnf"
    if [[ -f "$mysql_config" ]]; then
        if grep -q "bind-address.*0.0.0.0" "$mysql_config"; then
            issues+=("MySQL绑定到所有接口，存在安全风险")
            fixes+=("修改bind-address为127.0.0.1")
        fi
    fi
    
    # 检查MySQL日志
    local mysql_log_dir="/var/log/mysql"
    if [[ -d "$mysql_log_dir" ]]; then
        if [[ -f "$mysql_log_dir/error.log" ]]; then
            local error_count
            error_count="$(grep -c "ERROR" "$mysql_log_dir/error.log" 2>/dev/null || echo "0")"
            if [[ "$error_count" -gt 0 ]]; then
                issues+=("MySQL错误日志中发现 $error_count 个错误")
                fixes+=("检查MySQL错误日志: tail -f $mysql_log_dir/error.log")
            fi
        fi
    fi
    
    # 检查磁盘空间
    local mysql_data_dir="/var/lib/mysql"
    if [[ -d "$mysql_data_dir" ]]; then
        local disk_usage
        disk_usage="$(df "$mysql_data_dir" | awk 'NR==2{print $5}' | sed 's/%//')"
        if [[ "$disk_usage" -gt 90 ]]; then
            issues+=("MySQL数据目录磁盘使用率过高: ${disk_usage}%")
            fixes+=("清理MySQL日志文件或增加磁盘空间")
        fi
    fi
    
    # 输出诊断结果
    if [[ ${#issues[@]} -eq 0 ]]; then
        log_success "MySQL诊断完成 - 未发现问题"
    else
        log_warning "MySQL诊断完成 - 发现 ${#issues[@]} 个问题:"
        for i in "${!issues[@]}"; do
            log_error "  ${issues[$i]}"
            log_info "  建议修复: ${fixes[$i]}"
        done
    fi
    
    # 存储诊断结果
    DIAGNOSE_RESULTS+=("mysql:${#issues[@]}:${issues[*]}")
}

# 诊断PHP
diagnose_php() {
    log_info "开始诊断 PHP..."
    
    local issues=()
    local fixes=()
    
    # 检查PHP-FPM是否运行
    if ! systemctl is-active --quiet php8.3-fpm 2>/dev/null; then
        issues+=("PHP-FPM服务未运行")
        fixes+=("sudo systemctl start php8.3-fpm")
    fi
    
    # 检查PHP版本
    local php_version
    php_version="$(php -v 2>/dev/null | head -1 | cut -d' ' -f2)"
    if [[ -z "$php_version" ]]; then
        issues+=("PHP未安装或无法执行")
        fixes+=("安装PHP: sudo apt install php8.3-fpm")
    fi
    
    # 检查PHP配置
    local php_ini="/etc/php/8.3/fpm/php.ini"
    if [[ -f "$php_ini" ]]; then
        if grep -q "display_errors.*On" "$php_ini"; then
            issues+=("PHP错误显示已启用，生产环境建议关闭")
            fixes+=("修改php.ini: display_errors = Off")
        fi
        
        if grep -q "expose_php.*On" "$php_ini"; then
            issues+=("PHP版本信息暴露已启用，建议关闭")
            fixes+=("修改php.ini: expose_php = Off")
        fi
    fi
    
    # 检查PHP日志
    local php_log="/var/log/php8.3-fpm.log"
    if [[ -f "$php_log" ]]; then
        local error_count
        error_count="$(grep -c "ERROR\|FATAL" "$php_log" 2>/dev/null || echo "0")"
        if [[ "$error_count" -gt 0 ]]; then
            issues+=("PHP-FPM日志中发现 $error_count 个错误")
            fixes+=("检查PHP-FPM日志: tail -f $php_log")
        fi
    fi
    
    # 检查PHP扩展
    local required_extensions=("mysqli" "pdo_mysql" "curl" "json" "mbstring")
    for ext in "${required_extensions[@]}"; do
        if ! php -m | grep -q "^$ext$"; then
            issues+=("缺少PHP扩展: $ext")
            fixes+=("安装PHP扩展: sudo apt install php8.3-$ext")
        fi
    done
    
    # 输出诊断结果
    if [[ ${#issues[@]} -eq 0 ]]; then
        log_success "PHP诊断完成 - 未发现问题"
    else
        log_warning "PHP诊断完成 - 发现 ${#issues[@]} 个问题:"
        for i in "${!issues[@]}"; do
            log_error "  ${issues[$i]}"
            log_info "  建议修复: ${fixes[$i]}"
        done
    fi
    
    # 存储诊断结果
    DIAGNOSE_RESULTS+=("php:${#issues[@]}:${issues[*]}")
}

# 诊断系统
diagnose_system() {
    log_info "开始诊断系统..."
    
    local issues=()
    local fixes=()
    
    # 检查磁盘空间
    local disk_usage
    disk_usage="$(df / | awk 'NR==2{print $5}' | sed 's/%//')"
    if [[ "$disk_usage" -gt 90 ]]; then
        issues+=("根分区磁盘使用率过高: ${disk_usage}%")
        fixes+=("清理临时文件或增加磁盘空间")
    fi
    
    # 检查内存使用
    local mem_usage
    mem_usage="$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')"
    if [[ "$mem_usage" -gt 90 ]]; then
        issues+=("内存使用率过高: ${mem_usage}%")
        fixes+=("检查内存使用情况: htop 或 free -h")
    fi
    
    # 检查负载
    local load_avg
    load_avg="$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')"
    local cpu_cores
    cpu_cores="$(nproc)"
    local load_threshold
    load_threshold="$(echo "$cpu_cores * 2" | bc)"
    if (( $(echo "$load_avg > $load_threshold" | bc -l) )); then
        issues+=("系统负载过高: $load_avg (CPU核心数: $cpu_cores)")
        fixes+=("检查系统负载: top 或 htop")
    fi
    
    # 检查系统更新
    if command -v apt >/dev/null 2>&1; then
        local update_count
        update_count="$(apt list --upgradable 2>/dev/null | grep -c "upgradable")"
        if [[ "$update_count" -gt 0 ]]; then
            # 检查是否只是内核更新
            local kernel_updates
            kernel_updates="$(apt list --upgradable 2>/dev/null | grep -c "linux-")"
            local total_updates
            total_updates="$(apt list --upgradable 2>/dev/null | wc -l)"
            
            if [[ "$kernel_updates" -eq "$total_updates" ]]; then
                issues+=("发现 $update_count 个内核更新（安全更新）")
                fixes+=("建议更新内核: sudo apt update && sudo apt upgrade")
            else
                issues+=("发现 $update_count 个系统更新（主要是内核和安全补丁）")
                fixes+=("安全更新: sudo apt update && sudo apt upgrade（核心LEMP软件已锁定）")
            fi
        fi
    fi
    
    # 检查系统时间
    local time_sync
    time_sync="$(timedatectl status | grep "NTP service" | awk '{print $3}')"
    if [[ "$time_sync" != "active" ]]; then
        issues+=("NTP时间同步服务未激活")
        fixes+=("启用NTP同步: sudo timedatectl set-ntp true")
    fi
    
    # 输出诊断结果
    if [[ ${#issues[@]} -eq 0 ]]; then
        log_success "系统诊断完成 - 未发现问题"
    else
        log_warning "系统诊断完成 - 发现 ${#issues[@]} 个问题:"
        for i in "${!issues[@]}"; do
            log_error "  ${issues[$i]}"
            log_info "  建议修复: ${fixes[$i]}"
        done
    fi
    
    # 存储诊断结果
    DIAGNOSE_RESULTS+=("system:${#issues[@]}:${issues[*]}")
}

# 诊断网络
diagnose_network() {
    log_info "开始诊断网络..."
    
    local issues=()
    local fixes=()
    
    # 检查网络连接
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        issues+=("无法连接到外网 (8.8.8.8)")
        fixes+=("检查网络连接和DNS配置")
    fi
    
    # 检查DNS解析
    if ! nslookup google.com >/dev/null 2>&1; then
        issues+=("DNS解析失败")
        fixes+=("检查DNS配置: /etc/resolv.conf")
    fi
    
    # 检查防火墙状态
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status
        ufw_status="$(ufw status | head -1 | awk '{print $2}')"
        if [[ "$ufw_status" == "inactive" ]]; then
            issues+=("UFW防火墙未启用")
            fixes+=("启用防火墙: sudo ufw enable")
        fi
    fi
    
    # 检查SSH服务
    if systemctl is-active --quiet ssh; then
        local ssh_config="/etc/ssh/sshd_config"
        if [[ -f "$ssh_config" ]]; then
            if grep -q "PermitRootLogin yes" "$ssh_config"; then
                issues+=("SSH允许Root登录，存在安全风险")
                fixes+=("修改SSH配置: PermitRootLogin no")
            fi
        fi
    fi
    
    # 输出诊断结果
    if [[ ${#issues[@]} -eq 0 ]]; then
        log_success "网络诊断完成 - 未发现问题"
    else
        log_warning "网络诊断完成 - 发现 ${#issues[@]} 个问题:"
        for i in "${!issues[@]}"; do
            log_error "  ${issues[$i]}"
            log_info "  建议修复: ${fixes[$i]}"
        done
    fi
    
    # 存储诊断结果
    DIAGNOSE_RESULTS+=("network:${#issues[@]}:${issues[*]}")
}

# 显示诊断摘要
show_diagnose_summary() {
    log_info "诊断摘要:"
    echo "=========================================="
    
    local total_issues=0
    for result in "${DIAGNOSE_RESULTS[@]}"; do
        local type
        type="$(echo "$result" | cut -d':' -f1)"
        local count
        count="$(echo "$result" | cut -d':' -f2)"
        
        if [[ "$count" -eq 0 ]]; then
            log_success "$type: 无问题"
        else
            log_warning "$type: $count 个问题"
            total_issues=$((total_issues + count))
        fi
    done
    
    echo "=========================================="
    if [[ "$total_issues" -eq 0 ]]; then
        log_success "总体诊断结果: 系统运行正常"
    else
        log_warning "总体诊断结果: 发现 $total_issues 个问题需要关注"
    fi
}

# 诊断主函数
diagnose_handler() {
    case "$1" in
        "nginx")
            diagnose_nginx
            ;;
        "mysql")
            diagnose_mysql
            ;;
        "php")
            diagnose_php
            ;;
        "system")
            diagnose_system
            ;;
        "network")
            diagnose_network
            ;;
        "all")
            log_info "开始完整系统诊断..."
            diagnose_nginx
            diagnose_mysql
            diagnose_php
            diagnose_system
            diagnose_network
            show_diagnose_summary
            ;;
        *)
            log_error "未知的诊断类型: $1"
            log_info "支持的类型: nginx, mysql, php, system, network, all"
            return 1
            ;;
    esac
}

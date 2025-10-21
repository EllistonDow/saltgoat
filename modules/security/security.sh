#!/bin/bash
# 安全扫描模块 - 完全 Salt 原生功能
# services/security.sh

# 安全扫描配置
SECURITY_SCAN_DIRS=(
    "/etc"
    "/var/www"
    "/home"
    "/root"
)

# 检查开放端口
security_port_scan() {
    log_highlight "扫描开放端口..."
    
    echo "开放端口列表:"
    echo "=========================================="
    
    # 使用 Salt 命令模块扫描端口
    local open_ports=$(salt-call --local cmd.run "ss -tlnp" 2>/dev/null | grep LISTEN)
    
    if [[ -n "$open_ports" ]]; then
        echo "$open_ports"
    else
        log_info "未发现开放端口"
    fi
    
    echo ""
    echo "端口安全分析:"
    echo "----------------------------------------"
    
    # 检查常见危险端口
    local dangerous_ports=("21" "23" "135" "139" "445" "1433" "3389")
    local found_dangerous=""
    
    for port in "${dangerous_ports[@]}"; do
        if echo "$open_ports" | grep -q ":$port "; then
            found_dangerous="$found_dangerous $port"
        fi
    done
    
    if [[ -n "$found_dangerous" ]]; then
        log_warning "发现潜在危险端口:$found_dangerous"
        log_info "建议检查这些端口是否必要"
    else
        log_success "未发现常见危险端口"
    fi
}

# 检查服务安全状态
security_service_check() {
    log_highlight "检查服务安全状态..."
    
    echo "服务状态检查:"
    echo "=========================================="
    
    # 检查关键服务状态
    local services=("nginx" "mysql" "php8.3-fpm" "valkey" "rabbitmq" "opensearch")
    
    for service in "${services[@]}"; do
        local status=$(salt-call --local service.status "$service" 2>/dev/null | grep -o "True\|False")
        if [[ "$status" == "True" ]]; then
            echo "✅ $service: 运行中"
        else
            echo "❌ $service: 未运行"
        fi
    done
    
    echo ""
    echo "服务配置检查:"
    echo "----------------------------------------"
    
    # 检查 Nginx 安全配置
    if salt-call --local file.file_exists "/etc/nginx/nginx.conf" --out=txt 2>/dev/null | grep -q "True"; then
        local server_tokens=$(salt-call --local cmd.run "grep -c 'server_tokens off' /etc/nginx/nginx.conf" 2>/dev/null)
        if [[ "$server_tokens" == "0" ]]; then
            log_warning "Nginx: server_tokens 未关闭，可能泄露版本信息"
        else
            log_success "Nginx: server_tokens 已关闭"
        fi
    fi
    
    # 检查 MySQL 安全配置
    if salt-call --local file.file_exists "/etc/mysql/mysql.conf.d/mysqld.cnf" --out=txt 2>/dev/null | grep -q "True"; then
        local bind_address=$(salt-call --local cmd.run "grep -c 'bind-address.*127.0.0.1' /etc/mysql/mysql.conf.d/mysqld.cnf" 2>/dev/null)
        if [[ "$bind_address" == "0" ]]; then
            log_warning "MySQL: 可能允许远程连接"
        else
            log_success "MySQL: 绑定到本地地址"
        fi
    fi
}

# 检查文件权限
security_file_permissions() {
    log_highlight "检查文件权限安全..."
    
    echo "关键文件权限检查:"
    echo "=========================================="
    
    # 检查关键配置文件权限
    local critical_files=(
        "/etc/passwd"
        "/etc/shadow"
        "/etc/group"
        "/etc/sudoers"
        "/etc/ssh/sshd_config"
        "/etc/mysql/mysql.conf.d/mysqld.cnf"
        "/etc/nginx/nginx.conf"
    )
    
    for file in "${critical_files[@]}"; do
        if salt-call --local file.file_exists "$file" --out=txt 2>/dev/null | grep -q "True"; then
            local perms=$(salt-call --local file.stat "$file" --out=txt 2>/dev/null | grep "mode:" | awk '{print $2}')
            local owner=$(salt-call --local file.stat "$file" --out=txt 2>/dev/null | grep "user:" | awk '{print $2}')
            
            echo "$file: $perms (owner: $owner)"
            
            # 检查权限是否过于宽松
            if [[ "$file" == "/etc/shadow" ]] && [[ "$perms" != "640" ]]; then
                log_warning "$file: 权限过于宽松，建议设置为 640"
            elif [[ "$file" == "/etc/passwd" ]] && [[ "$perms" != "644" ]]; then
                log_warning "$file: 权限异常"
            fi
        fi
    done
    
    echo ""
    echo "Web 目录权限检查:"
    echo "----------------------------------------"
    
    # 检查 Web 目录权限
    local web_dirs=("/var/www" "/var/www/html")
    
    for dir in "${web_dirs[@]}"; do
        if salt-call --local file.directory_exists "$dir" --out=txt 2>/dev/null | grep -q "True"; then
            local perms=$(salt-call --local file.stat "$dir" --out=txt 2>/dev/null | grep "mode:" | awk '{print $2}')
            local owner=$(salt-call --local file.stat "$dir" --out=txt 2>/dev/null | grep "user:" | awk '{print $2}')
            
            echo "$dir: $perms (owner: $owner)"
            
            if [[ "$perms" == "777" ]] || [[ "$perms" == "755" ]]; then
                log_warning "$dir: 权限可能过于宽松"
            fi
        fi
    done
}

# 检查防火墙状态
security_firewall_check() {
    log_highlight "检查防火墙状态..."
    
    echo "防火墙状态:"
    echo "=========================================="
    
    # 检查 UFW 状态
    local ufw_status=$(salt-call --local cmd.run "ufw status" 2>/dev/null)
    
    if echo "$ufw_status" | grep -q "Status: active"; then
        log_success "UFW 防火墙: 已启用"
        echo "$ufw_status"
    else
        log_warning "UFW 防火墙: 未启用"
        log_info "建议启用防火墙以保护系统安全"
    fi
    
    echo ""
    echo "iptables 规则:"
    echo "----------------------------------------"
    
    # 检查 iptables 规则
    local iptables_rules=$(salt-call --local cmd.run "iptables -L -n" 2>/dev/null)
    echo "$iptables_rules"
}

# 检查系统更新
security_updates_check() {
    log_highlight "检查系统更新..."
    
    echo "系统更新状态:"
    echo "=========================================="
    
    # 检查可用的安全更新
    local updates_count=$(apt list --upgradable 2>/dev/null | grep -c 'upgradable' 2>/dev/null)
    local updates=${updates_count:-0}
    
    if [[ $updates -gt 0 ]]; then
        log_warning "发现 $updates 个可用更新"
        log_info "建议运行: sudo apt update && sudo apt upgrade"
        
        echo ""
        echo "安全相关更新:"
        echo "----------------------------------------"
        apt list --upgradable 2>/dev/null | grep -E '(security|kernel)' || true
    else
        log_success "系统已是最新版本"
    fi
    
    echo ""
    echo "自动更新状态:"
    echo "----------------------------------------"
    
    # 检查 unattended-upgrades 状态
    local auto_update_status=$(salt-call --local service.status "unattended-upgrades" --out=txt 2>/dev/null | tail -n 1)
    if [[ "$auto_update_status" == "True" ]]; then
        log_success "自动安全更新: 已启用"
    else
        log_warning "自动安全更新: 未启用"
        log_info "建议启用自动安全更新"
    fi
}

# 检查用户安全
security_user_check() {
    log_highlight "检查用户安全..."
    
    echo "用户安全状态:"
    echo "=========================================="
    
    # 检查 root 用户登录
    local root_login=$(salt-call --local cmd.run "grep '^PermitRootLogin' /etc/ssh/sshd_config" 2>/dev/null)
    if echo "$root_login" | grep -q "no"; then
        log_success "SSH: Root 登录已禁用"
    else
        log_warning "SSH: Root 登录可能已启用"
        log_info "建议禁用 Root 用户 SSH 登录"
    fi
    
    # 检查密码策略
    local passwd_policy=$(salt-call --local cmd.run "grep -E '^PASS_' /etc/login.defs" 2>/dev/null)
    echo "密码策略:"
    echo "$passwd_policy"
    
    echo ""
    echo "最近登录用户:"
    echo "----------------------------------------"
    salt-call --local cmd.run "last -n 10" 2>/dev/null
    
    echo ""
    echo "当前登录用户:"
    echo "----------------------------------------"
    salt-call --local cmd.run "who" 2>/dev/null
}

# 检查日志安全
security_log_check() {
    log_highlight "检查日志安全..."
    
    echo "日志安全状态:"
    echo "=========================================="
    
    # 检查关键日志文件
    local log_files=(
        "/var/log/auth.log"
        "/var/log/syslog"
        "/var/log/nginx/access.log"
        "/var/log/nginx/error.log"
        "/var/log/mysql/error.log"
    )
    
    for log_file in "${log_files[@]}"; do
        if salt-call --local file.file_exists "$log_file" --out=txt 2>/dev/null | grep -q "True"; then
            local size=$(salt-call --local cmd.run "du -h $log_file" 2>/dev/null | awk '{print $1}')
            echo "✅ $log_file: $size"
        else
            echo "❌ $log_file: 不存在"
        fi
    done
    
    echo ""
    echo "最近认证失败:"
    echo "----------------------------------------"
    salt-call --local cmd.run "grep 'Failed password' /var/log/auth.log | tail -5" 2>/dev/null
    
    echo ""
    echo "最近 SSH 登录:"
    echo "----------------------------------------"
    salt-call --local cmd.run "grep 'sshd' /var/log/auth.log | tail -5" 2>/dev/null
}

# 完整安全扫描
security_full_scan() {
    log_highlight "执行完整安全扫描..."
    
    security_port_scan
    echo ""
    
    security_service_check
    echo ""
    
    security_file_permissions
    echo ""
    
    security_firewall_check
    echo ""
    
    security_updates_check
    echo ""
    
    security_user_check
    echo ""
    
    security_log_check
    
    echo ""
    log_success "安全扫描完成"
    log_info "请仔细查看上述报告，并根据建议进行安全加固"
}

# 生成安全报告
security_report() {
    local report_file="$HOME/saltgoat_security_report_$(date +%Y%m%d_%H%M%S).txt"
    
    log_highlight "生成安全报告: $report_file"
    
    {
        echo "SaltGoat 安全扫描报告"
        echo "======================"
        echo "生成时间: $(date)"
        echo "系统信息: $(uname -a)"
        echo ""
        
        security_port_scan
        echo ""
        
        security_service_check
        echo ""
        
        security_file_permissions
        echo ""
        
        security_firewall_check
        echo ""
        
        security_updates_check
        echo ""
        
        security_user_check
        echo ""
        
        security_log_check
        
    } > "$report_file"
    
    log_success "安全报告已生成: $report_file"
}

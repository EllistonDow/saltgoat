#!/bin/bash
# SSL 证书管理模块 - 完全 Salt 原生功能
# services/ssl.sh

# SSL 证书配置
SSL_CERT_DIR="/etc/ssl/certs"
SSL_KEY_DIR="/etc/ssl/private"
SSL_CSR_DIR="/etc/ssl/csr"
SSL_BACKUP_DIR="/var/backups/ssl"

# 确保 SSL 目录存在
ensure_ssl_dirs() {
    salt-call --local file.mkdir "$SSL_CERT_DIR" >/dev/null 2>&1
    salt-call --local file.mkdir "$SSL_KEY_DIR" >/dev/null 2>&1
    salt-call --local file.mkdir "$SSL_CSR_DIR" >/dev/null 2>&1
    salt-call --local file.mkdir "$SSL_BACKUP_DIR" >/dev/null 2>&1
}

# 生成自签名证书
ssl_generate_self_signed() {
    local domain="$1"
    local days="${2:-365}"
    
    if [[ -z "$domain" ]]; then
        log_error "用法: saltgoat ssl generate-self-signed <domain> [days]"
        log_info "示例: saltgoat ssl generate-self-signed example.com 365"
        exit 1
    fi
    
    log_highlight "生成自签名证书: $domain (有效期: $days 天)"
    ensure_ssl_dirs
    
    local cert_file="$SSL_CERT_DIR/${domain}.crt"
    local key_file="$SSL_KEY_DIR/${domain}.key"
    
    # 检查证书是否已存在
    if salt-call --local file.file_exists "$cert_file" --out=txt 2>/dev/null | grep -q "True"; then
        log_warning "证书文件已存在: $cert_file"
        read -p "是否覆盖现有证书？(y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            log_info "操作已取消"
            exit 0
        fi
    fi
    
    # 生成私钥和证书
    log_info "生成私钥和证书..."
    salt-call --local cmd.run "sudo openssl req -newkey rsa:2048 -nodes -keyout $key_file -x509 -days $days -out $cert_file -subj '/C=US/ST=State/L=City/O=Organization/CN=$domain'" >/dev/null 2>&1
    salt-call --local cmd.run "sudo chmod 600 $key_file" >/dev/null 2>&1
    salt-call --local cmd.run "sudo chmod 644 $cert_file" >/dev/null 2>&1
    
    log_success "自签名证书生成完成"
    log_info "证书文件: $cert_file"
    log_info "私钥文件: $key_file"
}

# 生成证书签名请求 (CSR)
ssl_generate_csr() {
    local domain="$1"
    local country="${2:-US}"
    local state="${3:-State}"
    local city="${4:-City}"
    local organization="${5:-Organization}"
    
    if [[ -z "$domain" ]]; then
        log_error "用法: saltgoat ssl generate-csr <domain> [country] [state] [city] [organization]"
        log_info "示例: saltgoat ssl generate-csr example.com US California SanFrancisco MyCompany"
        exit 1
    fi
    
    log_highlight "生成证书签名请求: $domain"
    ensure_ssl_dirs
    
    local key_file="$SSL_KEY_DIR/${domain}.key"
    local csr_file="$SSL_CSR_DIR/${domain}.csr"
    
    # 生成私钥
    log_info "生成私钥..."
    salt-call --local cmd.run "openssl genrsa -out $key_file 2048" >/dev/null 2>&1
    salt-call --local cmd.run "chmod 600 $key_file" >/dev/null 2>&1
    
    # 生成 CSR
    log_info "生成证书签名请求..."
    salt-call --local cmd.run "openssl req -new -key $key_file -out $csr_file -subj '/C=$country/ST=$state/L=$city/O=$organization/CN=$domain'" >/dev/null 2>&1
    salt-call --local cmd.run "chmod 644 $csr_file" >/dev/null 2>&1
    
    log_success "证书签名请求生成完成"
    log_info "私钥文件: $key_file"
    log_info "CSR 文件: $csr_file"
    
    echo ""
    echo "CSR 内容:"
    echo "----------------------------------------"
    salt-call --local cmd.run "cat $csr_file" 2>/dev/null
}

# 查看证书信息
ssl_view_cert() {
    local cert_file="$1"
    
    if [[ -z "$cert_file" ]]; then
        log_error "用法: saltgoat ssl view <certificate_file>"
        log_info "示例: saltgoat ssl view /etc/ssl/certs/example.com.crt"
        exit 1
    fi
    
    # 检查证书文件是否存在
    if ! salt-call --local file.file_exists "$cert_file" --out=txt 2>/dev/null | grep -q "True"; then
        log_error "证书文件不存在: $cert_file"
        exit 1
    fi
    
    log_highlight "查看证书信息: $cert_file"
    
    echo "证书详细信息:"
    echo "=========================================="
    salt-call --local cmd.run "openssl x509 -in $cert_file -text -noout" 2>/dev/null
    
    echo ""
    echo "证书摘要:"
    echo "----------------------------------------"
    salt-call --local cmd.run "openssl x509 -in $cert_file -subject -issuer -dates -noout" 2>/dev/null
    
    echo ""
    echo "证书指纹:"
    echo "----------------------------------------"
    salt-call --local cmd.run "openssl x509 -in $cert_file -fingerprint -noout" 2>/dev/null
}

# 验证证书
ssl_verify_cert() {
    local cert_file="$1"
    local key_file="$2"
    
    if [[ -z "$cert_file" ]]; then
        log_error "用法: saltgoat ssl verify <certificate_file> [private_key_file]"
        log_info "示例: saltgoat ssl verify /etc/ssl/certs/example.com.crt /etc/ssl/private/example.com.key"
        exit 1
    fi
    
    log_highlight "验证证书: $cert_file"
    
    # 检查证书文件是否存在
    if ! salt-call --local file.file_exists "$cert_file" --out=txt 2>/dev/null | grep -q "True"; then
        log_error "证书文件不存在: $cert_file"
        exit 1
    fi
    
    # 验证证书格式
    log_info "验证证书格式..."
    if salt-call --local cmd.run "openssl x509 -in $cert_file -text -noout" >/dev/null 2>&1; then
        log_success "证书格式正确"
    else
        log_error "证书格式错误"
        exit 1
    fi
    
    # 验证证书有效期
    log_info "检查证书有效期..."
    local expiry_date=$(salt-call --local cmd.run "openssl x509 -in $cert_file -enddate -noout | cut -d= -f2" 2>/dev/null)
    local expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null)
    local current_timestamp=$(date +%s)
    local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
    
    if [[ $days_until_expiry -gt 0 ]]; then
        log_success "证书有效，还有 $days_until_expiry 天过期"
    else
        log_error "证书已过期"
    fi
    
    # 如果提供了私钥文件，验证证书和私钥匹配
    if [[ -n "$key_file" ]]; then
        if salt-call --local file.file_exists "$key_file" --out=txt 2>/dev/null | grep -q "True"; then
            log_info "验证证书和私钥匹配..."
            local cert_md5=$(salt-call --local cmd.run "openssl x509 -noout -modulus -in $cert_file | openssl md5" 2>/dev/null)
            local key_md5=$(salt-call --local cmd.run "openssl rsa -noout -modulus -in $key_file | openssl md5" 2>/dev/null)
            
            if [[ "$cert_md5" == "$key_md5" ]]; then
                log_success "证书和私钥匹配"
            else
                log_error "证书和私钥不匹配"
            fi
        else
            log_warning "私钥文件不存在: $key_file"
        fi
    fi
}

# 列出所有证书
ssl_list_certs() {
    log_highlight "列出所有 SSL 证书..."
    
    echo "系统证书目录:"
    echo "=========================================="
    
    # 列出系统证书目录
    if salt-call --local file.directory_exists "$SSL_CERT_DIR" --out=txt 2>/dev/null | grep -q "True"; then
        echo "证书文件 ($SSL_CERT_DIR):"
        local cert_files=$(salt-call --local file.find "$SSL_CERT_DIR" name="*.crt" --out=txt 2>/dev/null | tail -n +2 | awk '{print $2}')
        if [[ -n "$cert_files" ]]; then
            for file in $cert_files; do
                if [[ -n "$file" ]]; then
                    salt-call --local cmd.run "ls -la $file" 2>/dev/null
                fi
            done
        else
            echo "无证书文件"
        fi
    fi
    
    echo ""
    echo "私钥文件 ($SSL_KEY_DIR):"
    local key_files=$(salt-call --local file.find "$SSL_KEY_DIR" name="*.key" --out=txt 2>/dev/null | tail -n +2 | awk '{print $2}')
    if [[ -n "$key_files" ]]; then
        for file in $key_files; do
            if [[ -n "$file" ]]; then
                salt-call --local cmd.run "ls -la $file" 2>/dev/null
            fi
        done
    else
        echo "无私钥文件"
    fi
    
    echo ""
    echo "CSR 文件 ($SSL_CSR_DIR):"
    local csr_files=$(salt-call --local file.find "$SSL_CSR_DIR" name="*.csr" --out=txt 2>/dev/null | tail -n +2 | awk '{print $2}')
    if [[ -n "$csr_files" ]]; then
        for file in $csr_files; do
            if [[ -n "$file" ]]; then
                salt-call --local cmd.run "ls -la $file" 2>/dev/null
            fi
        done
    else
        echo "无 CSR 文件"
    fi
    
    echo ""
    echo "证书详细信息:"
    echo "----------------------------------------"
    
    # 显示每个证书的详细信息
    for cert_file in "$SSL_CERT_DIR"/*.crt; do
        if salt-call --local file.file_exists "$cert_file" --out=txt 2>/dev/null | grep -q "True"; then
            local domain=$(basename "$cert_file" .crt)
            local expiry_date=$(salt-call --local cmd.run "openssl x509 -in $cert_file -enddate -noout | cut -d= -f2" 2>/dev/null)
            local expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null)
            local current_timestamp=$(date +%s)
            local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
            
            echo "域名: $domain"
            echo "过期时间: $expiry_date"
            echo "剩余天数: $days_until_expiry"
            echo "文件路径: $cert_file"
            echo "----------------------------------------"
        fi
    done
}

# 续期证书
ssl_renew_cert() {
    local cert_file="$1"
    local days="${2:-365}"
    
    if [[ -z "$cert_file" ]]; then
        log_error "用法: saltgoat ssl renew <certificate_file> [days]"
        log_info "示例: saltgoat ssl renew /etc/ssl/certs/example.com.crt 365"
        exit 1
    fi
    
    # 检查证书文件是否存在
    if ! salt-call --local file.file_exists "$cert_file" --out=txt 2>/dev/null | grep -q "True"; then
        log_error "证书文件不存在: $cert_file"
        exit 1
    fi
    
    log_highlight "续期证书: $cert_file (有效期: $days 天)"
    
    local domain=$(basename "$cert_file" .crt)
    local key_file="$SSL_KEY_DIR/${domain}.key"
    local backup_cert="$SSL_BACKUP_DIR/${domain}_$(date +%Y%m%d_%H%M%S).crt"
    
    # 检查私钥文件是否存在
    if ! salt-call --local file.file_exists "$key_file" --out=txt 2>/dev/null | grep -q "True"; then
        log_error "私钥文件不存在: $key_file"
        log_info "无法续期证书，需要私钥文件"
        exit 1
    fi
    
    # 备份原证书
    log_info "备份原证书..."
    ensure_ssl_dirs
    salt-call --local cmd.run "cp $cert_file $backup_cert" >/dev/null 2>&1
    
    # 生成新证书
    log_info "生成新证书..."
    salt-call --local cmd.run "openssl req -new -x509 -key $key_file -out $cert_file -days $days -subj '/C=US/ST=State/L=City/O=Organization/CN=$domain'" >/dev/null 2>&1
    
    log_success "证书续期完成"
    log_info "原证书备份: $backup_cert"
    log_info "新证书文件: $cert_file"
}

# 备份证书
ssl_backup_certs() {
    local backup_name="$1"
    
    if [[ -z "$backup_name" ]]; then
        backup_name="ssl_backup_$(date +%Y%m%d_%H%M%S)"
    fi
    
    log_highlight "备份 SSL 证书: $backup_name"
    ensure_ssl_dirs
    
    local backup_dir="$SSL_BACKUP_DIR/$backup_name"
    salt-call --local file.mkdir "$backup_dir" >/dev/null 2>&1
    
    # 备份证书文件
    if salt-call --local file.directory_exists "$SSL_CERT_DIR" --out=txt 2>/dev/null | grep -q "True"; then
        log_info "备份证书文件..."
        salt-call --local cmd.run "cp -r $SSL_CERT_DIR $backup_dir/" >/dev/null 2>&1
    fi
    
    # 备份私钥文件
    if salt-call --local file.directory_exists "$SSL_KEY_DIR" --out=txt 2>/dev/null | grep -q "True"; then
        log_info "备份私钥文件..."
        salt-call --local cmd.run "cp -r $SSL_KEY_DIR $backup_dir/" >/dev/null 2>&1
    fi
    
    # 备份 CSR 文件
    if salt-call --local file.directory_exists "$SSL_CSR_DIR" --out=txt 2>/dev/null | grep -q "True"; then
        log_info "备份 CSR 文件..."
        salt-call --local cmd.run "cp -r $SSL_CSR_DIR $backup_dir/" >/dev/null 2>&1
    fi
    
    # 创建备份信息文件
    local backup_info="SSL 证书备份
==================
备份名称: $backup_name
备份时间: $(date)
备份目录: $backup_dir
备份内容:
- 证书文件
- 私钥文件
- CSR 文件"
    
    salt-call --local file.write "$backup_dir/backup_info.txt" contents="$backup_info" >/dev/null 2>&1
    
    # 创建压缩包
    log_info "创建备份压缩包..."
    salt-call --local cmd.run "tar -czf $SSL_BACKUP_DIR/${backup_name}.tar.gz -C $SSL_BACKUP_DIR $backup_name" >/dev/null 2>&1
    salt-call --local cmd.run "rm -rf $backup_dir" >/dev/null 2>&1
    
    log_success "SSL 证书备份完成: ${backup_name}.tar.gz"
    log_info "备份位置: $SSL_BACKUP_DIR/${backup_name}.tar.gz"
}

# 清理过期证书
ssl_cleanup_expired() {
    local days="${1:-30}"
    
    log_highlight "清理过期证书（超过 $days 天）..."
    
    local cleaned_count=0
    
    # 清理过期的证书文件
    for cert_file in "$SSL_CERT_DIR"/*.crt; do
        if salt-call --local file.file_exists "$cert_file" --out=txt 2>/dev/null | grep -q "True"; then
            local expiry_date=$(salt-call --local cmd.run "openssl x509 -in $cert_file -enddate -noout | cut -d= -f2" 2>/dev/null)
            local expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null)
            local current_timestamp=$(date +%s)
            local days_since_expiry=$(( (current_timestamp - expiry_timestamp) / 86400 ))
            
            if [[ $days_since_expiry -gt $days ]]; then
                local domain=$(basename "$cert_file" .crt)
                log_info "删除过期证书: $domain (过期 $days_since_expiry 天)"
                salt-call --local file.remove "$cert_file" >/dev/null 2>&1
                
                # 同时删除对应的私钥文件
                local key_file="$SSL_KEY_DIR/${domain}.key"
                if salt-call --local file.file_exists "$key_file" --out=txt 2>/dev/null | grep -q "True"; then
                    salt-call --local file.remove "$key_file" >/dev/null 2>&1
                fi
                
                ((cleaned_count++))
            fi
        fi
    done
    
    log_success "清理完成，删除了 $cleaned_count 个过期证书"
}

# SSL 状态检查
ssl_status() {
    log_highlight "SSL 证书状态检查..."
    
    echo "SSL 目录状态:"
    echo "=========================================="
    
    # 检查目录权限
    local cert_dir_perms=$(salt-call --local file.stat "$SSL_CERT_DIR" --out=txt 2>/dev/null | grep "mode:" | awk '{print $2}')
    local key_dir_perms=$(salt-call --local file.stat "$SSL_KEY_DIR" --out=txt 2>/dev/null | grep "mode:" | awk '{print $2}')
    
    echo "证书目录权限: $cert_dir_perms"
    echo "私钥目录权限: $key_dir_perms"
    
    echo ""
    echo "证书统计:"
    echo "----------------------------------------"
    
    # 使用 Salt 文件模块统计文件数量
    local cert_files=$(salt-call --local file.find "$SSL_CERT_DIR" name="*.crt" --out=txt 2>/dev/null | tail -n +2 | awk '{print $2}')
    local key_files=$(salt-call --local file.find "$SSL_KEY_DIR" name="*.key" --out=txt 2>/dev/null | tail -n +2 | awk '{print $2}')
    local csr_files=$(salt-call --local file.find "$SSL_CSR_DIR" name="*.csr" --out=txt 2>/dev/null | tail -n +2 | awk '{print $2}')
    
    local cert_count=0
    local key_count=0
    local csr_count=0
    
    for file in $cert_files; do
        if [[ -n "$file" ]]; then
            ((cert_count++))
        fi
    done
    
    for file in $key_files; do
        if [[ -n "$file" ]]; then
            ((key_count++))
        fi
    done
    
    for file in $csr_files; do
        if [[ -n "$file" ]]; then
            ((csr_count++))
        fi
    done
    
    echo "证书文件数量: $cert_count"
    echo "私钥文件数量: $key_count"
    echo "CSR 文件数量: $csr_count"
    
    echo ""
    echo "即将过期的证书:"
    echo "----------------------------------------"
    
    local expiring_count=0
    for cert_file in "$SSL_CERT_DIR"/*.crt; do
        if salt-call --local file.file_exists "$cert_file" --out=txt 2>/dev/null | grep -q "True"; then
            local expiry_date=$(salt-call --local cmd.run "openssl x509 -in $cert_file -enddate -noout | cut -d= -f2" 2>/dev/null)
            local expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null)
            local current_timestamp=$(date +%s)
            local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
            
            if [[ $days_until_expiry -lt 30 && $days_until_expiry -gt 0 ]]; then
                local domain=$(basename "$cert_file" .crt)
                echo "⚠️  $domain: $days_until_expiry 天后过期"
                ((expiring_count++))
            elif [[ $days_until_expiry -le 0 ]]; then
                local domain=$(basename "$cert_file" .crt)
                echo "❌ $domain: 已过期 $(( -days_until_expiry )) 天"
                ((expiring_count++))
            fi
        fi
    done
    
    if [[ $expiring_count -eq 0 ]]; then
        log_success "所有证书都在有效期内"
    else
        log_warning "发现 $expiring_count 个需要关注的证书"
    fi
}
#!/bin/bash

# 检查 Magento 2 兼容性
check_magento2_compatibility() {
    local site_path="${1:-$(pwd)}"
    
    log_highlight "检查 Magento 2 兼容性: $site_path"
    
    echo "系统环境检查:"
    echo "=========================================="
    
    # 检查 PHP 版本
    local php_version
    php_version=$(php -v | head -1 | awk '{print $2}' | cut -d. -f1,2)
    echo "PHP 版本: $php_version"
    if [[ "$php_version" == "8.3" || "$php_version" == "8.2" || "$php_version" == "8.1" ]]; then
        log_success "PHP 版本兼容 Magento 2"
    else
        log_warning "PHP 版本可能不兼容 Magento 2，建议使用 PHP 8.1+"
    fi
    
    # 检查 PHP 扩展
    echo ""
    echo "PHP 扩展检查:"
    echo "----------------------------------------"
    local required_extensions=("curl" "gd" "intl" "mbstring" "openssl" "pdo_mysql" "soap" "xml" "zip" "bcmath" "json")
    local missing_extensions=()
    
    for ext in "${required_extensions[@]}"; do
        if php -m | grep -q "^$ext$"; then
            echo "[SUCCESS] $ext"
        else
            echo "[ERROR] $ext (缺失)"
            missing_extensions+=("$ext")
        fi
    done
    
    if [[ ${#missing_extensions[@]} -eq 0 ]]; then
        log_success "所有必需的 PHP 扩展都已安装"
    else
        log_warning "缺失扩展: ${missing_extensions[*]}"
    fi
    
    # 检查 Nginx 配置
    echo ""
    echo "Nginx 配置检查:"
    echo "----------------------------------------"
    
    # 动态检测站点名称
    local site_name
    site_name="$(basename "$site_path")"
    local nginx_config="/etc/nginx/sites-enabled/$site_name"
    
    if [[ -f "$nginx_config" ]]; then
        echo "[SUCCESS] Nginx 站点配置存在"
        
        # 检查是否使用 Magento 2 简化配置（nginx.conf.sample）
        if grep -q "nginx.conf.sample" "$nginx_config"; then
            echo "[SUCCESS] 使用 Magento 2 简化配置（nginx.conf.sample）"
            echo "[SUCCESS] 包含 try_files 配置（在 nginx.conf.sample 中）"
            echo "[SUCCESS] PHP-FPM 配置存在（在 nginx.conf.sample 中）"
        else
            # 检查 Magento 2 特定的 Nginx 配置
            if grep -q "try_files" "$nginx_config"; then
                echo "[SUCCESS] 包含 try_files 配置"
            else
                log_warning "缺少 try_files 配置，需要 Magento 2 优化"
            fi
            
            if grep -q "fastcgi_pass" "$nginx_config"; then
                echo "[SUCCESS] PHP-FPM 配置存在"
            else
                log_warning "缺少 PHP-FPM 配置"
            fi
        fi
    else
        log_error "Nginx 站点配置不存在: $nginx_config"
    fi
    
    # 检查 MySQL 配置
    echo ""
    echo "MySQL 配置检查:"
    echo "----------------------------------------"
    local mysql_version
    mysql_version="$(mysql --version | awk '{print $3}' | cut -d. -f1,2)"
    echo "MySQL 版本: $mysql_version"
    
    if [[ "$mysql_version" == "8.0" || "$mysql_version" == "8.4" ]]; then
        log_success "MySQL 版本兼容 Magento 2"
    else
        log_warning "MySQL 版本可能不兼容 Magento 2，建议使用 MySQL 8.0+"
    fi
    
    # 检查 Composer
    echo ""
    echo "Composer 检查:"
    echo "----------------------------------------"
    if command -v composer >/dev/null 2>&1; then
        local composer_version
        composer_version="$(composer --version | awk '{print $3}')"
        echo "[SUCCESS] Composer 版本: $composer_version"
    else
        log_error "Composer 未安装"
    fi
    
    # 检查内存限制和执行时间（优先检查FPM配置）
    echo ""
    echo "系统资源检查:"
    echo "----------------------------------------"
    
    # 检查FPM配置
    local fpm_ini="/etc/php/8.3/fpm/php.ini"
    if [[ -f "$fpm_ini" ]]; then
        local memory_limit
        memory_limit="$(grep "^memory_limit" "$fpm_ini" | cut -d'=' -f2 | tr -d ' ')"
        local max_execution_time
        max_execution_time="$(grep "^max_execution_time" "$fpm_ini" | cut -d'=' -f2 | tr -d ' ')"
        echo "PHP 内存限制: $memory_limit (FPM配置)"
        echo "PHP 执行时间限制: ${max_execution_time}s (FPM配置)"
    else
        # 回退到CLI配置
        local memory_limit
        memory_limit="$(php -r "echo ini_get('memory_limit');")"
        local max_execution_time
        max_execution_time="$(php -r "echo ini_get('max_execution_time');")"
        echo "PHP 内存限制: $memory_limit (CLI配置)"
        echo "PHP 执行时间限制: ${max_execution_time}s (CLI配置)"
    fi
    
    # 检查磁盘空间
    local disk_usage
    disk_usage="$(df -h "$site_path" | awk 'NR==2 {print $5}' | sed 's/%//')"
    echo "磁盘使用率: ${disk_usage}%"
    
    if [[ "$disk_usage" -lt 80 ]]; then
        log_success "磁盘空间充足"
    else
        log_warning "磁盘空间不足，建议清理"
    fi
    
    echo ""
    echo "兼容性总结:"
    echo "=========================================="
    if [[ ${#missing_extensions[@]} -eq 0 ]] && [[ "$php_version" == "8.3" || "$php_version" == "8.2" || "$php_version" == "8.1" ]]; then
        log_success "系统环境兼容 Magento 2"
        log_info "可以运行 'convert magento2' 进行转换"
    else
        log_warning "系统环境需要优化才能完全兼容 Magento 2"
        log_info "建议先解决上述问题后再进行转换"
    fi
}

# 转换为 Magento 2 配置
convert_to_magento2() {
    local site_input="${1:-$(pwd)}"
    local site_path=""
    
    # 判断输入是路径还是站点名称
    if [[ "$site_input" =~ ^/ ]]; then
        # 如果是绝对路径，直接使用
        site_path="$site_input"
    else
        # 如果是站点名称，构建标准路径
        site_path="/var/www/$site_input"
    fi
    
    # 检查是否在 Magento 目录中
    if [[ ! -f "$site_path/bin/magento" ]]; then
        log_error "未在 Magento 目录中，请指定正确的路径或站点名称"
        log_info "用法: saltgoat magetools convert magento2 [site_name|path]"
        log_info "示例: saltgoat magetools convert magento2 tank"
        log_info "示例: saltgoat magetools convert magento2 /var/www/tank"
        return 1
    fi
    
    log_highlight "转换站点 Nginx 配置为 Magento 2: $site_path"
    
    # 先检查兼容性
    log_info "检查系统兼容性..."
    check_magento2_compatibility "$site_path"
    
    # 直接优化 Nginx 配置为 Magento 2
    log_info "优化 Nginx 配置为 Magento 2..."
    optimize_nginx_for_magento2 "$site_path"
    
    log_success "Magento 2 Nginx 配置转换完成！"
    log_info "注意: 此命令仅转换 Nginx 配置"
    log_info "如需其他 Magento 2 操作，请手动运行："
    echo "  cd $site_path"
    echo "  php bin/magento cache:clean"
    echo "  php bin/magento setup:di:compile"
    echo "  php bin/magento setup:static-content:deploy -f"
    echo "  php bin/magento indexer:reindex"
    echo "  saltgoat magetools permissions fix $site_path"
}

# 优化 Nginx 配置为 Magento 2
optimize_nginx_for_magento2() {
    local site_path="$1"
    local site_name
    site_name="$(basename "$site_path")"
    
    log_info "优化 Nginx 配置为 Magento 2..."
    
    # 检查站点配置文件是否存在
    if [[ ! -f "/etc/nginx/sites-enabled/$site_name" ]]; then
        log_error "站点配置文件不存在: /etc/nginx/sites-enabled/$site_name"
        log_info "请先使用 'saltgoat nginx create $site_name <domain>' 创建站点"
        return 1
    fi
    
    # 备份原配置到 sites-available 目录
    local nginx_backup_ts
    nginx_backup_ts="$(date +%Y%m%d_%H%M%S)"
    sudo cp "/etc/nginx/sites-enabled/$site_name" "/etc/nginx/sites-available/$site_name.backup.${nginx_backup_ts}"
    
    # 从原配置中提取域名信息
    local server_name
    server_name="$(grep "server_name" "/etc/nginx/sites-enabled/$site_name" | head -1 | sed 's/.*server_name[[:space:]]*//; s/;.*//')"
    
    if [[ -z "$server_name" ]]; then
        log_error "无法从原配置中提取域名信息"
        return 1
    fi
    
    log_info "检测到域名: $server_name"
    
    # 检查是否有 SSL 配置
    local has_ssl=false
    local backup_file
    backup_file="$(find /etc/nginx/sites-available -maxdepth 1 -name "${site_name}.backup.*" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | awk '{print $2}')"
    if [[ -n "$backup_file" ]] && grep -q "ssl_certificate" "$backup_file"; then
        has_ssl=true
        log_info "检测到 SSL 配置，将保持 HTTPS 设置"
    fi
    
    # 创建简化的 Magento 2 Nginx 配置（使用 nginx.conf.sample）
    # 注意：upstream fastcgi_backend 已在主配置文件中定义
    if [[ "$has_ssl" == "true" ]]; then
        # 如果有 SSL，创建 HTTP 重定向和 HTTPS 配置
        sudo tee "/etc/nginx/sites-enabled/$site_name" >/dev/null <<EOF
server {
    listen 80;
    server_name $server_name;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name $server_name;
    set \$MAGE_ROOT $site_path;
    include $site_path/nginx.conf.sample;
    
    # SSL 配置
    ssl_certificate /etc/letsencrypt/live/$site_name/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$site_name/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers off;
}
EOF
    else
        # 如果没有 SSL，只创建 HTTP 配置
        sudo tee "/etc/nginx/sites-enabled/$site_name" >/dev/null <<EOF
server {
    listen 80;
    server_name $server_name;
    set \$MAGE_ROOT $site_path;
    include $site_path/nginx.conf.sample;
}
EOF
    fi
    log_info "已创建 Magento 2 配置（使用主配置文件中的 fastcgi_backend upstream）"
    
    # 测试 Nginx 配置
    if sudo /usr/sbin/nginx -t -c /etc/nginx/nginx.conf; then
        sudo systemctl reload nginx
        log_success "Nginx 配置已更新为 Magento 2 简化配置（使用 nginx.conf.sample）"
        log_info "配置特点:"
        log_info "  - 使用官方 nginx.conf.sample"
        log_info "  - 包含 fastcgi_backend upstream 定义"
        log_info "  - 自动提取原域名配置"
    else
        log_error "Nginx 配置有误，请检查"
        # 恢复备份
        local backup_file
        backup_file="$(find /etc/nginx/sites-available -maxdepth 1 -name "${site_name}.backup.*" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | awk '{print $2}')"
        if [[ -n "$backup_file" ]]; then
            sudo cp "$backup_file" "/etc/nginx/sites-enabled/$site_name"
            log_info "已恢复备份配置"
        fi
        return 1
    fi
}

# 优化 PHP 配置为 Magento 2
optimize_php_for_magento2() {
    log_info "优化 PHP 配置为 Magento 2..."
    
    # 备份原配置
    local php_backup_ts
    php_backup_ts="$(date +%Y%m%d_%H%M%S)"
    sudo cp /etc/php/8.3/fpm/php.ini "/etc/php/8.3/fpm/php.ini.backup.${php_backup_ts}"
    
    # 优化 PHP 配置
    sudo sed -i 's/memory_limit = .*/memory_limit = 2G/' /etc/php/8.3/fpm/php.ini
    sudo sed -i 's/max_execution_time = .*/max_execution_time = 300/' /etc/php/8.3/fpm/php.ini
    sudo sed -i 's/max_input_time = .*/max_input_time = 300/' /etc/php/8.3/fpm/php.ini
    sudo sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' /etc/php/8.3/fpm/php.ini
    sudo sed -i 's/post_max_size = .*/post_max_size = 64M/' /etc/php/8.3/fpm/php.ini
    sudo sed -i 's/max_input_vars = .*/max_input_vars = 3000/' /etc/php/8.3/fpm/php.ini
    
    # 重启 PHP-FPM
    sudo systemctl restart php8.3-fpm
    
    log_success "PHP 配置已优化为 Magento 2"
}

# 优化 MySQL 配置为 Magento 2
optimize_mysql_for_magento2() {
    log_info "优化 MySQL 配置为 Magento 2..."
    
    # 检查是否已经有 Magento 优化配置
    if grep -q "# Magento 2 优化配置" /etc/mysql/mysql.conf.d/lemp.cnf; then
        log_info "MySQL 配置已经包含 Magento 2 优化，跳过优化步骤"
        return 0
    fi
    
    # 备份原配置
    local mysql_backup_ts
    mysql_backup_ts="$(date +%Y%m%d_%H%M%S)"
    sudo cp /etc/mysql/mysql.conf.d/lemp.cnf "/etc/mysql/mysql.conf.d/lemp.cnf.backup.${mysql_backup_ts}"
    
    # 添加 Magento 2 优化配置（使用 Percona 8.4+ 兼容参数）
    sudo tee -a /etc/mysql/mysql.conf.d/lemp.cnf >/dev/null <<EOF

# Magento 2 优化配置 (Percona 8.4+ 兼容)
# 基本设置
innodb_buffer_pool_size = 1G
innodb_log_buffer_size = 16M
innodb_flush_log_at_trx_commit = 2
innodb_thread_concurrency = 16

# 连接设置
max_connections = 500
max_connect_errors = 10000

# 临时表
tmp_table_size = 64M
max_heap_table_size = 64M

# 其他优化
table_open_cache = 4000
thread_cache_size = 16
EOF
    
    # 重启 MySQL
    if sudo systemctl restart mysql; then
        log_success "MySQL 配置已优化为 Magento 2"
    else
        log_error "MySQL 重启失败，请检查配置"
        log_info "恢复备份配置..."
        sudo cp "/etc/mysql/mysql.conf.d/lemp.cnf.backup.${mysql_backup_ts}" /etc/mysql/mysql.conf.d/lemp.cnf
        sudo systemctl restart mysql
        return 1
    fi
}

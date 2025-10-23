#!/bin/bash
# Nginx 服务管理模块
# services/nginx.sh

# Nginx 处理函数
nginx_handler() {
    case "$2" in
        "create")
            if [[ -z "$3" || -z "$4" ]]; then
                log_error "用法: saltgoat nginx create <site> <domain> [custom_path]"
                log_info "示例: saltgoat nginx create mysite example.com"
                log_info "示例: saltgoat nginx create hawk hawktattoosupply.com /home/doge/hawk"
                log_info "注意: 自动支持 example.com 和 www.example.com 双域名"
                exit 1
            fi
            log_highlight "创建 Nginx 站点配置: $3 (支持 $4 和 www.$4)"
            nginx_create_site "$3" "$4" "$5"
            ;;
        "list")
            log_highlight "列出所有 Nginx 站点..."
            nginx_list_sites
            ;;
        "add-ssl")
            if [[ -z "$3" || -z "$4" ]]; then
                log_error "用法: saltgoat nginx add-ssl <site> <domain> [email]"
                log_info "示例: saltgoat nginx add-ssl mysite example.com"
                log_info "示例: saltgoat nginx add-ssl mysite example.com admin@example.com"
                exit 1
            fi
            log_highlight "为站点添加 SSL 证书: $3 ($4)"
            nginx_add_ssl "$3" "$4" "$5"
            ;;
        "delete")
            if [[ -z "$3" ]]; then
                log_error "用法: saltgoat nginx delete <site>"
                exit 1
            fi
            log_highlight "删除 Nginx 站点: $3"
            nginx_delete_site "$3"
            ;;
        "enable")
            if [[ -z "$3" ]]; then
                log_error "用法: saltgoat nginx enable <site>"
                exit 1
            fi
            log_highlight "启用 Nginx 站点: $3"
            nginx_enable_site "$3"
            ;;
        "disable")
            if [[ -z "$3" ]]; then
                log_error "用法: saltgoat nginx disable <site>"
                exit 1
            fi
            log_highlight "禁用 Nginx 站点: $3"
            nginx_disable_site "$3"
            ;;
        "reload")
            log_highlight "重新加载 Nginx 配置..."
            nginx_reload
            ;;
        "test")
            log_highlight "测试 Nginx 配置..."
            nginx_test_config
            ;;
               "csp")
                   source "${SCRIPT_DIR}/modules/security/csp-salt.sh"
                   csp_salt_handler "csp" "$3" "$4"
                   ;;
        "help")
            show_nginx_help
            ;;
               "modsecurity")
                   # 加载 ModSecurity Salt 模块
                   if [[ -f "${SCRIPT_DIR}/modules/security/modsecurity-salt.sh" ]]; then
                       source "${SCRIPT_DIR}/modules/security/modsecurity-salt.sh"
                       modsecurity_salt_handler "modsecurity" "$3" "$4"
                   else
                       log_error "ModSecurity Salt 模块不存在"
                       exit 1
                   fi
                   ;;
        *)
            log_error "未知的 Nginx 操作: $2"
            log_info "支持: create, list, add-ssl, delete, enable, disable, reload, test, modsecurity, help"
            exit 1
            ;;
    esac
}

# 创建 Nginx 站点
nginx_create_site() {
    local site="$1"
    local domains="$2"
    local custom_path="$3"
    
    # 确定站点路径
    local site_path="${custom_path:-/var/www/$site}"
    
    log_info "创建站点目录: $site_path"
    sudo mkdir -p "$site_path"
    
    log_info "创建默认页面"
    sudo bash -c "echo \"<h1>Welcome to $site</h1>\" > $site_path/index.html"
    
    log_info "设置站点权限"
    sudo chown -R www-data:www-data "$site_path"
    sudo chmod -R 755 "$site_path"
    
    log_info "创建 Nginx 配置文件"
    local config_file="/etc/nginx/sites-available/$site"
    
    cat > /tmp/nginx_site.conf << EOF
server {
    listen 80;
    server_name $domains;
    root $site_path;
    index index.html index.php;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location ~ \.php$ {
        include /etc/nginx/snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
    }
}
EOF
    
    sudo cp /tmp/nginx_site.conf "$config_file"
    rm /tmp/nginx_site.conf
    
    log_info "启用站点配置"
    sudo ln -sf "$config_file" "/etc/nginx/sites-enabled/$site"
    
    log_info "测试 Nginx 配置"
    sudo /usr/sbin/nginx -t -c /etc/nginx/nginx.conf
    
    log_info "重新加载 Nginx"
    sudo systemctl reload nginx
    
    log_success "Nginx 站点创建成功: $site ($domain)"
    log_info "站点路径: $site_path"
    log_info "配置文件: $config_file"
    log_info "启用链接: /etc/nginx/sites-enabled/$site"
}

# 列出所有站点
nginx_list_sites() {
    echo "SaltGoat Nginx 站点:"
    if [[ -d "/etc/nginx/sites-enabled" ]]; then
        ls -la /etc/nginx/sites-enabled/ | grep -v "default" | awk '{print $9}' | grep -v "^$" | grep -v "^\.$" | grep -v "^\.\.$" | while read site; do
            if [[ -n "$site" ]]; then
                echo "  - $site"
            fi
        done
    else
        echo "  没有找到启用的站点"
    fi
}

# 添加 SSL 证书
nginx_add_ssl() {
    local site="$1"
    local domains="$2"
    local email="$3"
    
    # 如果没有提供邮箱，尝试从 Salt Pillar 获取
    if [[ -z "$email" ]]; then
        email=$(salt-call --local pillar.get ssl_email --out=txt 2>/dev/null | grep -o '[^:]*$' | tr -d ' ')
    fi
    
    # 如果 Salt Pillar 中也没有配置 email，提示用户输入
    if [[ -z "$email" || "$email" == "None" ]]; then
        echo ""
        log_info "SSL 邮箱未配置，请输入用于 SSL 证书申请的邮箱地址："
        read -p "邮箱地址: " email
        
        # 验证邮箱格式
        if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            log_error "邮箱格式不正确，请重新输入"
            return 1
        fi
        
        log_info "使用邮箱: $email"
    fi
    
    log_info "为 $site 申请 SSL 证书"
    log_info "域名: $domains"
    log_info "使用邮箱: $email"
    
    # 构建 certbot 命令
    local certbot_cmd="sudo certbot certonly --webroot -w \"/var/www/$site/pub\" --email \"$email\" --agree-tos --no-eff-email --cert-name \"$site\""
    
    # 添加所有域名
    for domain in $domains; do
        certbot_cmd="$certbot_cmd -d \"$domain\""
    done
    
    # 执行 certbot 命令
    eval $certbot_cmd
    
    # 手动添加 SSL 配置到现有的 server 块
    local config_file="/etc/nginx/sites-enabled/$site"
    if [[ -f "$config_file" ]]; then
        # 备份原配置到 sites-available 目录
        sudo cp "$config_file" "/etc/nginx/sites-available/$site.backup.$(date +%Y%m%d_%H%M%S)"
        
        # 添加 SSL 配置
        sudo tee "$config_file" >/dev/null <<EOF
server {
    listen 80;
    server_name $domains;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name $domains;
    set \$MAGE_ROOT /var/www/$site;
    include /var/www/$site/nginx.conf.sample;
    
    # SSL 配置
    ssl_certificate /etc/letsencrypt/live/$site/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$site/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers off;
}
EOF
        
        # 测试并重新加载 Nginx
        if sudo /usr/sbin/nginx -t -c /etc/nginx/nginx.conf; then
            sudo systemctl reload nginx
            log_success "SSL 证书申请完成: $site ($domain)"
        else
            log_error "Nginx 配置测试失败，请检查配置"
            return 1
        fi
    else
        log_error "找不到站点配置文件: $config_file"
        return 1
    fi
}

# 删除站点
nginx_delete_site() {
    local site="$1"
    
    log_info "删除站点: $site"
    
    # 删除 Nginx 配置文件
    sudo rm -f "/etc/nginx/sites-available/$site"
    sudo rm -f "/etc/nginx/sites-enabled/$site"
    
    # 删除站点目录
    sudo rm -rf "/var/www/$site"
    
    # 删除 SSL 证书（如果存在）
    if [[ -d "/etc/letsencrypt/live/$site" ]]; then
        log_info "删除 SSL 证书: $site"
        sudo certbot delete --cert-name "$site" --non-interactive
    fi
    
    # 删除 SSL 证书配置目录
    sudo rm -rf "/etc/letsencrypt/live/$site"
    sudo rm -rf "/etc/letsencrypt/archive/$site"
    sudo rm -rf "/etc/letsencrypt/renewal/$site.conf"
    
    # 删除 Nginx 日志文件（如果存在）
    sudo rm -f "/var/log/nginx/${site}_access.log"
    sudo rm -f "/var/log/nginx/${site}_error.log"
    
    log_info "重新加载 Nginx"
    sudo systemctl reload nginx
    
    log_success "Nginx 站点删除成功: $site"
    log_info "已删除:"
    log_info "  - Nginx 配置文件"
    log_info "  - 站点目录: /var/www/$site"
    log_info "  - SSL 证书（如果存在）"
    log_info "  - 日志文件（如果存在）"
}

# 启用站点
nginx_enable_site() {
    local site="$1"
    
    if [[ ! -f "/etc/nginx/sites-available/$site" ]]; then
        log_error "站点配置文件不存在: /etc/nginx/sites-available/$site"
        return 1
    fi
    
    if [[ -L "/etc/nginx/sites-enabled/$site" ]]; then
        log_warning "站点已经启用: $site"
        return 0
    fi
    
    sudo ln -sf "/etc/nginx/sites-available/$site" "/etc/nginx/sites-enabled/$site"
    
    if sudo /usr/sbin/nginx -t -c /etc/nginx/nginx.conf; then
        sudo systemctl reload nginx
        log_success "站点启用成功: $site"
    else
        sudo rm -f "/etc/nginx/sites-enabled/$site"
        log_error "Nginx 配置测试失败，站点未启用"
        return 1
    fi
}

# 禁用站点
nginx_disable_site() {
    local site="$1"
    
    if [[ ! -L "/etc/nginx/sites-enabled/$site" ]]; then
        log_warning "站点已经禁用: $site"
        return 0
    fi
    
    sudo rm -f "/etc/nginx/sites-enabled/$site"
    sudo systemctl reload nginx
    
    log_success "站点禁用成功: $site"
}

# 重新加载 Nginx
nginx_reload() {
    if sudo /usr/sbin/nginx -t -c /etc/nginx/nginx.conf; then
        sudo systemctl reload nginx
        log_success "Nginx 配置重新加载成功"
    else
        log_error "Nginx 配置测试失败，未重新加载"
        return 1
    fi
}

# 测试 Nginx 配置
nginx_test_config() {
    if sudo /usr/sbin/nginx -t -c /etc/nginx/nginx.conf; then
        log_success "Nginx 配置测试通过"
    else
        log_error "Nginx 配置测试失败"
        return 1
    fi
}

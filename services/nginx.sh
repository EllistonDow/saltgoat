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
        *)
            log_error "未知的 Nginx 操作: $2"
            log_info "支持: create, list, add-ssl, delete"
            exit 1
            ;;
    esac
}

# 创建 Nginx 站点
nginx_create_site() {
    local site="$1"
    local domain="$2"
    local custom_path="$3"
    
    # 确定站点路径
    local site_path="${custom_path:-/var/www/$site}"
    
    log_info "创建站点目录: $site_path"
    salt-call --local cmd.run "sudo mkdir -p $site_path"
    
    log_info "创建默认页面"
    salt-call --local cmd.run "sudo bash -c 'echo \"<h1>Welcome to $site</h1>\" > $site_path/index.html'"
    
    log_info "设置站点权限"
    salt-call --local cmd.run "sudo chown -R www-data:www-data $site_path"
    salt-call --local cmd.run "sudo chmod -R 755 $site_path"
    
    log_info "创建 Nginx 配置文件"
    local config_file="/usr/local/nginx/conf/sites-available/$site"
    
    cat > /tmp/nginx_site.conf << EOF
server {
    listen 80;
    server_name $domain www.$domain;
    root $site_path;
    index index.html index.php;
    
    # 重定向非 www 到 www
    if (\$host = $domain) {
        return 301 http://www.$domain\$request_uri;
    }
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location ~ \.php$ {
        include /usr/local/nginx/conf/snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
    }
}
EOF
    
    sudo cp /tmp/nginx_site.conf "$config_file"
    rm /tmp/nginx_site.conf
    
    log_info "启用站点配置"
    sudo ln -sf "$config_file" "/usr/local/nginx/conf/sites-enabled/$site"
    
    # 创建系统级符号链接
    sudo ln -sf "$config_file" "/etc/nginx/sites-available/$site"
    sudo ln -sf "$config_file" "/etc/nginx/sites-enabled/$site"
    
    log_info "测试 Nginx 配置"
    salt-call --local cmd.run "sudo /usr/local/nginx/sbin/nginx -t"
    
    log_info "重新加载 Nginx"
    salt-call --local cmd.run "sudo systemctl reload nginx"
    
    log_success "Nginx 站点创建成功: $site ($domain)"
    log_info "站点路径: $site_path"
    log_info "配置文件: $config_file"
    log_info "启用链接: /usr/local/nginx/conf/sites-enabled/$site"
}

# 列出所有站点
nginx_list_sites() {
    echo "SaltGoat Nginx 站点:"
    ls -la /usr/local/nginx/conf/sites-enabled/ | grep -v "default" | awk '{print $9}' | grep -v "^$" | grep -v "^\.$" | grep -v "^\.\.$" | while read site; do
        if [[ -n "$site" ]]; then
            echo "  - $site"
        fi
    done
}

# 添加 SSL 证书
nginx_add_ssl() {
    local site="$1"
    local domain="$2"
    local email="${3:-admin@$domain}"
    
    log_info "为 $site ($domain) 申请 SSL 证书"
    
    # 使用 certbot 申请证书
    sudo certbot --nginx \
        --nginx-server-root /usr/local/nginx/conf \
        --nginx-ctl /usr/local/nginx/sbin/nginx \
        --email "$email" \
        --agree-tos \
        --no-eff-email \
        --domains "$domain,www.$domain" \
        --cert-name "$site"
    
    log_success "SSL 证书申请完成: $site ($domain)"
}

# 删除站点
nginx_delete_site() {
    local site="$1"
    
    log_info "删除站点: $site"
    
    # 删除配置文件
    sudo rm -f "/usr/local/nginx/conf/sites-available/$site"
    sudo rm -f "/usr/local/nginx/conf/sites-enabled/$site"
    
    # 删除系统级符号链接
    sudo rm -f "/etc/nginx/sites-available/$site"
    sudo rm -f "/etc/nginx/sites-enabled/$site"
    
    # 删除站点目录
    salt-call --local cmd.run "sudo rm -rf /var/www/$site"
    
    log_info "重新加载 Nginx"
    salt-call --local cmd.run "sudo systemctl reload nginx"
    
    log_success "Nginx 站点删除成功: $site"
}

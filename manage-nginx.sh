#!/bin/bash

# SaltGoat Nginx 多站点管理脚本
# 用于创建和管理多个站点的 Nginx 配置

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        exit 1
    fi
}

# 检查 Nginx 服务状态
check_nginx() {
    if ! systemctl is-active --quiet nginx; then
        log_error "Nginx 服务未运行，请先启动服务"
        exit 1
    fi
}

# 创建站点配置
create_site() {
    local site_name="$1"
    local domain="$2"
    local document_root="$3"
    
    if [[ -z "$site_name" ]] || [[ -z "$domain" ]]; then
        log_error "用法: $0 create <site_name> <domain> [document_root]"
        exit 1
    fi
    
    document_root="${document_root:-/var/www/html/$site_name}"
    
    log_info "为站点 $site_name 创建 Nginx 配置..."
    
    # 创建网站目录
    mkdir -p "$document_root"
    chown -R www-data:www-data "$document_root"
    chmod -R 755 "$document_root"
    
    # 创建默认 index.html
    cat > "$document_root/index.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Welcome to $site_name</title>
</head>
<body>
    <h1>Welcome to $site_name</h1>
    <p>This is the default page for $domain</p>
    <p>Document root: $document_root</p>
</body>
</html>
EOF
    
    # 创建 Nginx 配置
    cat > "/etc/nginx/sites-available/$site_name" << EOF
server {
    listen 80;
    server_name $domain;
    root $document_root;
    index index.php index.html index.htm;
    
    # 安全设置
    server_tokens off;
    
    # 日志
    access_log /var/log/nginx/${site_name}_access.log;
    error_log /var/log/nginx/${site_name}_error.log;
    
    # 主目录
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # PHP 支持
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    
    # 隐藏敏感文件
    location ~ /\.ht {
        deny all;
    }
    
    location ~ /\.git {
        deny all;
    }
    
    # 静态文件缓存
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # 限制文件上传大小
    client_max_body_size 100M;
}
EOF
    
    # 启用站点
    ln -sf "/etc/nginx/sites-available/$site_name" "/etc/nginx/sites-enabled/$site_name"
    
    # 测试配置
    if nginx -t; then
        systemctl reload nginx
        log_success "站点 $site_name 创建成功"
        echo "域名: $domain"
        echo "文档根目录: $document_root"
        echo "配置文件: /etc/nginx/sites-available/$site_name"
        echo "访问地址: http://$domain"
    else
        log_error "Nginx 配置测试失败"
        rm -f "/etc/nginx/sites-enabled/$site_name"
        exit 1
    fi
}

# 删除站点
delete_site() {
    local site_name="$1"
    local keep_files="$2"
    
    if [[ -z "$site_name" ]]; then
        log_error "用法: $0 delete <site_name> [keep_files]"
        exit 1
    fi
    
    log_warning "确定要删除站点 $site_name 吗？"
    if [[ "$keep_files" != "keep" ]]; then
        log_warning "这将删除网站文件！"
    fi
    read -p "输入 'yes' 确认: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "操作已取消"
        exit 0
    fi
    
    log_info "删除站点 $site_name..."
    
    # 禁用站点
    rm -f "/etc/nginx/sites-enabled/$site_name"
    
    # 删除配置文件
    rm -f "/etc/nginx/sites-available/$site_name"
    
    # 删除日志文件
    rm -f "/var/log/nginx/${site_name}_access.log"
    rm -f "/var/log/nginx/${site_name}_error.log"
    
    # 删除网站文件（可选）
    if [[ "$keep_files" != "keep" ]]; then
        document_root=$(grep -o "root [^;]*" "/etc/nginx/sites-available/$site_name" 2>/dev/null | awk '{print $2}' || echo "/var/www/html/$site_name")
        if [[ -d "$document_root" ]]; then
            rm -rf "$document_root"
        fi
    fi
    
    # 重新加载 Nginx
    if nginx -t; then
        systemctl reload nginx
        log_success "站点 $site_name 删除成功"
    else
        log_error "Nginx 配置测试失败"
        exit 1
    fi
}

# 列出所有站点
list_sites() {
    log_info "列出所有站点配置..."
    
    echo "=== 启用的站点 ==="
    for site in /etc/nginx/sites-enabled/*; do
        if [[ -f "$site" ]]; then
            site_name=$(basename "$site")
            server_name=$(grep "server_name" "$site" | awk '{print $2}' | sed 's/;//')
            root_dir=$(grep "root" "$site" | awk '{print $2}' | sed 's/;//')
            echo "站点: $site_name"
            echo "  域名: $server_name"
            echo "  根目录: $root_dir"
            echo "  配置文件: $site"
            echo ""
        fi
    done
    
    echo "=== 可用的站点 ==="
    for site in /etc/nginx/sites-available/*; do
        if [[ -f "$site" ]] && [[ ! -L "/etc/nginx/sites-enabled/$(basename "$site")" ]]; then
            site_name=$(basename "$site")
            echo "站点: $site_name (未启用)"
        fi
    done
}

# 启用站点
enable_site() {
    local site_name="$1"
    
    if [[ -z "$site_name" ]]; then
        log_error "用法: $0 enable <site_name>"
        exit 1
    fi
    
    if [[ ! -f "/etc/nginx/sites-available/$site_name" ]]; then
        log_error "站点配置文件不存在: /etc/nginx/sites-available/$site_name"
        exit 1
    fi
    
    log_info "启用站点 $site_name..."
    
    ln -sf "/etc/nginx/sites-available/$site_name" "/etc/nginx/sites-enabled/$site_name"
    
    if nginx -t; then
        systemctl reload nginx
        log_success "站点 $site_name 启用成功"
    else
        log_error "Nginx 配置测试失败"
        rm -f "/etc/nginx/sites-enabled/$site_name"
        exit 1
    fi
}

# 禁用站点
disable_site() {
    local site_name="$1"
    
    if [[ -z "$site_name" ]]; then
        log_error "用法: $0 disable <site_name>"
        exit 1
    fi
    
    log_info "禁用站点 $site_name..."
    
    rm -f "/etc/nginx/sites-enabled/$site_name"
    
    if nginx -t; then
        systemctl reload nginx
        log_success "站点 $site_name 禁用成功"
    else
        log_error "Nginx 配置测试失败"
        exit 1
    fi
}

# 添加 SSL 证书
add_ssl() {
    local site_name="$1"
    local domain="$2"
    
    if [[ -z "$site_name" ]] || [[ -z "$domain" ]]; then
        log_error "用法: $0 add-ssl <site_name> <domain>"
        exit 1
    fi
    
    if [[ ! -f "/etc/nginx/sites-available/$site_name" ]]; then
        log_error "站点配置文件不存在: /etc/nginx/sites-available/$site_name"
        exit 1
    fi
    
    log_info "为站点 $site_name 添加 SSL 证书..."
    
    # 使用 Certbot 申请证书
    if command -v certbot &> /dev/null; then
        certbot --nginx -d "$domain" --non-interactive --agree-tos --email "${SSL_EMAIL:-admin@$domain}"
        
        if [[ $? -eq 0 ]]; then
            log_success "SSL 证书添加成功"
            echo "HTTPS 访问地址: https://$domain"
        else
            log_error "SSL 证书申请失败"
            exit 1
        fi
    else
        log_error "Certbot 未安装，请先安装 Certbot"
        exit 1
    fi
}

# 显示帮助信息
show_help() {
    echo "SaltGoat Nginx 多站点管理脚本"
    echo ""
    echo "用法: $0 <command> [options]"
    echo ""
    echo "命令:"
    echo "  create <site_name> <domain> [root]     - 创建新站点"
    echo "  delete <site_name> [keep]             - 删除站点"
    echo "  list                                  - 列出所有站点"
    echo "  enable <site_name>                    - 启用站点"
    echo "  disable <site_name>                   - 禁用站点"
    echo "  add-ssl <site_name> <domain>          - 添加 SSL 证书"
    echo "  help                                  - 显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 create mysite example.com"
    echo "  $0 create mysite example.com /var/www/mysite"
    echo "  $0 list"
    echo "  $0 add-ssl mysite example.com"
    echo "  $0 delete mysite"
}

# 主函数
main() {
    check_root
    check_nginx
    
    case "${1:-help}" in
        "create")
            create_site "$2" "$3" "$4"
            ;;
        "delete")
            delete_site "$2" "$3"
            ;;
        "list")
            list_sites
            ;;
        "enable")
            enable_site "$2"
            ;;
        "disable")
            disable_site "$2"
            ;;
        "add-ssl")
            add_ssl "$2" "$3"
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "无效的命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"

#!/bin/bash
# Adminer 数据库管理面板模块
# 提供轻量级的 Web 数据库管理界面

# 加载公共库
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${MODULE_DIR}/../../lib/logger.sh"
source "${MODULE_DIR}/../../lib/utils.sh"

# Adminer 配置
ADMINER_VERSION="4.8.1"
ADMINER_PORT="8081"
ADMINER_DIR="/var/www/adminer"
ADMINER_URL="https://github.com/vrana/adminer/releases/download/v${ADMINER_VERSION}/adminer-${ADMINER_VERSION}.php"

# Adminer 管理函数
adminer_install() {
    log_info "安装 Adminer 数据库管理面板..."
    
    # 创建目录
    sudo mkdir -p "$ADMINER_DIR"
    
    # 下载 Adminer
    log_info "下载 Adminer v${ADMINER_VERSION}..."
    sudo wget -O "${ADMINER_DIR}/adminer.php" "$ADMINER_URL"
    
    if [[ $? -eq 0 ]]; then
        log_success "Adminer 下载成功"
    else
        log_error "Adminer 下载失败"
        return 1
    fi
    
    # 设置权限
    sudo chown -R www-data:www-data "$ADMINER_DIR"
    sudo chmod 644 "${ADMINER_DIR}/adminer.php"
    
    # 创建 Nginx 配置
    adminer_create_nginx_config
    
    # 测试 Nginx 配置并重新加载
    if sudo nginx -t; then
        # 尝试不同的 Nginx 重新加载方式
        if systemctl is-active --quiet nginx 2>/dev/null; then
            # systemd 管理的 Nginx
            sudo systemctl reload nginx
            log_info "通过 systemctl 重新加载 Nginx"
        elif pgrep -f "nginx.*master" >/dev/null; then
            # 编译安装的 Nginx，使用信号重新加载
            sudo kill -HUP $(pgrep -f "nginx.*master" | head -1)
            log_info "通过信号重新加载 Nginx"
        else
            log_warning "无法重新加载 Nginx，请手动重启"
        fi
        
        # 配置防火墙
        log_info "配置防火墙规则..."
        if command -v ufw >/dev/null 2>&1; then
            sudo ufw allow ${ADMINER_PORT}/tcp
            log_success "UFW 规则已添加: 允许端口 ${ADMINER_PORT}"
        fi
        
        if command -v firewall-cmd >/dev/null 2>&1; then
            sudo firewall-cmd --permanent --add-port=${ADMINER_PORT}/tcp
            sudo firewall-cmd --reload
            log_success "Firewalld 规则已添加: 允许端口 ${ADMINER_PORT}"
        fi
        
        log_success "Adminer 安装完成"
        log_info "访问地址: http://$(hostname -I | awk '{print $1}'):${ADMINER_PORT}"
        log_info "默认登录: 使用 MySQL 用户凭据"
    else
        log_error "Nginx 配置错误"
        return 1
    fi
}

adminer_create_nginx_config() {
    log_info "创建 Adminer Nginx 配置..."
    
    # 检测 Nginx 安装方式并确定配置路径
    local nginx_config_dir
    if [[ -d "/etc/nginx" ]]; then
        # 标准 Nginx 安装
        nginx_config_dir="/etc/nginx"
        log_info "检测到标准 Nginx 安装，使用配置目录: $nginx_config_dir"
    else
        log_error "无法检测 Nginx 安装方式"
        return 1
    fi
    
    # 确保目录存在
    sudo mkdir -p "${nginx_config_dir}/sites-available"
    sudo mkdir -p "${nginx_config_dir}/sites-enabled"
    
    sudo tee "${nginx_config_dir}/sites-available/adminer" >/dev/null << 'EOF'
server {
    listen 8081;
    server_name _;
    root /var/www/adminer;
    index adminer.php;
    
    # 安全配置
    location ~ /\. {
        deny all;
    }
    
    # PHP 处理
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
    
    # 静态文件缓存
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
}
EOF
    
    # 启用站点
    sudo ln -sf "${nginx_config_dir}/sites-available/adminer" "${nginx_config_dir}/sites-enabled/"
    
    log_success "Nginx 配置创建完成"
}

adminer_uninstall() {
    log_info "卸载 Adminer 数据库管理面板..."
    
    # 删除 Nginx 配置
    sudo rm -f /etc/nginx/sites-enabled/adminer
    sudo rm -f /etc/nginx/sites-available/adminer
    
    # 删除文件
    sudo rm -rf "$ADMINER_DIR"
    
    # 重新加载 Nginx
    sudo nginx -t && sudo systemctl reload nginx
    
    log_success "Adminer 卸载完成"
}

adminer_status() {
    log_info "Adminer 状态检查:"
    
    # 检查文件是否存在
    if [[ -f "${ADMINER_DIR}/adminer.php" ]]; then
        echo "Adminer 文件: 存在"
        echo "版本: v${ADMINER_VERSION}"
        echo "位置: ${ADMINER_DIR}/adminer.php"
    else
        echo "Adminer 文件: 不存在"
    fi
    
    # 检查 Nginx 配置
    if [[ -f "/etc/nginx/sites-enabled/adminer" ]]; then
        echo "Nginx 配置: 已启用"
        echo "端口: 8081"
    else
        echo "Nginx 配置: 未启用"
    fi
    
    # 检查访问
    echo "访问地址: http://$(hostname -I | awk '{print $1}'):8081"
}

adminer_config() {
    local action="${1:-show}"
    
    case "$action" in
        "show")
            log_info "Adminer 配置信息:"
            echo "安装目录: $ADMINER_DIR"
            echo "版本: v${ADMINER_VERSION}"
            echo "端口: 8081"
            echo "Nginx 配置: /etc/nginx/sites-available/adminer"
            
            if [[ -f "/etc/nginx/sites-available/adminer" ]]; then
                echo ""
                echo "Nginx 配置内容:"
                cat /etc/nginx/sites-available/adminer
            fi
            ;;
        "update")
            log_info "更新 Adminer..."
            
            # 备份当前版本
            if [[ -f "${ADMINER_DIR}/adminer.php" ]]; then
                sudo cp "${ADMINER_DIR}/adminer.php" "${ADMINER_DIR}/adminer.php.backup"
            fi
            
            # 下载新版本
            sudo wget -O "${ADMINER_DIR}/adminer.php" "$ADMINER_URL"
            
            if [[ $? -eq 0 ]]; then
                sudo chown www-data:www-data "${ADMINER_DIR}/adminer.php"
                sudo chmod 644 "${ADMINER_DIR}/adminer.php"
                log_success "Adminer 更新完成"
            else
                log_error "Adminer 更新失败"
                return 1
            fi
            ;;
        "theme")
            local theme="${2:-default}"
            adminer_install_theme "$theme"
            ;;
        *)
            log_error "未知的配置操作: $action"
            log_info "可用操作: show, update, theme"
            return 1
            ;;
    esac
}

adminer_install_theme() {
    local theme="${1:-default}"
    
    log_info "安装 Adminer 主题: $theme"
    
    case "$theme" in
        "default")
            log_info "使用默认主题"
            ;;
        "nette")
            sudo wget -O "${ADMINER_DIR}/nette.php" "https://raw.githubusercontent.com/vrana/adminer/master/designs/nette/adminer.css"
            ;;
        "hydra")
            sudo wget -O "${ADMINER_DIR}/hydra.php" "https://raw.githubusercontent.com/vrana/adminer/master/designs/hydra/adminer.css"
            ;;
        "konya")
            sudo wget -O "${ADMINER_DIR}/konya.php" "https://raw.githubusercontent.com/vrana/adminer/master/designs/konya/adminer.css"
            ;;
        *)
            log_error "未知主题: $theme"
            log_info "可用主题: default, nette, hydra, konya"
            return 1
            ;;
    esac
    
    if [[ "$theme" != "default" ]]; then
        sudo chown www-data:www-data "${ADMINER_DIR}/${theme}.php"
        sudo chmod 644 "${ADMINER_DIR}/${theme}.php"
        log_success "主题 $theme 安装完成"
        log_info "访问地址: http://$(hostname -I | awk '{print $1}'):8081/${theme}.php"
    fi
}

adminer_security() {
    log_info "配置 Adminer 安全设置..."
    
    # 创建 .htaccess 文件（如果使用 Apache）
    sudo tee "${ADMINER_DIR}/.htaccess" >/dev/null << 'EOF'
# 限制访问 IP（可选）
# Require ip 192.168.1.0/24

# 禁用目录浏览
Options -Indexes

# 安全头
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
Header always set X-XSS-Protection "1; mode=block"
EOF
    
    # 创建登录限制脚本
    sudo tee "${ADMINER_DIR}/login.php" >/dev/null << 'EOF'
<?php
// Adminer 登录限制
session_start();

// 允许的数据库类型
$allowed_servers = [
    'localhost' => 'MySQL',
    '127.0.0.1' => 'MySQL'
];

// 检查服务器
if (isset($_POST['auth']['server']) && !isset($allowed_servers[$_POST['auth']['server']])) {
    die('不允许连接到该服务器');
}

// 包含 Adminer
include 'adminer.php';
?>
EOF
    
    sudo chown www-data:www-data "${ADMINER_DIR}/.htaccess" "${ADMINER_DIR}/login.php"
    sudo chmod 644 "${ADMINER_DIR}/.htaccess" "${ADMINER_DIR}/login.php"
    
    log_success "安全配置完成"
    log_info "建议使用: http://$(hostname -I | awk '{print $1}'):8081/login.php"
}

adminer_backup() {
    log_info "备份 Adminer 配置..."
    
    local backup_dir="/opt/saltgoat/backups/adminer"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    sudo mkdir -p "$backup_dir"
    
    # 备份文件
    if [[ -d "$ADMINER_DIR" ]]; then
        sudo tar -czf "${backup_dir}/adminer_${timestamp}.tar.gz" -C "$(dirname "$ADMINER_DIR")" "$(basename "$ADMINER_DIR")"
        log_success "Adminer 文件备份完成: ${backup_dir}/adminer_${timestamp}.tar.gz"
    fi
    
    # 备份 Nginx 配置
    if [[ -f "/etc/nginx/sites-available/adminer" ]]; then
        sudo cp "/etc/nginx/sites-available/adminer" "${backup_dir}/adminer_nginx_${timestamp}.conf"
        log_success "Nginx 配置备份完成: ${backup_dir}/adminer_nginx_${timestamp}.conf"
    fi
}

# 主函数
adminer_main() {
    local action="${1:-help}"
    
    case "$action" in
        "install")
            adminer_install
            ;;
        "uninstall")
            adminer_uninstall
            ;;
        "status")
            adminer_status
            ;;
        "config")
            adminer_config "${2:-show}"
            ;;
        "security")
            adminer_security
            ;;
        "backup")
            adminer_backup
            ;;
        "help"|*)
            log_info "Adminer 数据库管理面板命令:"
            echo ""
            echo "  install     - 安装 Adminer"
            echo "  uninstall   - 卸载 Adminer"
            echo "  status      - 查看状态和访问信息"
            echo "  config      - 配置管理 (show|update|theme)"
            echo "  security    - 配置安全设置"
            echo "  backup      - 备份配置"
            echo ""
            echo "示例:"
            echo "  saltgoat adminer install"
            echo "  saltgoat adminer status"
            echo "  saltgoat adminer config update"
            echo "  saltgoat adminer config theme nette"
            echo "  saltgoat adminer security"
            ;;
    esac
}

# 如果直接执行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    adminer_main "$@"
fi

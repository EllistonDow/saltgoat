#!/bin/bash
# OpenSearch Nginx 认证配置脚本
# modules/magetools/opensearch-auth.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"

# 配置参数
USERNAME="${1:-doge}"
PASSWORD="${USERNAME}2010"
OPENSEARCH_PORT="9200"
NGINX_PORT="9210"
PASSWD_FILE="/etc/nginx/passwd/.htpasswd_${USERNAME}_opensearch"
NGINX_CONFIG="/etc/nginx/sites-available/${USERNAME}_opensearch_auth.conf"
AUTH_CONFIG="/etc/nginx/auth/${USERNAME}_opensearch.conf"

# 显示帮助信息
show_help() {
    echo "OpenSearch Nginx 认证配置脚本"
    echo ""
    echo "用法: $0 [username]"
    echo ""
    echo "参数:"
    echo "  username    用户名 (默认: doge)"
    echo ""
    echo "示例:"
    echo "  $0 doge"
    echo "  $0 admin"
    echo ""
    echo "配置说明:"
    echo "  用户名: \$username"
    echo "  密码: \$username2010"
    echo "  Nginx端口: 9210"
    echo "  OpenSearch端口: 9200"
}

# 检查参数
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
    exit 0
fi

log_highlight "配置 OpenSearch Nginx 认证: $USERNAME"
log_info "用户名: $USERNAME"
log_info "密码: $PASSWORD"
log_info "Nginx端口: $NGINX_PORT"
log_info "OpenSearch端口: $OPENSEARCH_PORT"
echo ""

# 1. 检查并安装 htpasswd
log_info "1. 检查 htpasswd 命令..."
if ! command -v htpasswd >/dev/null 2>&1; then
    log_info "安装 apache2-utils..."
    sudo apt -y install apache2-utils
    if [[ $? -eq 0 ]]; then
        log_success "apache2-utils 安装完成"
    else
        log_error "apache2-utils 安装失败"
        exit 1
    fi
else
    log_success "htpasswd 命令已存在"
fi

# 2. 创建密码文件目录
log_info "2. 创建密码文件目录..."
sudo mkdir -p /etc/nginx/passwd
log_success "密码文件目录已创建"

# 3. 创建密码文件
log_info "3. 创建密码文件..."
if [[ -f "$PASSWD_FILE" ]]; then
    log_warning "密码文件已存在，更新密码..."
    sudo htpasswd "$PASSWD_FILE" "$USERNAME"
else
    log_info "创建新密码文件..."
    sudo htpasswd -c "$PASSWD_FILE" "$USERNAME"
fi

if [[ $? -eq 0 ]]; then
    log_success "密码文件创建/更新完成"
else
    log_error "密码文件创建失败"
    exit 1
fi

# 4. 创建 Nginx 主配置文件
log_info "4. 创建 Nginx 主配置文件..."
sudo mkdir -p /etc/nginx/sites-available

sudo tee "$NGINX_CONFIG" >/dev/null <<EOF
server {
  listen $NGINX_PORT;
  server_name 127.0.0.1;

  location / {
   limit_except HEAD {
      auth_basic "Restricted";
      auth_basic_user_file  $PASSWD_FILE;
   }
   proxy_pass http://127.0.0.1:$OPENSEARCH_PORT;
   proxy_redirect off;
   proxy_set_header Host \$host;
   proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }

  location /_aliases {
   auth_basic "Restricted";
   auth_basic_user_file  $PASSWD_FILE;
   proxy_pass http://127.0.0.1:$OPENSEARCH_PORT;
   proxy_redirect off;
   proxy_set_header Host \$host;
   proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }

  include /etc/nginx/auth/*.conf;
}
EOF

log_success "Nginx 主配置文件已创建"

# 5. 创建 auth 验证目录和配置文件
log_info "5. 创建 auth 验证配置..."
sudo mkdir -p /etc/nginx/auth/

sudo tee "$AUTH_CONFIG" >/dev/null <<EOF
location /opensearch {
auth_basic "Restricted - opensearch";
auth_basic_user_file $PASSWD_FILE;

proxy_pass http://127.0.0.1:$OPENSEARCH_PORT;
proxy_redirect off;
proxy_set_header Host \$host;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
}
EOF

log_success "auth 验证配置文件已创建"

# 6. 启用站点配置
log_info "6. 启用站点配置..."
sudo mkdir -p /etc/nginx/sites-enabled/
sudo ln -sf "$NGINX_CONFIG" "/etc/nginx/sites-enabled/"

log_success "站点配置已启用"

# 7. 测试 Nginx 配置
log_info "7. 测试 Nginx 配置..."
if sudo nginx -t; then
    log_success "Nginx 配置测试通过"
else
    log_error "Nginx 配置测试失败"
    exit 1
fi

# 8. 重启 Nginx
log_info "8. 重启 Nginx..."
sudo systemctl restart nginx
if [[ $? -eq 0 ]]; then
    log_success "Nginx 重启成功"
else
    log_error "Nginx 重启失败"
    exit 1
fi

# 9. 测试认证
log_info "9. 测试认证配置..."
echo ""
log_info "测试不带认证的访问 (应该返回 401):"
curl -s -i http://localhost:$NGINX_PORT/_cluster/health | head -1

echo ""
log_info "测试带认证的访问 (应该返回 200):"
curl -s -i -u "$USERNAME:$PASSWORD" http://localhost:$NGINX_PORT/_cluster/health | head -1

echo ""
log_success "OpenSearch Nginx 认证配置完成！"
echo ""
log_info "访问信息:"
echo "  URL: http://localhost:$NGINX_PORT"
echo "  用户名: $USERNAME"
echo "  密码: $PASSWORD"
echo ""
log_info "测试命令:"
echo "  curl -u $USERNAME:$PASSWORD http://localhost:$NGINX_PORT/_cluster/health"
echo ""
log_info "配置文件位置:"
echo "  密码文件: $PASSWD_FILE"
echo "  Nginx配置: $NGINX_CONFIG"
echo "  Auth配置: $AUTH_CONFIG"

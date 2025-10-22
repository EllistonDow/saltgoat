#!/bin/bash
# SaltGUI 集成模块
# services/saltgui.sh

# SaltGUI 配置
SALTGUI_PORT=3333
SALTGUI_HOST="0.0.0.0"
SALTGUI_CONFIG_DIR="/etc/saltgui"
SALTGUI_LOG_DIR="/var/log/saltgui"

# 确保 SaltGUI 目录存在
ensure_saltgui_dirs() {
    salt-call --local file.mkdir "$SALTGUI_CONFIG_DIR" 2>/dev/null || true
    salt-call --local file.mkdir "$SALTGUI_LOG_DIR" 2>/dev/null || true
}

# 安装 Salt Master 和 Salt API
install_salt_master_api() {
    log_info "安装 Salt Master 和 Salt API..."
    
    # 检查 Salt Master 是否已安装
    if ! command -v salt-master >/dev/null 2>&1; then
        log_info "安装 Salt Master..."
        salt-call --local pkg.install salt-master 2>/dev/null || {
            log_error "Salt Master 安装失败"
            return 1
        }
    else
        log_success "Salt Master 已安装"
    fi
    
    # 检查 Salt API 是否已安装
    if ! command -v salt-api >/dev/null 2>&1; then
        log_info "安装 Salt API..."
        salt-call --local pkg.install salt-api 2>/dev/null || {
            log_error "Salt API 安装失败"
            return 1
        }
    else
        log_success "Salt API 已安装"
    fi
    
    # 配置 Salt Master
    configure_salt_master
    
    # 检查 Salt Master 是否在运行
    if ! ss -tlnp | grep -q ":4506 "; then
        log_info "启动 Salt Master 服务..."
        salt-call --local service.start salt-master 2>/dev/null || {
            log_warning "Salt Master 启动失败，尝试手动启动..."
            sudo salt-master -d 2>/dev/null || {
                log_error "Salt Master 启动失败"
                return 1
            }
        }
    else
        log_success "Salt Master 已在运行"
    fi
    
    # 检查 Salt API 是否在运行
    if ! ss -tlnp | grep -q ":8000 "; then
        log_info "启动 Salt API 服务..."
        salt-call --local service.start salt-api 2>/dev/null || {
            log_warning "Salt API 启动失败，尝试手动启动..."
            sudo salt-api -d 2>/dev/null || {
                log_warning "Salt API 启动失败，继续安装 SaltGUI..."
            }
        }
    else
        log_success "Salt API 已在运行"
    fi
    
    # 设置开机自启
    salt-call --local service.enable salt-master 2>/dev/null || true
    salt-call --local service.enable salt-api 2>/dev/null || true
    
    log_success "Salt Master 和 Salt API 安装完成"
}

# 配置 Salt Master
configure_salt_master() {
    log_info "配置 Salt Master..."
    
    # 创建 Salt Master 配置目录
    salt-call --local file.mkdir "/etc/salt" 2>/dev/null || true
    
    # 创建 Salt Master 配置文件
    cat > "/tmp/salt_master_config" << EOF
# Salt Master 配置文件
interface: 0.0.0.0
publish_port: 4505
ret_port: 4506
user: root
worker_threads: 5
keep_jobs: 24
log_level: info
log_file: /var/log/salt/master
pidfile: /var/run/salt-master.pid

# Salt API 配置 (禁用SSL)
rest_cherrypy:
  host: 0.0.0.0
  port: 8000
  debug: False
  disable_ssl: True
  log_access_file: /var/log/salt/api_access.log
  log_error_file: /var/log/salt/api_error.log

# 外部认证配置（PAM）
external_auth:
  pam:
    saltgui:
      - .*
      - '@wheel'
      - '@runner'
      - '@jobs'

# 启用 Salt API 客户端
netapi_enable_clients:
  - wheel
  - runner
  - local
EOF
    
    # 移动配置文件
    sudo mv "/tmp/salt_master_config" "/etc/salt/master"
    sudo chmod 644 "/etc/salt/master"
    
    log_success "Salt Master 配置完成"
}

# 安装 SaltGUI
saltgui_install() {
    log_info "安装 SaltGUI..."
    
    # 检查是否已安装
    if [[ -f "/opt/saltgui/saltgui/index.html" ]]; then
        log_warning "SaltGUI 已安装"
        return 0
    fi
    
    # 首先安装 Salt Master 和 Salt API
    install_salt_master_api
    
    # 检查 Node.js 和 npm
    log_info "检查 Node.js 和 npm..."
    
    # 检查 Node.js
    if ! command -v node >/dev/null 2>&1; then
        log_info "安装 Node.js..."
        salt-call --local pkg.install nodejs 2>/dev/null || {
            log_error "Node.js 安装失败"
            return 1
        }
    else
        log_success "Node.js 已安装: $(node --version)"
    fi
    
    # 检查 npm
    if ! command -v npm >/dev/null 2>&1; then
        log_info "安装 npm..."
        salt-call --local pkg.install npm 2>/dev/null || {
            log_error "npm 安装失败"
            return 1
        }
    else
        log_success "npm 已安装: $(npm --version)"
    fi
    
    # 安装 SaltGUI (从 GitHub 源码)
    log_info "安装 SaltGUI..."
    
    # 创建安装目录
    local install_dir="/opt/saltgui"
    sudo mkdir -p "$install_dir"
    
    # 克隆 SaltGUI 仓库
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    log_info "从 GitHub 克隆 SaltGUI..."
    git clone https://github.com/erwindon/SaltGUI.git 2>/dev/null || {
        log_error "无法克隆 SaltGUI 仓库"
        cd - >/dev/null
        rm -rf "$temp_dir"
        return 1
    }
    
    cd SaltGUI
    
    # 复制文件到安装目录
    log_info "安装 SaltGUI 文件..."
    sudo cp -r * "$install_dir/" 2>/dev/null || {
        log_error "复制 SaltGUI 文件失败"
        cd - >/dev/null
        rm -rf "$temp_dir"
        return 1
    }
    
    # 设置权限
    sudo chown -R root:root "$install_dir"
    sudo chmod -R 755 "$install_dir"
    
    cd - >/dev/null
    rm -rf "$temp_dir"
    
    log_success "SaltGUI 安装完成"
    
    # 创建配置文件
    create_saltgui_config
    
    # 配置 SaltGUI API URL
    configure_saltgui_api_url
    
    # 创建 Nginx 配置
    create_saltgui_nginx_config
    
    # 创建 systemd 服务
    create_saltgui_service
    
    # 配置防火墙
    log_info "配置防火墙规则..."
    if command -v ufw >/dev/null 2>&1; then
        sudo ufw allow ${SALTGUI_PORT}/tcp
        log_success "UFW 规则已添加: 允许端口 ${SALTGUI_PORT}"
    fi
    
    if command -v firewall-cmd >/dev/null 2>&1; then
        sudo firewall-cmd --permanent --add-port=${SALTGUI_PORT}/tcp
        sudo firewall-cmd --reload
        log_success "Firewalld 规则已添加: 允许端口 ${SALTGUI_PORT}"
    fi
    
    log_success "SaltGUI 安装完成"
    log_info "访问地址: http://localhost:$SALTGUI_PORT"
    log_info "认证方式: PAM (系统用户认证)"
    log_info "用户名: saltgui"
    log_info "密码: saltgui123"
    log_info "认证类型: 选择 'pam'"
}

# 创建 SaltGUI 配置文件
create_saltgui_config() {
    log_info "创建 SaltGUI 配置文件..."
    
    # 确保配置目录存在
    sudo mkdir -p "$SALTGUI_CONFIG_DIR"
    
    cat > "/tmp/saltgui_config.json" << EOF
{
    "port": $SALTGUI_PORT,
    "host": "$SALTGUI_HOST",
    "salt": {
        "master": "localhost",
        "port": 4506,
        "auth": "pam"
    },
    "log": {
        "level": "info",
        "file": "$SALTGUI_LOG_DIR/saltgui.log"
    },
    "ui": {
        "theme": "dark",
        "language": "zh-CN"
    }
}
EOF
    
    # 移动配置文件到正确位置
    sudo mv "/tmp/saltgui_config.json" "$SALTGUI_CONFIG_DIR/config.json"
    
    log_success "SaltGUI 配置文件已创建"
}

# 配置 SaltGUI API URL
configure_saltgui_api_url() {
    log_info "配置 SaltGUI API URL..."
    
    # 更新 SaltGUI 的 config.js 文件，使用 /api 路径
    sudo tee /opt/saltgui/saltgui/static/scripts/config.js > /dev/null <<EOF
/* istanbul ignore file */
/* eslint-disable no-unused-vars */
const config = {
  // additional prefix for the API urls
  // with an empty string, the defaults will be used
  // See also https://docs.saltproject.io/en/latest/ref/netapi/all/salt.netapi.rest_cherrypy.html
  "API_URL": "/api",

  // additional prefix for the navigation urls
  // with an empty string, the defaults will be used
  "NAV_URL": ""
};
/* eslint-enable no-unused-vars */
EOF
    
    log_success "SaltGUI API URL 配置完成"
}

# 创建 SaltGUI Nginx 配置
create_saltgui_nginx_config() {
    log_info "创建 SaltGUI Nginx 配置..."
    
    # 检查 Nginx 是否安装
    if ! command -v nginx >/dev/null 2>&1 && ! [[ -f "/usr/local/nginx/sbin/nginx" ]]; then
        log_warning "Nginx 未安装，跳过 Nginx 配置"
        return 0
    fi
    
    # 确定 Nginx 配置目录
    local nginx_conf_dir="/usr/local/nginx/conf"
    if [[ ! -d "$nginx_conf_dir" ]]; then
        nginx_conf_dir="/etc/nginx"
    fi
    
    # 创建 SaltGUI Nginx 配置
    cat > "/tmp/saltgui_nginx.conf" << EOF
server {
    listen $SALTGUI_PORT;
    server_name localhost;
    root /opt/saltgui/saltgui;
    index index.html;

    # handle internal api (proxy)
    location /api/ {
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-NginX-Proxy true;
        proxy_pass http://localhost:8000/;
        proxy_ssl_session_reuse off;
        proxy_set_header Host \$http_host;
        proxy_redirect off;
    }

    # handle saltgui web page
    location / {
        try_files \$uri /index.html;
    }
}
EOF
    
    # 移动配置文件
    sudo mv "/tmp/saltgui_nginx.conf" "$nginx_conf_dir/sites-available/saltgui"
    
    # 创建 sites-enabled 目录（如果不存在）
    sudo mkdir -p "$nginx_conf_dir/sites-enabled"
    
    # 启用站点
    sudo ln -sf "$nginx_conf_dir/sites-available/saltgui" "$nginx_conf_dir/sites-enabled/"
    
    # 测试 Nginx 配置
    if command -v nginx >/dev/null 2>&1; then
        sudo nginx -t 2>/dev/null && {
            sudo systemctl reload nginx 2>/dev/null || sudo nginx -s reload 2>/dev/null
            log_success "SaltGUI Nginx 配置已创建并启用"
        } || {
            log_warning "Nginx 配置测试失败，请手动检查"
        }
    elif [[ -f "/usr/local/nginx/sbin/nginx" ]]; then
        sudo /usr/local/nginx/sbin/nginx -t 2>/dev/null && {
            sudo /usr/local/nginx/sbin/nginx -s reload 2>/dev/null
            log_success "SaltGUI Nginx 配置已创建并启用"
        } || {
            log_warning "Nginx 配置测试失败，请手动检查"
        }
    fi
}

# 创建 systemd 服务
create_saltgui_service() {
    log_info "创建 SaltGUI systemd 服务..."
    
    cat > "/etc/systemd/system/saltgui.service" << EOF
[Unit]
Description=SaltGUI Web Interface
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$SALTGUI_CONFIG_DIR
ExecStart=/usr/bin/python3 -m http.server $SALTGUI_PORT --directory /opt/saltgui/saltgui
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载 systemd
    sudo systemctl daemon-reload
    sudo systemctl enable saltgui
    
    log_success "SaltGUI systemd 服务已创建"
}

# 启动 SaltGUI
saltgui_start() {
    log_info "启动 SaltGUI..."
    
    if ! [[ -f "/opt/saltgui/saltgui/index.html" ]]; then
        log_error "SaltGUI 未安装，请先运行: saltgoat saltgui install"
        return 1
    fi
    
    sudo systemctl start saltgui
    
    if sudo systemctl is-active --quiet saltgui; then
        log_success "SaltGUI 启动成功"
        log_info "访问地址: http://localhost:$SALTGUI_PORT"
    else
        log_error "SaltGUI 启动失败"
        return 1
    fi
}

# 停止 SaltGUI
saltgui_stop() {
    log_info "停止 SaltGUI..."
    
    sudo systemctl stop saltgui
    
    if ! sudo systemctl is-active --quiet saltgui; then
        log_success "SaltGUI 已停止"
    else
        log_error "SaltGUI 停止失败"
        return 1
    fi
}

# 重启 SaltGUI
saltgui_restart() {
    log_info "重启 SaltGUI..."
    
    sudo systemctl restart saltgui
    
    if sudo systemctl is-active --quiet saltgui; then
        log_success "SaltGUI 重启成功"
        log_info "访问地址: http://localhost:$SALTGUI_PORT"
    else
        log_error "SaltGUI 重启失败"
        return 1
    fi
}

# 检查 SaltGUI 状态
saltgui_status() {
    log_info "检查 SaltGUI 状态..."
    
    if ! [[ -f "/opt/saltgui/saltgui/index.html" ]]; then
        log_warning "SaltGUI 未安装"
        return 1
    fi
    
    if sudo systemctl is-active --quiet saltgui; then
        log_success "SaltGUI 正在运行"
        log_info "访问地址: http://localhost:$SALTGUI_PORT"
        
        # 显示端口状态
        local port_status=$(sudo netstat -tlnp | grep ":$SALTGUI_PORT " || echo "端口未监听")
        log_info "端口状态: $port_status"
    else
        log_warning "SaltGUI 未运行"
    fi
    
    # 显示服务状态
    sudo systemctl status saltgui --no-pager -l
}

# 卸载 SaltGUI
saltgui_uninstall() {
    log_info "卸载 SaltGUI..."
    
    # 停止服务
    sudo systemctl stop saltgui 2>/dev/null || true
    sudo systemctl disable saltgui 2>/dev/null || true
    
    # 删除服务文件
    sudo rm -f /etc/systemd/system/saltgui.service
    sudo systemctl daemon-reload
    
    # 卸载 SaltGUI
    sudo rm -rf /opt/saltgui
    
    # 删除配置文件
    sudo rm -rf "$SALTGUI_CONFIG_DIR"
    sudo rm -rf "$SALTGUI_LOG_DIR"
    
    log_success "SaltGUI 卸载完成"
}

# 显示 SaltGUI 帮助
saltgui_help() {
    echo "SaltGUI 管理命令:"
    echo "  install    - 安装 SaltGUI"
    echo "  start      - 启动 SaltGUI"
    echo "  stop       - 停止 SaltGUI"
    echo "  restart    - 重启 SaltGUI"
    echo "  status     - 检查 SaltGUI 状态"
    echo "  uninstall  - 卸载 SaltGUI"
    echo "  help       - 显示此帮助信息"
    echo ""
    echo "访问地址: http://localhost:$SALTGUI_PORT"
    echo "配置文件: $SALTGUI_CONFIG_DIR/config.json"
    echo "日志文件: $SALTGUI_LOG_DIR/saltgui.log"
}

# SaltGUI 主处理函数
saltgui_handler() {
    case "$1" in
        install)
            saltgui_install
            ;;
        start)
            saltgui_start
            ;;
        stop)
            saltgui_stop
            ;;
        restart)
            saltgui_restart
            ;;
        status)
            saltgui_status
            ;;
        uninstall)
            saltgui_uninstall
            ;;
        help|--help|-h)
            saltgui_help
            ;;
        *)
            log_error "未知命令: $1"
            saltgui_help
            return 1
            ;;
    esac
}

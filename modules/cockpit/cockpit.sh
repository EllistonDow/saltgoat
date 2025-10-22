#!/bin/bash
# Cockpit 系统管理面板模块
# 提供现代化的 Web 系统管理界面

# 加载公共库
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${MODULE_DIR}/../../lib/logger.sh"
source "${MODULE_DIR}/../../lib/utils.sh"

# Cockpit 配置
COCKPIT_PORT="9091"
cockpit_install() {
    log_info "安装 Cockpit 系统管理面板..."
    
    # 更新包列表
    sudo apt update
    
    # 安装 Cockpit 及其插件
    log_info "安装 Cockpit 核心包..."
    sudo apt install -y cockpit
    
    log_info "安装 Cockpit 插件..."
    # 安装可用的插件
    local plugins=(
        "cockpit-system"
        "cockpit-networkmanager" 
        "cockpit-storaged"
        "cockpit-packagekit"
        "cockpit-machines"
    )
    
    for plugin in "${plugins[@]}"; do
        if apt-cache show "$plugin" >/dev/null 2>&1; then
            log_info "安装插件: $plugin"
            sudo apt install -y "$plugin"
        else
            log_warning "插件 $plugin 不可用，跳过安装"
        fi
    done
    
    # 启动并启用 Cockpit 服务
    sudo systemctl enable --now cockpit.socket
    
    # 配置 Cockpit 使用端口 9091
    sudo mkdir -p /etc/cockpit
    sudo tee /etc/cockpit/cockpit.conf >/dev/null << EOF
[WebService]
Port = $COCKPIT_PORT
EOF
    
    # 配置 systemd socket 使用端口 9091
    sudo mkdir -p /etc/systemd/system/cockpit.socket.d
    sudo tee /etc/systemd/system/cockpit.socket.d/override.conf >/dev/null << EOF
[Socket]
ListenStream=
ListenStream=$COCKPIT_PORT
EOF
    
    # 重新加载 systemd 配置
    sudo systemctl daemon-reload
    
    # 重启服务以应用新配置
    sudo systemctl restart cockpit.socket
    
    # 配置防火墙
    log_info "配置防火墙规则..."
    if command -v ufw >/dev/null 2>&1; then
        sudo ufw allow ${COCKPIT_PORT}/tcp
        log_success "UFW 规则已添加: 允许端口 ${COCKPIT_PORT}"
    fi
    
    if command -v firewall-cmd >/dev/null 2>&1; then
        sudo firewall-cmd --permanent --add-port=${COCKPIT_PORT}/tcp
        sudo firewall-cmd --reload
        log_success "Firewalld 规则已添加: 允许端口 ${COCKPIT_PORT}"
    fi
    
    # 检查服务状态
    if systemctl is-active --quiet cockpit.socket; then
        log_success "Cockpit 安装成功"
        log_info "访问地址: https://$(hostname -I | awk '{print $1}'):${COCKPIT_PORT}"
        log_info "默认使用系统用户登录"
        
        # 显示防火墙配置提示
        log_info "防火墙配置提示:"
        echo "sudo ufw allow ${COCKPIT_PORT}/tcp"
        echo "sudo firewall-cmd --permanent --add-port=${COCKPIT_PORT}/tcp && sudo firewall-cmd --reload"
    else
        log_error "Cockpit 服务启动失败"
        return 1
    fi
}

cockpit_uninstall() {
    log_info "卸载 Cockpit 系统管理面板..."
    
    # 停止服务
    sudo systemctl stop cockpit.socket
    sudo systemctl disable cockpit.socket
    
    # 卸载包
    sudo apt remove -y cockpit cockpit-*
    sudo apt autoremove -y
    
    log_success "Cockpit 卸载完成"
}

cockpit_status() {
    log_info "Cockpit 服务状态:"
    
    if systemctl is-active --quiet cockpit.socket; then
        echo "Cockpit: active"
        echo "访问地址: https://$(hostname -I | awk '{print $1}'):${COCKPIT_PORT}"
        echo "服务状态: $(systemctl is-active cockpit.socket)"
    else
        echo "Cockpit: inactive"
    fi
    
    # 显示已安装的插件
    log_info "已安装的 Cockpit 插件:"
    dpkg -l | grep cockpit | awk '{print $2}' | sed 's/^/  - /'
}

cockpit_config() {
    local action="${1:-show}"
    
    case "$action" in
        "show")
            log_info "Cockpit 配置信息:"
            echo "配置文件: /etc/cockpit/cockpit.conf"
            echo "日志文件: /var/log/cockpit.log"
            echo "服务端口: $COCKPIT_PORT"
            echo "访问协议: HTTPS"
            
            if [[ -f "/etc/cockpit/cockpit.conf" ]]; then
                echo ""
                echo "当前配置:"
                cat /etc/cockpit/cockpit.conf
            fi
            ;;
        "firewall")
            log_info "配置 Cockpit 防火墙规则..."
            
            # UFW 配置
            if command -v ufw >/dev/null 2>&1; then
                sudo ufw allow ${COCKPIT_PORT}/tcp
                log_success "UFW 规则已添加: 允许端口 ${COCKPIT_PORT}"
            fi
            
            # Firewalld 配置
            if command -v firewall-cmd >/dev/null 2>&1; then
                sudo firewall-cmd --permanent --add-port=${COCKPIT_PORT}/tcp
                sudo firewall-cmd --reload
                log_success "Firewalld 规则已添加: 允许端口 ${COCKPIT_PORT}"
            fi
            ;;
        "ssl")
            log_info "配置 Cockpit SSL 证书..."
            
            # 检查是否有自定义证书
            if [[ -f "/etc/cockpit/ws-certs.d/50-cockpit.cert" ]]; then
                log_info "发现自定义 SSL 证书"
                openssl x509 -in /etc/cockpit/ws-certs.d/50-cockpit.cert -text -noout | head -20
            else
                log_info "使用默认自签名证书"
                log_info "要使用自定义证书，请将证书文件放置在:"
                echo "  /etc/cockpit/ws-certs.d/50-cockpit.cert"
                echo "  /etc/cockpit/ws-certs.d/50-cockpit.key"
            fi
            ;;
        *)
            log_error "未知的配置操作: $action"
            log_info "可用操作: show, firewall, ssl"
            return 1
            ;;
    esac
}

cockpit_logs() {
    local lines="${1:-50}"
    
    log_info "显示 Cockpit 日志 (最近 $lines 行):"
    
    if [[ -f "/var/log/cockpit.log" ]]; then
        tail -n "$lines" /var/log/cockpit.log
    else
        log_warning "Cockpit 日志文件不存在"
        log_info "尝试查看 systemd 日志:"
        journalctl -u cockpit.socket -n "$lines" --no-pager
    fi
}

cockpit_restart() {
    log_info "重启 Cockpit 服务..."
    
    sudo systemctl restart cockpit.socket
    
    if systemctl is-active --quiet cockpit.socket; then
        log_success "Cockpit 服务重启成功"
    else
        log_error "Cockpit 服务重启失败"
        return 1
    fi
}

# 主函数
cockpit_main() {
    local action="${1:-help}"
    
    case "$action" in
        "install")
            cockpit_install
            ;;
        "uninstall")
            cockpit_uninstall
            ;;
        "status")
            cockpit_status
            ;;
        "config")
            cockpit_config "${2:-show}"
            ;;
        "logs")
            cockpit_logs "${2:-50}"
            ;;
        "restart")
            cockpit_restart
            ;;
        "help"|*)
            log_info "Cockpit 系统管理面板命令:"
            echo ""
            echo "  install     - 安装 Cockpit 及其插件"
            echo "  uninstall   - 卸载 Cockpit"
            echo "  status      - 查看服务状态和访问信息"
            echo "  config      - 配置管理 (show|firewall|ssl)"
            echo "  logs        - 查看日志 (可选行数，默认50)"
            echo "  restart     - 重启服务"
            echo ""
            echo "示例:"
            echo "  saltgoat cockpit install"
            echo "  saltgoat cockpit status"
            echo "  saltgoat cockpit config firewall"
            echo "  saltgoat cockpit logs 100"
            ;;
    esac
}

# 如果直接执行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cockpit_main "$@"
fi

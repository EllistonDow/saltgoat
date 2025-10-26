#!/bin/bash
# Uptime Kuma 监控面板模块
# 提供现代化的服务监控和状态页面

# 加载公共库
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/logger.sh
# shellcheck disable=SC1091
source "${MODULE_DIR}/../../lib/logger.sh"
# shellcheck source=../../lib/utils.sh
# shellcheck disable=SC1091
source "${MODULE_DIR}/../../lib/utils.sh"

# Uptime Kuma 配置
KUMA_DIR="/opt/uptime-kuma"
KUMA_USER="uptime-kuma"
KUMA_PORT="3001"
KUMA_DATA_DIR="/opt/uptime-kuma/data"

# Uptime Kuma 管理函数
uptime_kuma_install() {
    log_info "安装 Uptime Kuma 监控面板..."
    
    # 检查 Node.js
    if ! command -v node >/dev/null 2>&1; then
        log_info "安装 Node.js (使用系统软件仓库)..."
        sudo apt-get update
        sudo apt-get install -y nodejs npm
    fi
    
    if ! command -v node >/dev/null 2>&1; then
        log_error "Node.js 安装失败，请手动安装 18+ 版本"
        return 1
    fi

    if ! command -v npm >/dev/null 2>&1; then
        log_info "安装 npm..."
        sudo apt-get install -y npm
    fi

    # 检查 Node.js 版本
    local node_version
    node_version=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [[ $node_version -lt 18 ]]; then
        log_error "Node.js 版本过低，需要 18+ 版本"
        return 1
    fi
    
    # 创建用户
    if ! id "$KUMA_USER" >/dev/null 2>&1; then
        sudo useradd -r -s /bin/false -d "$KUMA_DIR" "$KUMA_USER"
        log_success "创建用户: $KUMA_USER"
    fi
    
    # 创建目录
    sudo mkdir -p "$KUMA_DIR" "$KUMA_DATA_DIR"
    
    # 下载 Uptime Kuma
    log_info "下载 Uptime Kuma..."
    if sudo git clone https://github.com/louislam/uptime-kuma.git "$KUMA_DIR"; then
        log_success "Uptime Kuma 下载成功"
    else
        log_error "Uptime Kuma 下载失败"
        return 1
    fi
    
    # 安装依赖
    log_info "安装依赖包..."
    if ! cd "$KUMA_DIR"; then
        log_error "无法进入目录 $KUMA_DIR"
        return 1
    fi
    if sudo npm ci --production; then
        log_success "依赖安装成功"
    else
        log_error "依赖安装失败"
        return 1
    fi
    
    # 设置权限
    sudo chown -R "$KUMA_USER:$KUMA_USER" "$KUMA_DIR" "$KUMA_DATA_DIR"
    
    # 创建 systemd 服务
    uptime_kuma_create_service
    
    # 启动服务
    sudo systemctl enable uptime-kuma
    sudo systemctl start uptime-kuma
    
    # 配置防火墙
    log_info "配置防火墙规则..."
    if command -v ufw >/dev/null 2>&1; then
        sudo ufw allow "${KUMA_PORT}"/tcp
        log_success "UFW 规则已添加: 允许端口 ${KUMA_PORT}"
    fi
    
    if command -v firewall-cmd >/dev/null 2>&1; then
        sudo firewall-cmd --permanent --add-port="${KUMA_PORT}"/tcp
        sudo firewall-cmd --reload
        log_success "Firewalld 规则已添加: 允许端口 ${KUMA_PORT}"
    fi
    
    # 等待服务启动
    sleep 5
    
    if systemctl is-active --quiet uptime-kuma; then
        log_success "Uptime Kuma 安装完成"
        log_info "访问地址: http://$(hostname -I | awk '{print $1}'):${KUMA_PORT}"
        log_info "默认管理员账户: admin / admin"
        log_warning "请立即修改默认密码！"
    else
        log_error "Uptime Kuma 服务启动失败"
        return 1
    fi
}

uptime_kuma_create_service() {
    log_info "创建 Uptime Kuma systemd 服务..."
    
    sudo tee /etc/systemd/system/uptime-kuma.service >/dev/null << EOF
[Unit]
Description=Uptime Kuma
After=network.target

[Service]
Type=simple
User=$KUMA_USER
WorkingDirectory=$KUMA_DIR
ExecStart=/usr/bin/node server/server.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=UPTIME_KUMA_PORT=$KUMA_PORT
Environment=UPTIME_KUMA_DATA_DIR=$KUMA_DATA_DIR

# 安全设置
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$KUMA_DATA_DIR

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    log_success "systemd 服务创建完成"
}

uptime_kuma_uninstall() {
    log_info "卸载 Uptime Kuma 监控面板..."
    
    # 停止服务
    sudo systemctl stop uptime-kuma
    sudo systemctl disable uptime-kuma
    
    # 删除服务文件
    sudo rm -f /etc/systemd/system/uptime-kuma.service
    sudo systemctl daemon-reload
    
    # 删除文件
    sudo rm -rf "$KUMA_DIR" "$KUMA_DATA_DIR"
    
    # 删除用户
    sudo userdel "$KUMA_USER" 2>/dev/null || true
    
    log_success "Uptime Kuma 卸载完成"
}

uptime_kuma_status() {
    log_info "Uptime Kuma 状态检查:"
    
    # 检查服务状态
    if systemctl is-active --quiet uptime-kuma; then
        echo "服务状态: active"
        echo "端口: $KUMA_PORT"
        echo "数据目录: $KUMA_DATA_DIR"
        echo "用户: $KUMA_USER"
    else
        echo "服务状态: inactive"
    fi
    
    # 检查端口
    if netstat -tlnp 2>/dev/null | grep -q ":$KUMA_PORT "; then
        echo "端口状态: 监听中"
    else
        echo "端口状态: 未监听"
    fi
    
    # 检查文件
    if [[ -d "$KUMA_DIR" ]]; then
        echo "安装目录: 存在"
        echo "版本: $(cd "$KUMA_DIR" && git describe --tags 2>/dev/null || echo 'unknown')"
    else
        echo "安装目录: 不存在"
    fi
    
    echo "访问地址: http://$(hostname -I | awk '{print $1}'):${KUMA_PORT}"
}

uptime_kuma_config() {
    local action="${1:-show}"
    
    case "$action" in
        "show")
            log_info "Uptime Kuma 配置信息:"
            echo "安装目录: $KUMA_DIR"
            echo "数据目录: $KUMA_DATA_DIR"
            echo "运行用户: $KUMA_USER"
            echo "服务端口: $KUMA_PORT"
            echo "服务文件: /etc/systemd/system/uptime-kuma.service"
            
            if [[ -f "/etc/systemd/system/uptime-kuma.service" ]]; then
                echo ""
                echo "服务配置:"
                cat /etc/systemd/system/uptime-kuma.service
            fi
            ;;
        "port")
            local new_port="${2:-3001}"
            uptime_kuma_change_port "$new_port"
            ;;
        "update")
            uptime_kuma_update
            ;;
        "backup")
            uptime_kuma_backup
            ;;
        "restore")
            local backup_file="${2}"
            uptime_kuma_restore "$backup_file"
            ;;
        *)
            log_error "未知的配置操作: $action"
            log_info "可用操作: show, port, update, backup, restore"
            return 1
            ;;
    esac
}

uptime_kuma_change_port() {
    local new_port="${1:-3001}"
    
    log_info "更改 Uptime Kuma 端口为: $new_port"
    
    # 停止服务
    sudo systemctl stop uptime-kuma
    
    # 更新服务文件
    sudo sed -i "s/UPTIME_KUMA_PORT=$KUMA_PORT/UPTIME_KUMA_PORT=$new_port/g" /etc/systemd/system/uptime-kuma.service
    
    # 更新端口变量
    KUMA_PORT="$new_port"
    
    # 重新加载服务
    sudo systemctl daemon-reload
    sudo systemctl start uptime-kuma
    
    if systemctl is-active --quiet uptime-kuma; then
        log_success "端口更改成功"
        log_info "新访问地址: http://$(hostname -I | awk '{print $1}'):${KUMA_PORT}"
    else
        log_error "端口更改失败"
        return 1
    fi
}

uptime_kuma_update() {
    log_info "更新 Uptime Kuma..."
    
    # 停止服务
    sudo systemctl stop uptime-kuma
    
    # 备份数据
    uptime_kuma_backup
    
    # 更新代码
    if ! cd "$KUMA_DIR"; then
        log_error "无法进入目录 $KUMA_DIR"
        return 1
    fi
    if ! sudo -u "$KUMA_USER" git pull origin master >/dev/null 2>&1; then
        log_error "拉取最新代码失败"
        return 1
    fi
    
    # 更新依赖
    if ! sudo -u "$KUMA_USER" npm ci --production >/dev/null 2>&1; then
        log_error "依赖更新失败"
        return 1
    fi
    
    # 启动服务
    sudo systemctl start uptime-kuma
    
    if systemctl is-active --quiet uptime-kuma; then
        log_success "Uptime Kuma 更新完成"
    else
        log_error "Uptime Kuma 更新失败"
        return 1
    fi
}

uptime_kuma_backup() {
    log_info "备份 Uptime Kuma 数据..."
    
    local backup_dir="/opt/saltgoat/backups/uptime-kuma"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    
    sudo mkdir -p "$backup_dir"
    
    # 备份数据目录
    if [[ -d "$KUMA_DATA_DIR" ]]; then
        sudo tar -czf "${backup_dir}/uptime-kuma-data_${timestamp}.tar.gz" -C "$(dirname "$KUMA_DATA_DIR")" "$(basename "$KUMA_DATA_DIR")"
        log_success "数据备份完成: ${backup_dir}/uptime-kuma-data_${timestamp}.tar.gz"
    fi
    
    # 备份配置文件
    if [[ -f "/etc/systemd/system/uptime-kuma.service" ]]; then
        sudo cp "/etc/systemd/system/uptime-kuma.service" "${backup_dir}/uptime-kuma-service_${timestamp}.service"
        log_success "服务配置备份完成: ${backup_dir}/uptime-kuma-service_${timestamp}.service"
    fi
}

uptime_kuma_restore() {
    local backup_file="${1}"
    
    if [[ -z "$backup_file" ]]; then
        log_error "请指定备份文件"
        return 1
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "备份文件不存在: $backup_file"
        return 1
    fi
    
    log_info "恢复 Uptime Kuma 数据: $backup_file"
    
    # 停止服务
    sudo systemctl stop uptime-kuma
    
    # 备份当前数据
    uptime_kuma_backup
    
    # 恢复数据
    sudo rm -rf "$KUMA_DATA_DIR"
    sudo tar -xzf "$backup_file" -C "$(dirname "$KUMA_DATA_DIR")"
    sudo chown -R "$KUMA_USER:$KUMA_USER" "$KUMA_DATA_DIR"
    
    # 启动服务
    sudo systemctl start uptime-kuma
    
    if systemctl is-active --quiet uptime-kuma; then
        log_success "数据恢复完成"
    else
        log_error "数据恢复失败"
        return 1
    fi
}

uptime_kuma_logs() {
    local lines="${1:-50}"
    
    log_info "显示 Uptime Kuma 日志 (最近 $lines 行):"
    
    # 显示 systemd 日志
    journalctl -u uptime-kuma -n "$lines" --no-pager
    
    # 显示应用日志（如果存在）
    if [[ -f "$KUMA_DATA_DIR/logs/app.log" ]]; then
        echo ""
        log_info "应用日志:"
        tail -n "$lines" "$KUMA_DATA_DIR/logs/app.log"
    fi
}

uptime_kuma_restart() {
    log_info "重启 Uptime Kuma 服务..."
    
    sudo systemctl restart uptime-kuma
    
    if systemctl is-active --quiet uptime-kuma; then
        log_success "Uptime Kuma 服务重启成功"
    else
        log_error "Uptime Kuma 服务重启失败"
        return 1
    fi
}

uptime_kuma_monitor() {
    log_info "配置 SaltGoat 服务监控..."
    
    # 创建监控配置
    local monitor_config="/opt/saltgoat/monitoring/uptime-kuma.conf"
    
    sudo tee "$monitor_config" >/dev/null << EOF
# Uptime Kuma 监控配置
[uptime-kuma]
name=Uptime Kuma
url=http://localhost:$KUMA_PORT
port=$KUMA_PORT
service=uptime-kuma
check_interval=60
alert_threshold=3
EOF
    
    log_success "监控配置创建完成: $monitor_config"
    log_info "Uptime Kuma 将监控以下 SaltGoat 服务:"
    echo "  - Nginx"
    echo "  - MySQL"
    echo "  - PHP-FPM"
    echo "  - Valkey"
    echo "  - OpenSearch"
    echo "  - RabbitMQ"
}

# 主函数
uptime_kuma_main() {
    local action="${1:-help}"
    
    case "$action" in
        "install")
            uptime_kuma_install
            ;;
        "uninstall")
            uptime_kuma_uninstall
            ;;
        "status")
            uptime_kuma_status
            ;;
        "config")
            uptime_kuma_config "${2:-show}"
            ;;
        "logs")
            uptime_kuma_logs "${2:-50}"
            ;;
        "restart")
            uptime_kuma_restart
            ;;
        "monitor")
            uptime_kuma_monitor
            ;;
        "help"|*)
            log_info "Uptime Kuma 监控面板命令:"
            echo ""
            echo "  install     - 安装 Uptime Kuma"
            echo "  uninstall   - 卸载 Uptime Kuma"
            echo "  status      - 查看服务状态"
            echo "  config      - 配置管理 (show|port|update|backup|restore)"
            echo "  logs        - 查看日志 (可选行数，默认50)"
            echo "  restart     - 重启服务"
            echo "  monitor     - 配置 SaltGoat 服务监控"
            echo ""
            echo "示例:"
            echo "  saltgoat uptime-kuma install"
            echo "  saltgoat uptime-kuma status"
            echo "  saltgoat uptime-kuma config port 3002"
            echo "  saltgoat uptime-kuma config update"
            echo "  saltgoat uptime-kuma logs 100"
            echo "  saltgoat uptime-kuma monitor"
            ;;
    esac
}

# 如果直接执行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    uptime_kuma_main "$@"
fi

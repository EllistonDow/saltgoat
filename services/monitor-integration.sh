#!/bin/bash
# 监控集成模块 - Prometheus & Grafana
# services/monitor-integration.sh

# Prometheus集成设置
monitor_prometheus_setup() {
    echo "Prometheus 监控集成"
    echo "=========================================="
    
    # 检查是否已安装
    if systemctl is-active --quiet prometheus 2>/dev/null; then
        log_info "Prometheus 已安装并运行"
        show_prometheus_status
        return 0
    fi
    
    log_info "开始安装 Prometheus..."
    
    # 创建Prometheus用户
    if ! id prometheus >/dev/null 2>&1; then
        sudo useradd --no-create-home --shell /bin/false prometheus
        log_success "创建 Prometheus 用户"
    fi
    
    # 创建目录
    sudo mkdir -p /etc/prometheus
    sudo mkdir -p /var/lib/prometheus
    sudo chown prometheus:prometheus /etc/prometheus
    sudo chown prometheus:prometheus /var/lib/prometheus
    
    # 下载Prometheus
    local prometheus_version="2.45.0"
    local prometheus_url="https://github.com/prometheus/prometheus/releases/download/v${prometheus_version}/prometheus-${prometheus_version}.linux-amd64.tar.gz"
    
    log_info "下载 Prometheus v${prometheus_version}..."
    cd /tmp
    wget -q "$prometheus_url" -O prometheus.tar.gz
    
    if [[ $? -ne 0 ]]; then
        log_error "下载 Prometheus 失败"
        exit 1
    fi
    
    # 解压和安装
    tar xzf prometheus.tar.gz
    sudo cp prometheus-${prometheus_version}.linux-amd64/prometheus /usr/local/bin/
    sudo cp prometheus-${prometheus_version}.linux-amd64/promtool /usr/local/bin/
    sudo chown prometheus:prometheus /usr/local/bin/prometheus
    sudo chown prometheus:prometheus /usr/local/bin/promtool
    
    # 创建配置文件
    create_prometheus_config
    
    # 创建systemd服务
    create_prometheus_service
    
    # 启动服务
    sudo systemctl daemon-reload
    sudo systemctl enable prometheus
    sudo systemctl start prometheus
    
    # 放行Prometheus端口
    configure_firewall_port "9090" "Prometheus"
    
    if systemctl is-active --quiet prometheus; then
        log_success "Prometheus 安装成功"
        local server_ip=$(ip route get 1.1.1.1 | awk '{print $7}' | head -1)
        log_info "访问地址: http://${server_ip}:9090"
        show_prometheus_status
        
        # 自动安装Node Exporter
        log_info "自动安装 Node Exporter..."
        install_node_exporter
        
        # 自动安装Nginx Exporter
        log_info "自动安装 Nginx Exporter..."
        install_nginx_exporter
    else
        log_error "Prometheus 启动失败"
        sudo systemctl status prometheus
        exit 1
    fi
    
    # 清理临时文件
    rm -rf /tmp/prometheus*
}

# 创建Prometheus配置
create_prometheus_config() {
    log_info "创建 Prometheus 配置文件..."
    
    sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'nginx'
    static_configs:
      - targets: ['localhost:9113']

  - job_name: 'mysql'
    static_configs:
      - targets: ['localhost:9104']

  - job_name: 'valkey'
    static_configs:
      - targets: ['localhost:9121']
EOF
    
    sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
    log_success "Prometheus 配置文件创建完成"
}

# 创建Prometheus服务
create_prometheus_service() {
    log_info "创建 Prometheus 系统服务..."
    
    sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \\
    --config.file /etc/prometheus/prometheus.yml \\
    --storage.tsdb.path /var/lib/prometheus/ \\
    --web.console.templates=/etc/prometheus/consoles \\
    --web.console.libraries=/etc/prometheus/console_libraries \\
    --web.listen-address=0.0.0.0:9090 \\
    --web.enable-lifecycle

[Install]
WantedBy=multi-user.target
EOF
    
    log_success "Prometheus 系统服务创建完成"
}

# 显示Prometheus状态
show_prometheus_status() {
    local server_ip=$(ip route get 1.1.1.1 | awk '{print $7}' | head -1)
    echo ""
    echo "Prometheus 状态信息:"
    echo "----------------------------------------"
    echo "服务状态: $(systemctl is-active prometheus)"
    echo "访问地址: http://${server_ip}:9090"
    echo "配置文件: /etc/prometheus/prometheus.yml"
    echo "数据目录: /var/lib/prometheus/"
    echo ""
    
    # 检查端口
    if ss -tlnp 2>/dev/null | grep -q ":9090 "; then
        echo "端口状态: ✅ 9090端口已监听"
    else
        echo "端口状态: ❌ 9090端口未监听"
    fi
    
    # 检查目标
    echo ""
    echo "监控目标:"
    echo "  - Prometheus自身 (localhost:9090)"
    echo "  - Node Exporter (localhost:9100) - 需要单独安装"
    echo "  - Nginx Exporter (localhost:9113) - 需要单独安装"
    echo "  - MySQL Exporter (localhost:9104) - 需要单独安装"
    echo "  - Valkey Exporter (localhost:9121) - 需要单独安装"
}

# Grafana集成设置
monitor_grafana_setup() {
    echo "Grafana 监控集成"
    echo "=========================================="
    
    # 检查是否已安装
    if systemctl is-active --quiet grafana-server 2>/dev/null; then
        log_info "Grafana 已安装并运行"
        show_grafana_status
        return 0
    fi
    
    log_info "开始安装 Grafana..."
    
    # 添加Grafana仓库
    if ! dpkg -l | grep -q grafana; then
        log_info "添加 Grafana 官方仓库..."
        wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
        echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
        
        sudo apt update
    fi
    
    # 安装Grafana
    log_info "安装 Grafana..."
    sudo apt install -y grafana
    
    if [[ $? -ne 0 ]]; then
        log_error "Grafana 安装失败"
        exit 1
    fi
    
    # 启动服务
    sudo systemctl enable grafana-server
    sudo systemctl start grafana-server
    
    # 放行Grafana端口
    configure_firewall_port "3000" "Grafana"
    
    if systemctl is-active --quiet grafana-server; then
        log_success "Grafana 安装成功"
        local server_ip=$(ip route get 1.1.1.1 | awk '{print $7}' | head -1)
        log_info "访问地址: http://${server_ip}:3000"
        log_info "默认用户名: admin"
        log_info "默认密码: admin"
        show_grafana_status
    else
        log_error "Grafana 启动失败"
        sudo systemctl status grafana-server
        exit 1
    fi
}

# 显示Grafana状态
show_grafana_status() {
    local server_ip=$(ip route get 1.1.1.1 | awk '{print $7}' | head -1)
    echo ""
    echo "Grafana 状态信息:"
    echo "----------------------------------------"
    echo "服务状态: $(systemctl is-active grafana-server)"
    echo "访问地址: http://${server_ip}:3000"
    echo "配置文件: /etc/grafana/grafana.ini"
    echo "数据目录: /var/lib/grafana/"
    echo ""
    
    # 检查端口
    if ss -tlnp 2>/dev/null | grep -q ":3000 "; then
        echo "端口状态: ✅ 3000端口已监听"
    else
        echo "端口状态: ❌ 3000端口未监听"
    fi
    
    echo ""
    echo "下一步操作:"
    echo "  1. 访问 http://${server_ip}:3000"
    echo "  2. 使用 admin/admin 登录"
    echo "  3. 添加 Prometheus 数据源"
    echo "  4. 导入仪表板模板"
    echo ""
    
    echo "推荐仪表板:"
    echo "  - Node Exporter: 1860"
    echo "  - Nginx: 12559"
    echo "  - MySQL: 7362"
    echo "  - Valkey: 11835"
}

# 安装Node Exporter
install_node_exporter() {
    log_info "安装 Node Exporter..."
    
    local node_exporter_version="1.6.1"
    local node_exporter_url="https://github.com/prometheus/node_exporter/releases/download/v${node_exporter_version}/node_exporter-${node_exporter_version}.linux-amd64.tar.gz"
    
    cd /tmp
    wget -q "$node_exporter_url" -O node_exporter.tar.gz
    tar xzf node_exporter.tar.gz
    
    sudo cp node_exporter-${node_exporter_version}.linux-amd64/node_exporter /usr/local/bin/
    sudo chown prometheus:prometheus /usr/local/bin/node_exporter
    
    # 创建服务
    sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable node_exporter
    sudo systemctl start node_exporter
    
    # 放行Node Exporter端口
    configure_firewall_port "9100" "Node Exporter"
    
    if systemctl is-active --quiet node_exporter; then
        log_success "Node Exporter 安装成功"
        local server_ip=$(ip route get 1.1.1.1 | awk '{print $7}' | head -1)
        log_info "访问地址: http://${server_ip}:9100/metrics"
    else
        log_error "Node Exporter 启动失败"
    fi
    
    rm -rf /tmp/node_exporter*
}

# 安装Nginx Exporter
install_nginx_exporter() {
    log_info "安装 Nginx Exporter..."
    
    # 检查Nginx是否安装
    if ! command -v nginx >/dev/null 2>&1; then
        log_info "Nginx 未安装，跳过 Nginx Exporter 安装"
        return 0
    fi
    
    local nginx_exporter_version="0.11.0"
    local nginx_exporter_url="https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v${nginx_exporter_version}/nginx-prometheus-exporter_${nginx_exporter_version}_linux_amd64.tar.gz"
    
    cd /tmp
    wget -q "$nginx_exporter_url" -O nginx_exporter.tar.gz
    
    if [[ $? -ne 0 ]]; then
        log_error "下载 Nginx Exporter 失败"
        return 1
    fi
    
    tar xzf nginx_exporter.tar.gz
    sudo cp nginx-prometheus-exporter /usr/local/bin/nginx_exporter
    sudo chown prometheus:prometheus /usr/local/bin/nginx_exporter
    
    # 创建服务
    sudo tee /etc/systemd/system/nginx_exporter.service > /dev/null <<EOF
[Unit]
Description=Nginx Prometheus Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/nginx_exporter -nginx.scrape-uri=http://localhost/nginx_status

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable nginx_exporter
    sudo systemctl start nginx_exporter
    
    # 放行Nginx Exporter端口
    configure_firewall_port "9113" "Nginx Exporter"
    
    if systemctl is-active --quiet nginx_exporter; then
        log_success "Nginx Exporter 安装成功"
        local server_ip=$(ip route get 1.1.1.1 | awk '{print $7}' | head -1)
        log_info "访问地址: http://${server_ip}:9113/metrics"
    else
        log_error "Nginx Exporter 启动失败"
    fi
    
    rm -rf /tmp/nginx-prometheus-exporter*
}

# 防火墙管理函数
configure_firewall_port() {
    local port="$1"
    local service_name="$2"
    
    log_info "配置防火墙规则: ${service_name} (${port})..."
    if command -v ufw >/dev/null 2>&1; then
        sudo ufw allow ${port}/tcp comment "${service_name}"
        log_success "UFW: 已放行${port}端口"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        sudo firewall-cmd --permanent --add-port=${port}/tcp
        sudo firewall-cmd --reload
        log_success "Firewalld: 已放行${port}端口"
    elif command -v iptables >/dev/null 2>&1; then
        sudo iptables -A INPUT -p tcp --dport ${port} -j ACCEPT
        log_success "iptables: 已放行${port}端口"
    else
        log_info "未检测到防火墙，请手动放行${port}端口"
    fi
}

# 检查防火墙状态
check_firewall_status() {
    local port="$1"
    local service_name="$2"
    
    echo "防火墙状态 (${service_name}):"
    if command -v ufw >/dev/null 2>&1; then
        if sudo ufw status | grep -q "${port}"; then
            echo "  UFW: ✅ ${port}端口已放行"
        else
            echo "  UFW: ❌ ${port}端口未放行"
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if sudo firewall-cmd --list-ports | grep -q "${port}"; then
            echo "  Firewalld: ✅ ${port}端口已放行"
        else
            echo "  Firewalld: ❌ ${port}端口未放行"
        fi
    elif command -v iptables >/dev/null 2>&1; then
        if sudo iptables -L INPUT | grep -q "dpt:${port}"; then
            echo "  iptables: ✅ ${port}端口已放行"
        else
            echo "  iptables: ❌ ${port}端口未放行"
        fi
    else
        echo "  防火墙: ❌ 未检测到防火墙"
    fi
}

# 监控集成状态检查
monitor_integration_status() {
    local server_ip=$(ip route get 1.1.1.1 | awk '{print $7}' | head -1)
    echo "监控集成状态检查"
    echo "=========================================="
    
    echo "Prometheus:"
    if systemctl is-active --quiet prometheus 2>/dev/null; then
        echo "  服务状态: ✅ 运行中"
        echo "  端口状态: $(ss -tlnp 2>/dev/null | grep ":9090 " | awk '{print $4}' || echo '未监听')"
        check_firewall_status "9090" "Prometheus"
    else
        echo "  服务状态: ❌ 未运行"
    fi
    
    echo ""
    echo "Grafana:"
    if systemctl is-active --quiet grafana-server 2>/dev/null; then
        echo "  服务状态: ✅ 运行中"
        echo "  端口状态: $(ss -tlnp 2>/dev/null | grep ":3000 " | awk '{print $4}' || echo '未监听')"
        check_firewall_status "3000" "Grafana"
    else
        echo "  服务状态: ❌ 未运行"
    fi
    
    echo ""
    echo "Node Exporter:"
    if systemctl is-active --quiet node_exporter 2>/dev/null; then
        echo "  服务状态: ✅ 运行中"
        echo "  端口状态: $(ss -tlnp 2>/dev/null | grep ":9100 " | awk '{print $4}' || echo '未监听')"
        check_firewall_status "9100" "Node Exporter"
    else
        echo "  服务状态: ❌ 未运行"
    fi
    
    echo ""
    echo "访问地址:"
    echo "  Prometheus: http://${server_ip}:9090"
    echo "  Grafana: http://${server_ip}:3000"
    echo "  Node Exporter: http://${server_ip}:9100/metrics"
}

# 测试防火墙配置
test_firewall_config() {
    echo "测试防火墙配置功能"
    echo "=========================================="
    
    echo "配置Prometheus端口 (9090):"
    configure_firewall_port "9090" "Prometheus"
    
    echo ""
    echo "配置Grafana端口 (3000):"
    configure_firewall_port "3000" "Grafana"
    
    echo ""
    echo "配置Node Exporter端口 (9100):"
    configure_firewall_port "9100" "Node Exporter"
    
    echo ""
    echo "防火墙状态检查:"
    check_firewall_status "9090" "Prometheus"
    check_firewall_status "3000" "Grafana"
    check_firewall_status "9100" "Node Exporter"
}

# 模拟新安装测试
simulate_fresh_install() {
    echo "模拟新安装测试 - 防火墙配置"
    echo "=========================================="
    
    echo "当前防火墙状态:"
    sudo ufw status | grep -E "(9090|3000|9100)" || echo "  没有相关端口规则"
    
    echo ""
    echo "模拟安装Prometheus并配置防火墙:"
    configure_firewall_port "9090" "Prometheus"
    
    echo ""
    echo "模拟安装Grafana并配置防火墙:"
    configure_firewall_port "3000" "Grafana"
    
    echo ""
    echo "模拟安装Node Exporter并配置防火墙:"
    configure_firewall_port "9100" "Node Exporter"
    
    echo ""
    echo "安装后的防火墙状态:"
    sudo ufw status | grep -E "(9090|3000|9100)"
    
    echo ""
    echo "防火墙状态检查:"
    check_firewall_status "9090" "Prometheus"
    check_firewall_status "3000" "Grafana"
    check_firewall_status "9100" "Node Exporter"
}

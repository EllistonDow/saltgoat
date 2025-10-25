#!/bin/bash
# 分级监控配置模块
# services/monitoring-levels.sh

# 检测系统资源并确定监控级别
detect_monitoring_level() {
    local total_memory_gb
    total_memory_gb=$(free -m | awk 'NR==2{print int($2/1024)}')
    local cpu_cores
    cpu_cores=$(nproc)
    
    echo "系统资源检测:"
    echo "  内存: ${total_memory_gb}GB"
    echo "  CPU核心: ${cpu_cores}个"
    
    if [[ $total_memory_gb -ge 32 && $cpu_cores -ge 8 ]]; then
        echo "high"
    elif [[ $total_memory_gb -ge 16 && $cpu_cores -ge 4 ]]; then
        echo "medium"
    else
        echo "low"
    fi
}

# 低级别监控配置
configure_prometheus_low() {
    echo "配置低级别监控 (Low Level)"
    echo "=========================================="
    
    # 创建简化的Prometheus配置
    sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 30s
  evaluation_interval: 30s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']
    scrape_interval: 30s
    metrics_path: /metrics

  - job_name: 'nginx'
    static_configs:
      - targets: ['localhost:9113']
    scrape_interval: 60s

rule_files:
  - "low_level_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: []
EOF

    # 创建低级别告警规则
    sudo tee /etc/prometheus/low_level_rules.yml > /dev/null <<EOF
groups:
- name: low_level_alerts
  rules:
  - alert: HighCPUUsage
    expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High CPU usage detected"
      description: "CPU usage is above 80% for more than 5 minutes"

  - alert: HighMemoryUsage
    expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High memory usage detected"
      description: "Memory usage is above 85% for more than 5 minutes"

  - alert: DiskSpaceLow
    expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 10
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "Low disk space"
      description: "Disk space is below 10%"
EOF

    sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
    sudo chown prometheus:prometheus /etc/prometheus/low_level_rules.yml
    
    log_success "低级别监控配置完成"
    log_info "监控间隔: 30秒"
    log_info "告警规则: 基础系统告警"
}

# 中级别监控配置
configure_prometheus_medium() {
    echo "配置中级别监控 (Medium Level)"
    echo "=========================================="
    
    # 创建中等Prometheus配置
    sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']
    scrape_interval: 15s
    metrics_path: /metrics

  - job_name: 'nginx'
    static_configs:
      - targets: ['localhost:9113']
    scrape_interval: 30s

  - job_name: 'mysql'
    static_configs:
      - targets: ['localhost:9104']
    scrape_interval: 30s

  - job_name: 'valkey'
    static_configs:
      - targets: ['localhost:9121']
    scrape_interval: 30s

rule_files:
  - "medium_level_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: []
EOF

    # 创建中级别告警规则
    sudo tee /etc/prometheus/medium_level_rules.yml > /dev/null <<EOF
groups:
- name: medium_level_alerts
  rules:
  - alert: HighCPUUsage
    expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 70
    for: 3m
    labels:
      severity: warning
    annotations:
      summary: "High CPU usage detected"
      description: "CPU usage is above 70% for more than 3 minutes"

  - alert: HighMemoryUsage
    expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 80
    for: 3m
    labels:
      severity: warning
    annotations:
      summary: "High memory usage detected"
      description: "Memory usage is above 80% for more than 3 minutes"

  - alert: DiskSpaceLow
    expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 15
    for: 3m
    labels:
      severity: critical
    annotations:
      summary: "Low disk space"
      description: "Disk space is below 15%"

  - alert: MySQLDown
    expr: up{job="mysql"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "MySQL is down"
      description: "MySQL service is not responding"

  - alert: NginxDown
    expr: up{job="nginx"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Nginx is down"
      description: "Nginx service is not responding"

  - alert: HighMySQLConnections
    expr: mysql_global_status_threads_connected / mysql_global_variables_max_connections * 100 > 80
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High MySQL connections"
      description: "MySQL connections are above 80% of max"
EOF

    sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
    sudo chown prometheus:prometheus /etc/prometheus/medium_level_rules.yml
    
    log_success "中级别监控配置完成"
    log_info "监控间隔: 15秒"
    log_info "告警规则: 系统+服务告警"
}

# 高级别监控配置
configure_prometheus_high() {
    echo "配置高级别监控 (High Level)"
    echo "=========================================="
    
    # 创建高级Prometheus配置
    sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 10s
  evaluation_interval: 10s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']
    scrape_interval: 10s
    metrics_path: /metrics

  - job_name: 'nginx'
    static_configs:
      - targets: ['localhost:9113']
    scrape_interval: 15s

  - job_name: 'mysql'
    static_configs:
      - targets: ['localhost:9104']
    scrape_interval: 15s

  - job_name: 'valkey'
    static_configs:
      - targets: ['localhost:9121']
    scrape_interval: 15s

  - job_name: 'opensearch'
    static_configs:
      - targets: ['localhost:9200']
    scrape_interval: 30s
    metrics_path: /_prometheus/metrics

  - job_name: 'rabbitmq'
    static_configs:
      - targets: ['localhost:15692']
    scrape_interval: 30s

rule_files:
  - "high_level_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: []
EOF

    # 创建高级别告警规则
    sudo tee /etc/prometheus/high_level_rules.yml > /dev/null <<EOF
groups:
- name: high_level_alerts
  rules:
  - alert: HighCPUUsage
    expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 60
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High CPU usage detected"
      description: "CPU usage is above 60% for more than 2 minutes"

  - alert: HighMemoryUsage
    expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 75
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High memory usage detected"
      description: "Memory usage is above 75% for more than 2 minutes"

  - alert: DiskSpaceLow
    expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 20
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Low disk space"
      description: "Disk space is below 20%"

  - alert: MySQLDown
    expr: up{job="mysql"} == 0
    for: 30s
    labels:
      severity: critical
    annotations:
      summary: "MySQL is down"
      description: "MySQL service is not responding"

  - alert: NginxDown
    expr: up{job="nginx"} == 0
    for: 30s
    labels:
      severity: critical
    annotations:
      summary: "Nginx is down"
      description: "Nginx service is not responding"

  - alert: HighMySQLConnections
    expr: mysql_global_status_threads_connected / mysql_global_variables_max_connections * 100 > 70
    for: 1m
    labels:
      severity: warning
    annotations:
      summary: "High MySQL connections"
      description: "MySQL connections are above 70% of max"

  - alert: HighNginxErrorRate
    expr: rate(nginx_http_requests_total{status=~"5.."}[5m]) / rate(nginx_http_requests_total[5m]) * 100 > 5
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High Nginx error rate"
      description: "Nginx 5xx error rate is above 5%"

  - alert: ValkeyDown
    expr: up{job="valkey"} == 0
    for: 30s
    labels:
      severity: critical
    annotations:
      summary: "Valkey is down"
      description: "Valkey service is not responding"

  - alert: OpenSearchDown
    expr: up{job="opensearch"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "OpenSearch is down"
      description: "OpenSearch service is not responding"

  - alert: RabbitMQDown
    expr: up{job="rabbitmq"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "RabbitMQ is down"
      description: "RabbitMQ service is not responding"
EOF

    sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
    sudo chown prometheus:prometheus /etc/prometheus/high_level_rules.yml
    
    log_success "高级别监控配置完成"
    log_info "监控间隔: 10秒"
    log_info "告警规则: 全面系统+服务告警"
}

# 分级监控安装
install_monitoring_by_level() {
    local level="$1"
    
    if [[ -z "$level" ]]; then
        level=$(detect_monitoring_level)
        log_info "自动检测到监控级别: $level"
    fi
    
    echo "安装 $level 级别监控系统"
    echo "=========================================="
    
    # 安装Prometheus
    monitor_prometheus_setup
    
    # 根据级别配置
    case "$level" in
        "low")
            configure_prometheus_low
            ;;
        "medium")
            configure_prometheus_medium
            ;;
        "high")
            configure_prometheus_high
            ;;
        *)
            log_error "未知的监控级别: $level"
            log_info "支持的级别: low, medium, high"
            exit 1
            ;;
    esac
    
    # 重启Prometheus应用配置
    sudo systemctl restart prometheus
    
    if systemctl is-active --quiet prometheus; then
        log_success "$level 级别监控系统安装完成"
        local server_ip
        server_ip=$(ip route get 1.1.1.1 | awk '{print $7}' | head -1)
        log_info "Prometheus访问地址: http://${server_ip}:9090"
        log_info "监控级别: $level"
        
        # 显示配置信息
        show_monitoring_level_info "$level"
    else
        log_error "Prometheus启动失败"
        exit 1
    fi
}

# 显示监控级别信息
show_monitoring_level_info() {
    local level="$1"
    
    echo ""
    echo "监控级别配置信息:"
    echo "=========================================="
    
    case "$level" in
        "low")
            echo "级别: 低级别 (Low Level)"
            echo "监控间隔: 30秒"
            echo "监控目标: Prometheus, Node Exporter, Nginx"
            echo "告警规则: 基础系统告警"
            echo "适用场景: 小型服务器, 开发环境"
            ;;
        "medium")
            echo "级别: 中级别 (Medium Level)"
            echo "监控间隔: 15秒"
            echo "监控目标: Prometheus, Node Exporter, Nginx, MySQL, Valkey"
            echo "告警规则: 系统+服务告警"
            echo "适用场景: 中型服务器, 测试环境"
            ;;
        "high")
            echo "级别: 高级别 (High Level)"
            echo "监控间隔: 10秒"
            echo "监控目标: 所有服务 (Prometheus, Node Exporter, Nginx, MySQL, Valkey, OpenSearch, RabbitMQ)"
            echo "告警规则: 全面系统+服务告警"
            echo "适用场景: 大型服务器, 生产环境"
            ;;
    esac
    
    echo ""
    echo "下一步操作:"
    echo "  1. 安装Grafana: saltgoat monitoring grafana"
    echo "  2. 访问Prometheus查看数据收集状态"
    echo "  3. 在Grafana中导入对应级别的仪表板"
}

# 显示监控级别帮助
show_monitoring_levels_help() {
    echo "SaltGoat 分级监控系统"
    echo "=========================================="
    echo ""
    echo "用法: saltgoat monitoring prometheus <level>"
    echo ""
    echo "监控级别:"
    echo "  low     - 低级别监控 (小型服务器)"
    echo "  medium  - 中级别监控 (中型服务器)"
    echo "  high    - 高级别监控 (大型服务器)"
    echo "  auto    - 自动检测级别"
    echo ""
    echo "示例:"
    echo "  saltgoat monitoring prometheus low      # 安装低级别监控"
    echo "  saltgoat monitoring prometheus medium   # 安装中级别监控"
    echo "  saltgoat monitoring prometheus high     # 安装高级别监控"
    echo "  saltgoat monitoring prometheus auto     # 自动检测级别"
    echo ""
    echo "级别对比:"
    echo "  低级别: 30秒间隔, 基础告警, 3个监控目标"
    echo "  中级别: 15秒间隔, 系统+服务告警, 5个监控目标"
    echo "  高级别: 10秒间隔, 全面告警, 7个监控目标"
    echo ""
}

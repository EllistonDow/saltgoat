#!/bin/bash
# 成本优化监控配置模块
# services/cost-optimized-monitoring.sh

# 成本分析
analyze_cost_requirements() {
    echo "分析成本需求..."
    
    # 检测系统资源
    local total_memory_gb=$(free -m | awk 'NR==2{print int($2/1024)}')
    local cpu_cores=$(nproc)
    local disk_size_gb=$(df / | awk 'NR==2{print int($2/1024/1024)}')
    
    # 估算监控成本
    local estimated_cost=0
    
    # 基于内存估算成本
    if [[ $total_memory_gb -ge 64 ]]; then
        estimated_cost=$((estimated_cost + 50))  # 高内存系统
    elif [[ $total_memory_gb -ge 16 ]]; then
        estimated_cost=$((estimated_cost + 20))  # 中内存系统
    else
        estimated_cost=$((estimated_cost + 10))  # 低内存系统
    fi
    
    # 基于CPU估算成本
    if [[ $cpu_cores -ge 16 ]]; then
        estimated_cost=$((estimated_cost + 30))
    elif [[ $cpu_cores -ge 8 ]]; then
        estimated_cost=$((estimated_cost + 15))
    else
        estimated_cost=$((estimated_cost + 5))
    fi
    
    echo "成本分析结果:"
    echo "  系统内存: ${total_memory_gb}GB"
    echo "  CPU核心: ${cpu_cores}个"
    echo "  磁盘大小: ${disk_size_gb}GB"
    echo "  预估月成本: \$${estimated_cost}"
    
    # 确定成本级别
    if [[ $estimated_cost -ge 50 ]]; then
        echo "premium"
    elif [[ $estimated_cost -ge 20 ]]; then
        echo "standard"
    else
        echo "budget"
    fi
}

# 预算级监控配置
configure_budget_monitoring() {
    echo "配置预算级监控 (Budget)"
    echo "=========================================="
    
    sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 60s
  evaluation_interval: 60s
  # 预算级配置，最小化资源使用
  storage.tsdb.retention.time: 3d
  storage.tsdb.retention.size: 500MB
  storage.tsdb.min-block-duration: 2h
  storage.tsdb.max-block-duration: 25h

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
    scrape_interval: 60s

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']
    scrape_interval: 60s
    # 只收集关键指标
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: 'node_cpu_seconds_total|node_memory_MemTotal_bytes|node_memory_MemAvailable_bytes|node_filesystem_avail_bytes|node_load1'
        action: keep

rule_files:
  - "budget_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: []
EOF

    sudo tee /etc/prometheus/budget_rules.yml > /dev/null <<EOF
groups:
- name: budget_alerts
  rules:
  - alert: SystemDown
    expr: up == 0
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "System is down"
      description: "Service {{ \$labels.instance }} is down"

  - alert: DiskSpaceCritical
    expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.05
    for: 10m
    labels:
      severity: critical
    annotations:
      summary: "Critical disk space"
      description: "Disk space below 5%"
EOF

    sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
    sudo chown prometheus:prometheus /etc/prometheus/budget_rules.yml
    
    log_success "预算级监控配置完成"
}

# 标准级监控配置
configure_standard_monitoring() {
    echo "配置标准级监控 (Standard)"
    echo "=========================================="
    
    sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 30s
  evaluation_interval: 30s
  storage.tsdb.retention.time: 7d
  storage.tsdb.retention.size: 2GB

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']
    scrape_interval: 30s

  - job_name: 'nginx'
    static_configs:
      - targets: ['localhost:9113']
    scrape_interval: 60s

rule_files:
  - "standard_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: []
EOF

    sudo tee /etc/prometheus/standard_rules.yml > /dev/null <<EOF
groups:
- name: standard_alerts
  rules:
  - alert: HighCPUUsage
    expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High CPU usage"
      description: "CPU usage above 80%"

  - alert: HighMemoryUsage
    expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High memory usage"
      description: "Memory usage above 85%"

  - alert: DiskSpaceLow
    expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 10
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "Low disk space"
      description: "Disk space below 10%"

  - alert: ServiceDown
    expr: up == 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Service is down"
      description: "Service {{ \$labels.instance }} is down"
EOF

    sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
    sudo chown prometheus:prometheus /etc/prometheus/standard_rules.yml
    
    log_success "标准级监控配置完成"
}

# 高级监控配置
configure_premium_monitoring() {
    echo "配置高级监控 (Premium)"
    echo "=========================================="
    
    sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  storage.tsdb.retention.time: 30d
  storage.tsdb.retention.size: 10GB
  # 高级配置，优化性能
  storage.tsdb.min-block-duration: 2h
  storage.tsdb.max-block-duration: 25h

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']
    scrape_interval: 15s

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
  - "premium_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: []
EOF

    sudo tee /etc/prometheus/premium_rules.yml > /dev/null <<EOF
groups:
- name: premium_alerts
  rules:
  - alert: HighCPUUsage
    expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 70
    for: 3m
    labels:
      severity: warning
    annotations:
      summary: "High CPU usage"
      description: "CPU usage above 70%"

  - alert: HighMemoryUsage
    expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 80
    for: 3m
    labels:
      severity: warning
    annotations:
      summary: "High memory usage"
      description: "Memory usage above 80%"

  - alert: DiskSpaceLow
    expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 15
    for: 3m
    labels:
      severity: critical
    annotations:
      summary: "Low disk space"
      description: "Disk space below 15%"

  - alert: ServiceDown
    expr: up == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Service is down"
      description: "Service {{ \$labels.instance }} is down"

  - alert: DatabaseSlowQueries
    expr: mysql_global_status_slow_queries > 5
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "Database slow queries"
      description: "More than 5 slow queries"

  - alert: CacheMissRate
    expr: (redis_keyspace_misses_total / redis_keyspace_hits_total) * 100 > 20
    for: 3m
    labels:
      severity: warning
    annotations:
      summary: "High cache miss rate"
      description: "Cache miss rate above 20%"
EOF

    sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
    sudo chown prometheus:prometheus /etc/prometheus/premium_rules.yml
    
    log_success "高级监控配置完成"
}

# 成本优化监控安装
install_cost_optimized_monitoring() {
    local cost_level=$(analyze_cost_requirements)
    
    echo "成本优化监控配置"
    echo "=========================================="
    log_info "检测到成本级别: $cost_level"
    
    # 安装Prometheus
    monitor_prometheus_setup
    
    # 根据成本级别配置
    case "$cost_level" in
        "budget")
            configure_budget_monitoring
            ;;
        "standard")
            configure_standard_monitoring
            ;;
        "premium")
            configure_premium_monitoring
            ;;
    esac
    
    # 重启Prometheus应用配置
    sudo systemctl restart prometheus
    
    if systemctl is-active --quiet prometheus; then
        log_success "成本优化监控系统安装完成"
        local server_ip=$(ip route get 1.1.1.1 | awk '{print $7}' | head -1)
        log_info "Prometheus访问地址: http://${server_ip}:9090"
        log_info "成本级别: $cost_level"
        
        show_cost_monitoring_info "$cost_level"
    else
        log_error "Prometheus启动失败"
        exit 1
    fi
}

# 显示成本监控信息
show_cost_monitoring_info() {
    local cost_level="$1"
    
    echo ""
    echo "成本优化监控配置信息:"
    echo "=========================================="
    
    case "$cost_level" in
        "budget")
            echo "成本级别: 预算级 (Budget)"
            echo "监控间隔: 60秒"
            echo "数据保留: 3天"
            echo "存储限制: 500MB"
            echo "适用场景: 个人项目, 开发环境"
            echo "月成本: < \$20"
            ;;
        "standard")
            echo "成本级别: 标准级 (Standard)"
            echo "监控间隔: 30秒"
            echo "数据保留: 7天"
            echo "存储限制: 2GB"
            echo "适用场景: 小型企业, 测试环境"
            echo "月成本: \$20-50"
            ;;
        "premium")
            echo "成本级别: 高级 (Premium)"
            echo "监控间隔: 15秒"
            echo "数据保留: 30天"
            echo "存储限制: 10GB"
            echo "适用场景: 大型企业, 生产环境"
            echo "月成本: > \$50"
            ;;
    esac
    
    echo ""
    echo "下一步操作:"
    echo "  1. 安装Grafana: saltgoat monitoring grafana"
    echo "  2. 导入对应成本级别的仪表板"
    echo "  3. 配置告警通知"
}

# 显示成本监控帮助
show_cost_monitoring_help() {
    echo "SaltGoat 成本优化监控系统"
    echo "=========================================="
    echo ""
    echo "用法: saltgoat monitoring cost"
    echo ""
    echo "功能特点:"
    echo "  - 自动分析系统成本"
    echo "  - 优化监控资源使用"
    echo "  - 智能配置存储策略"
    echo "  - 成本相关的告警规则"
    echo ""
    echo "成本级别:"
    echo "  预算级  - 60秒间隔, 3天保留, 500MB存储"
    echo "  标准级  - 30秒间隔, 7天保留, 2GB存储"
    echo "  高级    - 15秒间隔, 30天保留, 10GB存储"
    echo ""
    echo "示例:"
    echo "  saltgoat monitoring cost    # 成本优化配置"
    echo ""
}

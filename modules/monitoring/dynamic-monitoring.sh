#!/bin/bash
# 动态监控配置模块 - 基于性能需求
# services/dynamic-monitoring.sh

# 性能需求分析
analyze_performance_requirements() {
    echo "分析性能需求..."
    
    # 检测系统负载
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_cores
    cpu_cores=$(nproc)
    local load_ratio
    load_ratio=$(echo "scale=2; $load_avg / $cpu_cores" | bc)
    
    # 检测内存使用
    local memory_usage
    memory_usage=$(free | awk 'NR==2{printf "%.2f", $3*100/$2}')
    
    # 检测磁盘IO
    local disk_io
    disk_io=$(iostat -x 1 1 | tail -n +4 | awk '{sum+=$10} END {print sum/NR}')
    
    # 检测网络流量
    local network_traffic
    network_traffic=$(awk 'NR>2 {sum+=$2+$10} END {print sum}' /proc/net/dev)
    
    echo "性能分析结果:"
    echo "  CPU负载比: $load_ratio"
    echo "  内存使用率: ${memory_usage}%"
    echo "  磁盘IO: $disk_io"
    echo "  网络流量: $network_traffic"
    
    # 确定性能级别
    if (( $(echo "$load_ratio > 2.0" | bc -l) )) || (( $(echo "$memory_usage > 80" | bc -l) )); then
        echo "high"
    elif (( $(echo "$load_ratio > 1.0" | bc -l) )) || (( $(echo "$memory_usage > 60" | bc -l) )); then
        echo "medium"
    else
        echo "low"
    fi
}

# 低负载监控配置
configure_low_load_monitoring() {
    echo "配置低负载监控 (Low Load)"
    echo "=========================================="
    
    sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 30s
  evaluation_interval: 30s
  # 低负载环境，减少存储压力
  storage.tsdb.retention.time: 7d
  storage.tsdb.retention.size: 1GB

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']
    scrape_interval: 30s

rule_files:
  - "low_load_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: []
EOF

    sudo tee /etc/prometheus/low_load_rules.yml > /dev/null <<EOF
groups:
- name: low_load_alerts
  rules:
  - alert: SystemOverload
    expr: node_load1 / on(instance) count by(instance)(node_cpu_seconds_total{mode="idle"}) > 1.5
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "System overload detected"
      description: "Load average is above 1.5"

  - alert: MemoryPressure
    expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes > 0.8
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "Memory pressure"
      description: "Memory usage above 80%"
EOF

    sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
    sudo chown prometheus:prometheus /etc/prometheus/low_load_rules.yml
    
    log_success "低负载监控配置完成"
}

# 中负载监控配置
configure_medium_load_monitoring() {
    echo "配置中负载监控 (Medium Load)"
    echo "=========================================="
    
    sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  storage.tsdb.retention.time: 15d
  storage.tsdb.retention.size: 5GB

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

rule_files:
  - "medium_load_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: []
EOF

    sudo tee /etc/prometheus/medium_load_rules.yml > /dev/null <<EOF
groups:
- name: medium_load_alerts
  rules:
  - alert: HighLoadAverage
    expr: node_load1 / on(instance) count by(instance)(node_cpu_seconds_total{mode="idle"}) > 2.0
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High load average"
      description: "Load average is above 2.0"

  - alert: DatabaseSlowQueries
    expr: mysql_global_status_slow_queries > 5
    for: 3m
    labels:
      severity: warning
    annotations:
      summary: "Database slow queries"
      description: "More than 5 slow queries"

  - alert: WebServerErrors
    expr: rate(nginx_http_requests_total{status=~"5.."}[5m]) > 0.1
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Web server errors"
      description: "Error rate above 0.1 req/s"
EOF

    sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
    sudo chown prometheus:prometheus /etc/prometheus/medium_load_rules.yml
    
    log_success "中负载监控配置完成"
}

# 高负载监控配置
configure_high_load_monitoring() {
    echo "配置高负载监控 (High Load)"
    echo "=========================================="
    
    sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 5s
  evaluation_interval: 5s
  storage.tsdb.retention.time: 30d
  storage.tsdb.retention.size: 20GB
  # 高负载环境，优化性能
  storage.tsdb.min-block-duration: 2h
  storage.tsdb.max-block-duration: 25h

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']
    scrape_interval: 5s

  - job_name: 'nginx'
    static_configs:
      - targets: ['localhost:9113']
    scrape_interval: 10s

  - job_name: 'mysql'
    static_configs:
      - targets: ['localhost:9104']
    scrape_interval: 10s

  - job_name: 'valkey'
    static_configs:
      - targets: ['localhost:9121']
    scrape_interval: 15s

rule_files:
  - "high_load_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: []
EOF

    sudo tee /etc/prometheus/high_load_rules.yml > /dev/null <<EOF
groups:
- name: high_load_alerts
  rules:
  - alert: CriticalLoadAverage
    expr: node_load1 / on(instance) count by(instance)(node_cpu_seconds_total{mode="idle"}) > 3.0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Critical load average"
      description: "Load average is above 3.0"

  - alert: MemoryExhaustion
    expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes > 0.9
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Memory exhaustion"
      description: "Memory usage above 90%"

  - alert: DatabaseConnectionPool
    expr: mysql_global_status_threads_connected / mysql_global_variables_max_connections > 0.8
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Database connection pool"
      description: "Connection pool above 80%"

  - alert: CacheMissRate
    expr: (redis_keyspace_misses_total / redis_keyspace_hits_total) > 0.3
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High cache miss rate"
      description: "Cache miss rate above 30%"
EOF

    sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
    sudo chown prometheus:prometheus /etc/prometheus/high_load_rules.yml
    
    log_success "高负载监控配置完成"
}

# 动态监控安装
install_dynamic_monitoring() {
    local load_level
    load_level=$(analyze_performance_requirements)
    
    echo "动态监控配置"
    echo "=========================================="
    log_info "检测到负载级别: $load_level"
    
    # 安装Prometheus
    monitor_prometheus_setup
    
    # 根据负载级别配置
    case "$load_level" in
        "low")
            configure_low_load_monitoring
            ;;
        "medium")
            configure_medium_load_monitoring
            ;;
        "high")
            configure_high_load_monitoring
            ;;
    esac
    
    # 重启Prometheus应用配置
    sudo systemctl restart prometheus
    
    if systemctl is-active --quiet prometheus; then
        log_success "动态监控系统安装完成"
        local server_ip
        server_ip=$(ip route get 1.1.1.1 | awk '{print $7}' | head -1)
        log_info "Prometheus访问地址: http://${server_ip}:9090"
        log_info "负载级别: $load_level"
        
        show_dynamic_monitoring_info "$load_level"
    else
        log_error "Prometheus启动失败"
        exit 1
    fi
}

# 显示动态监控信息
show_dynamic_monitoring_info() {
    local load_level="$1"
    
    echo ""
    echo "动态监控配置信息:"
    echo "=========================================="
    
    case "$load_level" in
        "low")
            echo "负载级别: 低负载 (Low Load)"
            echo "监控间隔: 30秒"
            echo "数据保留: 7天"
            echo "存储限制: 1GB"
            echo "适用场景: 开发环境, 小型应用"
            ;;
        "medium")
            echo "负载级别: 中负载 (Medium Load)"
            echo "监控间隔: 15秒"
            echo "数据保留: 15天"
            echo "存储限制: 5GB"
            echo "适用场景: 测试环境, 中型应用"
            ;;
        "high")
            echo "负载级别: 高负载 (High Load)"
            echo "监控间隔: 5秒"
            echo "数据保留: 30天"
            echo "存储限制: 20GB"
            echo "适用场景: 生产环境, 大型应用"
            ;;
    esac
    
    echo ""
    echo "下一步操作:"
    echo "  1. 安装Grafana: saltgoat monitoring grafana"
    echo "  2. 导入对应负载级别的仪表板"
    echo "  3. 配置告警通知"
}

# 显示动态监控帮助
show_dynamic_monitoring_help() {
    echo "SaltGoat 动态监控系统"
    echo "=========================================="
    echo ""
    echo "用法: saltgoat monitoring dynamic"
    echo ""
    echo "功能特点:"
    echo "  - 自动分析系统负载"
    echo "  - 动态调整监控频率"
    echo "  - 智能配置存储策略"
    echo "  - 负载相关的告警规则"
    echo ""
    echo "负载级别:"
    echo "  低负载  - 30秒间隔, 7天保留, 1GB存储"
    echo "  中负载  - 15秒间隔, 15天保留, 5GB存储"
    echo "  高负载  - 5秒间隔, 30天保留, 20GB存储"
    echo ""
    echo "示例:"
    echo "  saltgoat monitoring dynamic    # 动态检测并配置"
    echo ""
}

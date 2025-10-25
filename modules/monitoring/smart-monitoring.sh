#!/bin/bash
# 智能监控配置模块 - 基于业务场景
# services/smart-monitoring.sh

# 业务场景检测
detect_business_scenario() {
    echo "检测业务场景..."
    
    # 检测已安装的服务
    local services=()
    systemctl is-active --quiet nginx && services+=("web")
    systemctl is-active --quiet mysql && services+=("database")
    systemctl is-active --quiet valkey && services+=("cache")
    systemctl is-active --quiet opensearch && services+=("search")
    systemctl is-active --quiet rabbitmq && services+=("queue")
    
    # 检测网站类型
    local web_type="generic"
    if [[ -d "/var/www/magento" ]] || [[ -d "/var/www/html/magento" ]]; then
        web_type="magento"
    elif [[ -d "/var/www/wordpress" ]] || [[ -d "/var/www/html/wordpress" ]]; then
        web_type="wordpress"
    elif [[ -d "/var/www/laravel" ]] || [[ -d "/var/www/html/laravel" ]]; then
        web_type="laravel"
    fi
    
    # 检测服务器用途
    local server_role="web"
    if [[ ${#services[@]} -gt 3 ]]; then
        server_role="fullstack"
    else
        for svc in "${services[@]}"; do
            if [[ "$svc" == "database" ]]; then
                server_role="database"
                break
            fi
        done
    fi
    
    echo "检测结果:"
    echo "  已安装服务: ${services[*]}"
    echo "  网站类型: $web_type"
    echo "  服务器角色: $server_role"
    
    echo "$web_type:$server_role:${services[*]}"
}

# Magento电商监控配置
configure_magento_monitoring() {
    echo "配置Magento电商监控"
    echo "=========================================="
    
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

  - job_name: 'nginx'
    static_configs:
      - targets: ['localhost:9113']

  - job_name: 'mysql'
    static_configs:
      - targets: ['localhost:9104']

  - job_name: 'valkey'
    static_configs:
      - targets: ['localhost:9121']

  - job_name: 'opensearch'
    static_configs:
      - targets: ['localhost:9200']

rule_files:
  - "magento_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: []
EOF

    # Magento专用告警规则
    sudo tee /etc/prometheus/magento_rules.yml > /dev/null <<EOF
groups:
- name: magento_alerts
  rules:
  - alert: MagentoHighResponseTime
    expr: nginx_http_request_duration_seconds{quantile="0.95"} > 2
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "Magento high response time"
      description: "95th percentile response time is above 2 seconds"

  - alert: MagentoHighErrorRate
    expr: rate(nginx_http_requests_total{status=~"5.."}[5m]) / rate(nginx_http_requests_total[5m]) * 100 > 1
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Magento high error rate"
      description: "Error rate is above 1%"

  - alert: MagentoDatabaseSlowQueries
    expr: mysql_global_status_slow_queries > 10
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Magento slow database queries"
      description: "More than 10 slow queries detected"

  - alert: MagentoCacheMissRate
    expr: (redis_keyspace_misses_total / redis_keyspace_hits_total) * 100 > 20
    for: 3m
    labels:
      severity: warning
    annotations:
      summary: "Magento high cache miss rate"
      description: "Cache miss rate is above 20%"

  - alert: MagentoSearchDown
    expr: up{job="opensearch"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Magento search is down"
      description: "OpenSearch service is not responding"
EOF

    sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
    sudo chown prometheus:prometheus /etc/prometheus/magento_rules.yml
    
    log_success "Magento电商监控配置完成"
}

# WordPress博客监控配置
configure_wordpress_monitoring() {
    echo "配置WordPress博客监控"
    echo "=========================================="
    
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

  - job_name: 'nginx'
    static_configs:
      - targets: ['localhost:9113']

  - job_name: 'mysql'
    static_configs:
      - targets: ['localhost:9104']

rule_files:
  - "wordpress_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: []
EOF

    # WordPress专用告警规则
    sudo tee /etc/prometheus/wordpress_rules.yml > /dev/null <<EOF
groups:
- name: wordpress_alerts
  rules:
  - alert: WordPressHighTraffic
    expr: rate(nginx_http_requests_total[5m]) > 100
    for: 3m
    labels:
      severity: warning
    annotations:
      summary: "WordPress high traffic"
      description: "Request rate is above 100 req/s"

  - alert: WordPressDatabaseConnections
    expr: mysql_global_status_threads_connected > 50
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "WordPress high database connections"
      description: "Database connections above 50"

  - alert: WordPressDiskSpace
    expr: (node_filesystem_avail_bytes{mountpoint="/var/www"} / node_filesystem_size_bytes{mountpoint="/var/www"}) * 100 < 20
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "WordPress low disk space"
      description: "WordPress disk space below 20%"
EOF

    sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
    sudo chown prometheus:prometheus /etc/prometheus/wordpress_rules.yml
    
    log_success "WordPress博客监控配置完成"
}

# Laravel应用监控配置
configure_laravel_monitoring() {
    echo "配置Laravel应用监控"
    echo "=========================================="
    
    sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 12s
  evaluation_interval: 12s

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

rule_files:
  - "laravel_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: []
EOF

    # Laravel专用告警规则
    sudo tee /etc/prometheus/laravel_rules.yml > /dev/null <<EOF
groups:
- name: laravel_alerts
  rules:
  - alert: LaravelQueueBacklog
    expr: redis_list_length{key="queues:default"} > 1000
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Laravel queue backlog"
      description: "Queue backlog is above 1000 jobs"

  - alert: LaravelSessionStorage
    expr: redis_memory_used_bytes / redis_maxmemory_bytes * 100 > 80
    for: 3m
    labels:
      severity: warning
    annotations:
      summary: "Laravel session storage high"
      description: "Redis memory usage above 80%"

  - alert: LaravelDatabaseSlowQueries
    expr: mysql_global_status_slow_queries > 5
    for: 3m
    labels:
      severity: warning
    annotations:
      summary: "Laravel slow queries"
      description: "More than 5 slow queries detected"
EOF

    sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
    sudo chown prometheus:prometheus /etc/prometheus/laravel_rules.yml
    
    log_success "Laravel应用监控配置完成"
}

# 通用Web监控配置
configure_generic_monitoring() {
    echo "配置通用Web监控"
    echo "=========================================="
    
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

  - job_name: 'nginx'
    static_configs:
      - targets: ['localhost:9113']

rule_files:
  - "generic_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: []
EOF

    # 通用告警规则
    sudo tee /etc/prometheus/generic_rules.yml > /dev/null <<EOF
groups:
- name: generic_alerts
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
EOF

    sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
    sudo chown prometheus:prometheus /etc/prometheus/generic_rules.yml
    
    log_success "通用Web监控配置完成"
}

# 智能监控安装
install_smart_monitoring() {
    echo "智能监控配置"
    echo "=========================================="
    
    local scenario
    scenario=$(detect_business_scenario)
    local web_type
    web_type=$(echo "$scenario" | cut -d: -f1)
    
    # 安装Prometheus
    monitor_prometheus_setup
    
    # 根据业务场景配置
    case "$web_type" in
        "magento")
            configure_magento_monitoring
            ;;
        "wordpress")
            configure_wordpress_monitoring
            ;;
        "laravel")
            configure_laravel_monitoring
            ;;
        *)
            configure_generic_monitoring
            ;;
    esac
    
    # 重启Prometheus应用配置
    sudo systemctl restart prometheus
    
    if systemctl is-active --quiet prometheus; then
        log_success "智能监控系统安装完成"
        local server_ip
        server_ip=$(ip route get 1.1.1.1 | awk '{print $7}' | head -1)
        log_info "Prometheus访问地址: http://${server_ip}:9090"
        log_info "业务场景: $web_type"
        
        show_smart_monitoring_info "$web_type"
    else
        log_error "Prometheus启动失败"
        exit 1
    fi
}

# 显示智能监控信息
show_smart_monitoring_info() {
    local web_type="$1"
    
    echo ""
    echo "智能监控配置信息:"
    echo "=========================================="
    
    case "$web_type" in
        "magento")
            echo "业务场景: Magento电商平台"
            echo "监控重点: 响应时间, 错误率, 数据库性能, 缓存命中率"
            echo "告警规则: 电商专用告警"
            echo "推荐仪表板: Magento Performance Dashboard"
            ;;
        "wordpress")
            echo "业务场景: WordPress博客"
            echo "监控重点: 流量, 数据库连接, 磁盘空间"
            echo "告警规则: 博客专用告警"
            echo "推荐仪表板: WordPress Monitoring Dashboard"
            ;;
        "laravel")
            echo "业务场景: Laravel应用"
            echo "监控重点: 队列处理, 会话存储, 数据库查询"
            echo "告警规则: Laravel专用告警"
            echo "推荐仪表板: Laravel Application Dashboard"
            ;;
        *)
            echo "业务场景: 通用Web服务"
            echo "监控重点: 系统资源, 基础服务"
            echo "告警规则: 通用系统告警"
            echo "推荐仪表板: Basic System Dashboard"
            ;;
    esac
    
    echo ""
    echo "下一步操作:"
    echo "  1. 安装Grafana: saltgoat monitoring grafana"
    echo "  2. 导入对应的业务仪表板"
    echo "  3. 配置告警通知渠道"
}

# 显示智能监控帮助
show_smart_monitoring_help() {
    echo "SaltGoat 智能监控系统"
    echo "=========================================="
    echo ""
    echo "用法: saltgoat monitoring smart"
    echo ""
    echo "功能特点:"
    echo "  - 自动检测业务场景 (Magento/WordPress/Laravel/Generic)"
    echo "  - 智能配置监控规则"
    echo "  - 业务相关的告警设置"
    echo "  - 推荐专用仪表板"
    echo ""
    echo "支持的场景:"
    echo "  Magento   - 电商平台监控"
    echo "  WordPress - 博客系统监控"
    echo "  Laravel   - 应用框架监控"
    echo "  Generic   - 通用Web监控"
    echo ""
    echo "示例:"
    echo "  saltgoat monitoring smart    # 智能检测并配置"
    echo ""
}

#!/bin/bash

# SaltGoat Grafana 警报配置脚本
# 配置服务器重启、服务状态等警报

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 Grafana 是否运行
check_grafana() {
    if ! systemctl is-active --quiet grafana-server; then
        log_error "Grafana 服务未运行"
        exit 1
    fi
    log_success "Grafana 服务正在运行"
}

# 创建通知渠道
create_notification_channel() {
    log_info "创建邮件通知渠道..."
    
    # 创建邮件通知渠道
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -u admin:admin \
        "http://localhost:3000/api/alert-notifications" \
        -d '{
            "name": "Email Alerts",
            "type": "email",
            "settings": {
                "addresses": "notice@tschenfeng.com",
                "subject": "SaltGoat Alert: {{ .GroupLabels.alertname }}",
                "message": "Alert: {{ .GroupLabels.alertname }}\nStatus: {{ .Status }}\nDescription: {{ .Annotations.description }}\nTime: {{ .StartsAt }}"
            },
            "isDefault": true
        }' > /dev/null
    
    log_success "邮件通知渠道创建完成"
}

# 创建服务器重启警报规则
create_server_reboot_alert() {
    log_info "创建服务器重启警报规则..."
    
    # 创建服务器重启警报
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -u admin:admin \
        "http://localhost:3000/api/alerts" \
        -d '{
            "name": "Server Reboot Alert",
            "message": "服务器已重启",
            "frequency": "10s",
            "handler": 1,
            "noDataState": "no_data",
            "executionErrorState": "alerting",
            "conditions": [
                {
                    "evaluator": {
                        "params": [300],
                        "type": "gt"
                    },
                    "operator": {
                        "type": "and"
                    },
                    "query": {
                        "params": ["A", "5m", "now"]
                    },
                    "reducer": {
                        "params": [],
                        "type": "last"
                    },
                    "type": "query"
                }
            ],
            "for": "0s",
            "query": "up == 0",
            "title": "服务器重启检测"
        }' > /dev/null
    
    log_success "服务器重启警报规则创建完成"
}

# 创建服务状态警报规则
create_service_status_alerts() {
    log_info "创建服务状态警报规则..."
    
    # Nginx 服务状态
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -u admin:admin \
        "http://localhost:3000/api/alerts" \
        -d '{
            "name": "Nginx Service Down",
            "message": "Nginx 服务异常",
            "frequency": "10s",
            "handler": 1,
            "noDataState": "no_data",
            "executionErrorState": "alerting",
            "conditions": [
                {
                    "evaluator": {
                        "params": [0],
                        "type": "lt"
                    },
                    "operator": {
                        "type": "and"
                    },
                    "query": {
                        "params": ["A", "5m", "now"]
                    },
                    "reducer": {
                        "params": [],
                        "type": "last"
                    },
                    "type": "query"
                }
            ],
            "for": "30s",
            "query": "nginx_up == 0",
            "title": "Nginx 服务异常"
        }' > /dev/null
    
    # MySQL 服务状态
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -u admin:admin \
        "http://localhost:3000/api/alerts" \
        -d '{
            "name": "MySQL Service Down",
            "message": "MySQL 服务异常",
            "frequency": "10s",
            "handler": 1,
            "noDataState": "no_data",
            "executionErrorState": "alerting",
            "conditions": [
                {
                    "evaluator": {
                        "params": [0],
                        "type": "lt"
                    },
                    "operator": {
                        "type": "and"
                    },
                    "query": {
                        "params": ["A", "5m", "now"]
                    },
                    "reducer": {
                        "params": [],
                        "type": "last"
                    },
                    "type": "query"
                }
            ],
            "for": "30s",
            "query": "mysql_up == 0",
            "title": "MySQL 服务异常"
        }' > /dev/null
    
    log_success "服务状态警报规则创建完成"
}

# 创建系统资源警报规则
create_system_resource_alerts() {
    log_info "创建系统资源警报规则..."
    
    # CPU 使用率过高
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -u admin:admin \
        "http://localhost:3000/api/alerts" \
        -d '{
            "name": "High CPU Usage",
            "message": "CPU 使用率过高",
            "frequency": "10s",
            "handler": 1,
            "noDataState": "no_data",
            "executionErrorState": "alerting",
            "conditions": [
                {
                    "evaluator": {
                        "params": [80],
                        "type": "gt"
                    },
                    "operator": {
                        "type": "and"
                    },
                    "query": {
                        "params": ["A", "5m", "now"]
                    },
                    "reducer": {
                        "params": [],
                        "type": "last"
                    },
                    "type": "query"
                }
            ],
            "for": "2m",
            "query": "100 - (avg by (instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
            "title": "CPU 使用率过高"
        }' > /dev/null
    
    # 内存使用率过高
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -u admin:admin \
        "http://localhost:3000/api/alerts" \
        -d '{
            "name": "High Memory Usage",
            "message": "内存使用率过高",
            "frequency": "10s",
            "handler": 1,
            "noDataState": "no_data",
            "executionErrorState": "alerting",
            "conditions": [
                {
                    "evaluator": {
                        "params": [85],
                        "type": "gt"
                    },
                    "operator": {
                        "type": "and"
                    },
                    "query": {
                        "params": ["A", "5m", "now"]
                    },
                    "reducer": {
                        "params": [],
                        "type": "last"
                    },
                    "type": "query"
                }
            ],
            "for": "2m",
            "query": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100",
            "title": "内存使用率过高"
        }' > /dev/null
    
    # 磁盘空间不足
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -u admin:admin \
        "http://localhost:3000/api/alerts" \
        -d '{
            "name": "Low Disk Space",
            "message": "磁盘空间不足",
            "frequency": "10s",
            "handler": 1,
            "noDataState": "no_data",
            "executionErrorState": "alerting",
            "conditions": [
                {
                    "evaluator": {
                        "params": [90],
                        "type": "gt"
                    },
                    "operator": {
                        "type": "and"
                    },
                    "query": {
                        "params": ["A", "5m", "now"]
                    },
                    "reducer": {
                        "params": [],
                        "type": "last"
                    },
                    "type": "query"
                }
            ],
            "for": "1m",
            "query": "100 - ((node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"}) * 100)",
            "title": "磁盘空间不足"
        }' > /dev/null
    
    log_success "系统资源警报规则创建完成"
}

# 主函数
main() {
    log_info "开始配置 Grafana 警报系统..."
    
    check_grafana
    create_notification_channel
    create_server_reboot_alert
    create_service_status_alerts
    create_system_resource_alerts
    
    log_success "Grafana 警报系统配置完成！"
    log_info "访问 Grafana: http://192.99.45.187:3000"
    log_info "用户名: admin"
    log_info "密码: admin"
    log_info "邮件通知将发送到: notice@tschenfeng.com"
}

# 运行主函数
main "$@"

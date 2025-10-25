#!/bin/bash

# SaltGoat 内存监控脚本
# 监控系统内存使用率，在达到阈值时自动处理

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

# 获取内存使用率
get_memory_usage() {
    local mem_info
    mem_info=$(free | grep Mem)
    local total
    total=$(echo "$mem_info" | awk '{print $2}')
    local used
    used=$(echo "$mem_info" | awk '{print $3}')
    
    # 计算使用率 (used / total * 100)
    local usage_percent=$((used * 100 / total))
    echo "$usage_percent"
}

# 清理系统缓存
clean_system_cache() {
    log_info "清理系统缓存..."
    
    # 清理页面缓存
    sync
    echo 1 > /proc/sys/vm/drop_caches
    
    # 清理 dentries 和 inodes
    echo 2 > /proc/sys/vm/drop_caches
    
    # 清理所有缓存
    echo 3 > /proc/sys/vm/drop_caches
    
    log_success "系统缓存清理完成"
}

# 清理 Valkey 内存
clean_valkey_memory() {
    log_info "清理 Valkey 内存..."
    
    # 执行 Valkey 内存清理命令
    redis-cli --no-auth-warning -a "$(salt-call --local grains.get pillar_valkey_password 2>/dev/null | grep -v "local:" | tail -1 | xargs)" MEMORY PURGE 2>/dev/null || true
    
    log_success "Valkey 内存清理完成"
}

# 清理 OpenSearch 缓存
clean_opensearch_cache() {
    log_info "清理 OpenSearch 缓存..."
    
    # 清理查询缓存
    curl -s -X POST "localhost:9200/_cache/clear" > /dev/null 2>&1 || true
    
    # 强制合并段
    curl -s -X POST "localhost:9200/_forcemerge?max_num_segments=1" > /dev/null 2>&1 || true
    
    log_success "OpenSearch 缓存清理完成"
}

# 重启服务
restart_services() {
    log_warning "重启关键服务..."
    
    # 重启 OpenSearch
    systemctl restart opensearch
    sleep 5
    
    # 重启 RabbitMQ
    systemctl restart rabbitmq
    sleep 3
    
    # 重启 Valkey
    systemctl restart valkey
    sleep 2
    
    log_success "服务重启完成"
}

# 主监控函数
monitor_memory() {
    local usage
    usage=$(get_memory_usage)
    
    log_info "当前内存使用率: ${usage}%"
    
    if [ "$usage" -ge 85 ]; then
        log_error "内存使用率达到 ${usage}%，执行紧急处理..."
        
        # 85% 以上：重启服务
        restart_services
        
    elif [ "$usage" -ge 75 ]; then
        log_warning "内存使用率达到 ${usage}%，执行深度清理..."
        
        # 75% 以上：深度清理
        clean_system_cache
        clean_valkey_memory
        clean_opensearch_cache
        
    elif [ "$usage" -ge 65 ]; then
        log_warning "内存使用率达到 ${usage}%，执行基础清理..."
        
        # 65% 以上：基础清理
        clean_system_cache
        clean_valkey_memory
    fi
    
    # 记录到日志
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Memory usage: ${usage}%" >> /var/log/saltgoat-memory-monitor.log
}

# 检查参数
case "$1" in
    "monitor")
        monitor_memory
        ;;
    "clean")
        clean_system_cache
        clean_valkey_memory
        clean_opensearch_cache
        ;;
    "restart")
        restart_services
        ;;
    *)
        echo "用法: $0 {monitor|clean|restart}"
        echo "  monitor - 监控内存使用率并自动处理"
        echo "  clean   - 执行内存清理"
        echo "  restart - 重启关键服务"
        exit 1
        ;;
esac

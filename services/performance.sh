#!/bin/bash
# 性能监控模块 - 完全 Salt 原生功能
# services/performance.sh

# 性能监控配置
PERFORMANCE_LOG_DIR="$HOME/saltgoat_performance_logs"
PERFORMANCE_RETENTION_DAYS=7

# 确保性能日志目录存在
ensure_performance_log_dir() {
    salt-call --local file.mkdir "$PERFORMANCE_LOG_DIR" >/dev/null 2>&1
}

# CPU 性能监控
performance_cpu() {
    log_highlight "CPU 性能监控..."
    
    echo "CPU 使用情况:"
    echo "=========================================="
    
    # CPU 使用率
    local cpu_usage=$(top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | awk -F'%' '{print $1}' 2>/dev/null)
    echo "CPU 使用率: ${cpu_usage}%"
    
    # CPU 核心数
    local cpu_cores=$(nproc 2>/dev/null)
    echo "CPU 核心数: $cpu_cores"
    
    # CPU 负载
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' 2>/dev/null)
    echo "系统负载: $load_avg"
    
    # CPU 信息
    echo ""
    echo "CPU 详细信息:"
    echo "----------------------------------------"
    lscpu | grep -E '(Model name|CPU MHz|Cache)' 2>/dev/null
    
    # 进程 CPU 使用率排行
    echo ""
    echo "CPU 使用率最高的进程:"
    echo "----------------------------------------"
    ps aux --sort=-%cpu | head -10 2>/dev/null
}

# 内存性能监控
performance_memory() {
    log_highlight "内存性能监控..."
    
    echo "内存使用情况:"
    echo "=========================================="
    
    # 内存使用情况
    free -h 2>/dev/null
    
    echo ""
    echo "内存详细信息:"
    echo "----------------------------------------"
    
    # 内存使用率
    local mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}' 2>/dev/null)
    echo "内存使用率: ${mem_usage}%"
    
    # 交换分区使用情况
    local swap_usage=$(free | grep Swap | awk '{printf "%.1f", $3/$2 * 100.0}' 2>/dev/null)
    echo "交换分区使用率: ${swap_usage}%"
    
    # 内存使用率最高的进程
    echo ""
    echo "内存使用率最高的进程:"
    echo "----------------------------------------"
    ps aux --sort=-%mem | head -10 2>/dev/null
    
    # 缓存和缓冲区
    echo ""
    echo "缓存和缓冲区:"
    echo "----------------------------------------"
    cat /proc/meminfo | grep -E '(Cached|Buffers|MemAvailable)' 2>/dev/null
}

# 磁盘性能监控
performance_disk() {
    log_highlight "磁盘性能监控..."
    
    echo "磁盘使用情况:"
    echo "=========================================="
    
    # 磁盘使用情况
    salt-call --local cmd.run "df -h" 2>/dev/null
    
    echo ""
    echo "磁盘 I/O 统计:"
    echo "----------------------------------------"
    salt-call --local cmd.run "iostat -x 1 1" 2>/dev/null
    
    echo ""
    echo "磁盘使用率最高的目录:"
    echo "----------------------------------------"
    du -h / 2>/dev/null | sort -h -r | head -10
    
    echo ""
    echo "磁盘设备信息:"
    echo "----------------------------------------"
    salt-call --local cmd.run "lsblk" 2>/dev/null
    
    echo ""
    echo "磁盘健康状态:"
    echo "----------------------------------------"
    # 检查磁盘健康状态（如果支持）
    salt-call --local cmd.run "sudo smartctl -a /dev/sda 2>/dev/null | grep -E '(Model|Capacity|Power_On_Hours|Reallocated_Sector_Ct)' || echo 'SMART 信息不可用'" 2>/dev/null
}

# 网络性能监控
performance_network() {
    log_highlight "网络性能监控..."
    
    echo "网络接口状态:"
    echo "=========================================="
    
    # 网络接口信息
    salt-call --local cmd.run "ip addr show" 2>/dev/null
    
    echo ""
    echo "网络统计信息:"
    echo "----------------------------------------"
    salt-call --local cmd.run "ss -s" 2>/dev/null
    
    echo ""
    echo "网络连接统计:"
    echo "----------------------------------------"
    salt-call --local cmd.run "netstat -i" 2>/dev/null
    
    echo ""
    echo "网络流量统计:"
    echo "----------------------------------------"
    salt-call --local cmd.run "cat /proc/net/dev" 2>/dev/null
    
    echo ""
    echo "网络连接状态:"
    echo "----------------------------------------"
    salt-call --local cmd.run "ss -tuln" 2>/dev/null
}

# 进程性能监控
performance_processes() {
    log_highlight "进程性能监控..."
    
    echo "系统进程概览:"
    echo "=========================================="
    
    # 进程总数
    local total_processes=$(salt-call --local cmd.run "ps aux | wc -l" 2>/dev/null)
    echo "总进程数: $total_processes"
    
    # 运行中的进程
    local running_processes=$(salt-call --local cmd.run "ps aux | grep -c ' R '" 2>/dev/null)
    echo "运行中的进程: $running_processes"
    
    # 睡眠中的进程
    local sleeping_processes=$(salt-call --local cmd.run "ps aux | grep -c ' S '" 2>/dev/null)
    echo "睡眠中的进程: $sleeping_processes"
    
    echo ""
    echo "资源使用率最高的进程:"
    echo "----------------------------------------"
    salt-call --local cmd.run "ps aux --sort=-%cpu | head -10" 2>/dev/null
    
    echo ""
    echo "内存使用率最高的进程:"
    echo "----------------------------------------"
    salt-call --local cmd.run "ps aux --sort=-%mem | head -10" 2>/dev/null
    
    echo ""
    echo "系统服务状态:"
    echo "----------------------------------------"
    local services=("nginx" "mysql" "php8.3-fpm" "valkey" "rabbitmq" "opensearch")
    for service in "${services[@]}"; do
        local status=$(salt-call --local service.status "$service" --out=txt 2>/dev/null | tail -n 1)
        if [[ "$status" == "True" ]]; then
            echo "✅ $service: 运行中"
        else
            echo "❌ $service: 未运行"
        fi
    done
}

# 系统负载监控
performance_load() {
    log_highlight "系统负载监控..."
    
    echo "系统负载信息:"
    echo "=========================================="
    
    # 系统运行时间
    salt-call --local cmd.run "uptime" 2>/dev/null
    
    echo ""
    echo "系统负载详情:"
    echo "----------------------------------------"
    salt-call --local cmd.run "cat /proc/loadavg" 2>/dev/null
    
    echo ""
    echo "系统运行时间:"
    echo "----------------------------------------"
    salt-call --local cmd.run "uptime -p" 2>/dev/null
    
    echo ""
    echo "系统启动时间:"
    echo "----------------------------------------"
    salt-call --local cmd.run "who -b" 2>/dev/null
    
    echo ""
    echo "当前登录用户:"
    echo "----------------------------------------"
    salt-call --local cmd.run "who" 2>/dev/null
}

# 性能基准测试
performance_benchmark() {
    log_highlight "性能基准测试..."
    
    echo "CPU 基准测试:"
    echo "=========================================="
    
    # CPU 基准测试（简单计算）
    local start_time=$(date +%s.%N)
    salt-call --local cmd.run "for i in {1..1000}; do echo \$i > /dev/null; done" 2>/dev/null
    local end_time=$(date +%s.%N)
    local cpu_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "计算失败")
    echo "CPU 基准测试时间: ${cpu_time}秒"
    
    echo ""
    echo "磁盘 I/O 基准测试:"
    echo "----------------------------------------"
    
    # 磁盘写入测试
    local write_start=$(date +%s.%N)
    salt-call --local cmd.run "dd if=/dev/zero of=/tmp/test_write bs=1M count=100 2>/dev/null" 2>/dev/null
    local write_end=$(date +%s.%N)
    local write_time=$(echo "$write_end - $write_start" | bc 2>/dev/null || echo "计算失败")
    echo "磁盘写入测试时间: ${write_time}秒"
    
    # 磁盘读取测试
    local read_start=$(date +%s.%N)
    salt-call --local cmd.run "dd if=/tmp/test_write of=/dev/null bs=1M 2>/dev/null" 2>/dev/null
    local read_end=$(date +%s.%N)
    local read_time=$(echo "$read_end - $read_start" | bc 2>/dev/null || echo "计算失败")
    echo "磁盘读取测试时间: ${read_time}秒"
    
    # 清理测试文件
    salt-call --local cmd.run "rm -f /tmp/test_write" 2>/dev/null
    
    echo ""
    echo "网络基准测试:"
    echo "----------------------------------------"
    
    # 网络延迟测试
    salt-call --local cmd.run "ping -c 3 8.8.8.8" 2>/dev/null
}

# 性能历史记录
performance_history() {
    log_highlight "性能历史记录..."
    
    ensure_performance_log_dir
    
    local log_file="$PERFORMANCE_LOG_DIR/performance_$(date +%Y%m%d).log"
    
    echo "记录性能数据到: $log_file"
    
    {
        echo "=== SaltGoat 性能监控记录 ==="
        echo "时间: $(date)"
        echo ""
        
        echo "CPU 使用率:"
        salt-call --local cmd.run "top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | awk -F'%' '{print \$1}'" 2>/dev/null
        
        echo "内存使用率:"
        salt-call --local cmd.run "free | grep Mem | awk '{printf \"%.1f\", \$3/\$2 * 100.0}'" 2>/dev/null
        
        echo "磁盘使用率:"
        salt-call --local cmd.run "df -h / | tail -1 | awk '{print \$5}'" 2>/dev/null
        
        echo "系统负载:"
        salt-call --local cmd.run "uptime | awk -F'load average:' '{print \$2}'" 2>/dev/null
        
        echo ""
        
    } >> "$log_file"
    
    log_success "性能数据已记录"
    
    echo ""
    echo "最近性能记录:"
    echo "----------------------------------------"
    if [[ -f "$log_file" ]]; then
        tail -20 "$log_file"
    else
        log_info "暂无性能记录"
    fi
}

# 性能报告生成
performance_report() {
    local report_file="$HOME/saltgoat_performance_report_$(date +%Y%m%d_%H%M%S).txt"
    
    log_highlight "生成性能报告: $report_file"
    
    {
        echo "SaltGoat 性能监控报告"
        echo "======================"
        echo "生成时间: $(date)"
        echo "系统信息: $(uname -a)"
        echo ""
        
        performance_cpu
        echo ""
        
        performance_memory
        echo ""
        
        performance_disk
        echo ""
        
        performance_network
        echo ""
        
        performance_processes
        echo ""
        
        performance_load
        echo ""
        
        performance_benchmark
        
    } > "$report_file"
    
    log_success "性能报告已生成: $report_file"
}

# 性能清理
performance_cleanup() {
    log_highlight "清理性能日志（保留 $PERFORMANCE_RETENTION_DAYS 天）..."
    ensure_performance_log_dir
    
    # 清理旧日志文件
    salt-call --local cmd.run "find $PERFORMANCE_LOG_DIR -name 'performance_*.log' -mtime +$PERFORMANCE_RETENTION_DAYS -delete" 2>/dev/null
    
    log_success "性能日志清理完成"
}

#!/bin/bash
# 内存监控模块
# monitoring/memory.sh

# 内存监控处理函数
memory_handler() {
    case "$2" in
        "monitor")
            log_highlight "执行内存监控..."
            memory_monitor
            ;;
        "status")
            log_highlight "查看内存监控状态..."
            memory_status
            ;;
        *)
            log_error "未知的 Memory 操作: $2"
            log_info "支持: monitor, status"
            exit 1
            ;;
    esac
}

# 内存监控函数
memory_monitor() {
    local LOG_FILE="/var/log/saltgoat-memory.log"
    local THRESHOLD_75=75
    local THRESHOLD_85=85

    # 创建日志目录
    sudo mkdir -p "$(dirname "$LOG_FILE")"

    # 获取内存使用率
    local MEMORY_USAGE
    MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    local TIMESTAMP
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # 记录内存使用情况
    echo "[$TIMESTAMP] 内存使用率: ${MEMORY_USAGE}%" | sudo tee -a "$LOG_FILE" > /dev/null

    # 检查内存使用率
    if [[ $MEMORY_USAGE -ge $THRESHOLD_85 ]]; then
        echo "[$TIMESTAMP] 警告: 内存使用率达到 ${MEMORY_USAGE}%，超过 85% 阈值" | sudo tee -a "$LOG_FILE" > /dev/null
        echo "[$TIMESTAMP] 执行内存清理..." | sudo tee -a "$LOG_FILE" > /dev/null
        
        # 清理缓存
        sync
        echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
        
        # 重启相关服务
        sudo systemctl restart php8.3-fpm
        sudo systemctl restart nginx
        
        echo "[$TIMESTAMP] 内存清理完成" | sudo tee -a "$LOG_FILE" > /dev/null
        
    elif [[ $MEMORY_USAGE -ge $THRESHOLD_75 ]]; then
        echo "[$TIMESTAMP] 注意: 内存使用率达到 ${MEMORY_USAGE}%，超过 75% 阈值" | sudo tee -a "$LOG_FILE" > /dev/null
        echo "[$TIMESTAMP] 执行轻度内存清理..." | sudo tee -a "$LOG_FILE" > /dev/null
        
        # 轻度清理
        sync
        echo 1 | sudo tee /proc/sys/vm/drop_caches > /dev/null
        
        echo "[$TIMESTAMP] 轻度内存清理完成" | sudo tee -a "$LOG_FILE" > /dev/null
    fi

    # 保持日志文件大小合理
    if [[ -f "$LOG_FILE" ]] && [[ $(sudo stat -c%s "$LOG_FILE" 2>/dev/null) -gt 1048576 ]]; then
        sudo tail -n 1000 "$LOG_FILE" | sudo tee "${LOG_FILE}.tmp" > /dev/null && sudo mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
}

# 内存状态查看
memory_status() {
    local LOG_FILE="/var/log/saltgoat-memory.log"
    
    if [[ -f "$LOG_FILE" ]]; then
        echo "内存监控日志文件: $LOG_FILE"
        echo "最近 10 条记录:"
        sudo tail -n 10 "$LOG_FILE"
    else
        echo "内存监控日志文件不存在"
    fi
    
    echo ""
    echo "当前内存使用情况:"
    free -h
}

#!/bin/bash

# SaltGoat Schedule 管理脚本
# 管理 Salt 定时任务

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
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

# 显示帮助信息
show_help() {
    echo "SaltGoat Schedule 管理脚本"
    echo "=========================="
    echo
    echo "用法: $0 <command> [options]"
    echo
    echo "命令:"
    echo "  list                   列出所有定时任务"
    echo "  enable                 启用 SaltGoat 定时任务"
    echo "  disable                禁用 SaltGoat 定时任务"
    echo "  status                 查看定时任务状态"
    echo "  logs                   查看定时任务日志"
    echo "  test                   测试定时任务配置"
    echo "  help                   显示此帮助信息"
    echo
    echo "示例:"
    echo "  $0 list                # 列出所有任务"
    echo "  $0 enable              # 启用任务"
    echo "  $0 status              # 查看状态"
    echo
}

# 列出所有定时任务
list_schedules() {
    log_info "列出所有 Salt 定时任务..."
    echo
    salt-call --local schedule.list
}

# 启用 SaltGoat 定时任务
enable_schedules() {
    log_info "启用 SaltGoat 定时任务..."
    
    # 应用调度配置
    salt-call --local state.apply schedules.saltgoat
    
    if [[ $? -eq 0 ]]; then
        log_success "SaltGoat 定时任务已启用"
    else
        log_error "启用定时任务失败"
        return 1
    fi
}

# 禁用 SaltGoat 定时任务
disable_schedules() {
    log_info "禁用 SaltGoat 定时任务..."
    
    # 删除调度配置
    salt-call --local schedule.delete memory_monitor
    salt-call --local schedule.delete system_update
    salt-call --local schedule.delete log_cleanup
    salt-call --local schedule.delete database_backup
    salt-call --local schedule.delete service_health_check
    salt-call --local schedule.delete disk_space_check
    salt-call --local schedule.delete security_updates
    
    log_success "SaltGoat 定时任务已禁用"
}

# 查看定时任务状态
show_status() {
    log_info "查看定时任务状态..."
    echo
    
    # 检查 SaltGoat 相关任务
    local tasks=("memory_monitor" "system_update" "log_cleanup" "database_backup" "service_health_check" "disk_space_check" "security_updates")
    
    for task in "${tasks[@]}"; do
        echo "任务: $task"
        salt-call --local schedule.show "$task" 2>/dev/null || echo "  未配置"
        echo
    done
}

# 查看定时任务日志
show_logs() {
    log_info "查看定时任务日志..."
    echo
    
    # 查看 Salt 日志
    if [[ -f /var/log/salt/minion ]]; then
        echo "=== Salt Minion 日志 ==="
        tail -20 /var/log/salt/minion
        echo
    fi
    
    # 查看 SaltGoat 日志
    if [[ -d /var/log/saltgoat ]]; then
        echo "=== SaltGoat 日志 ==="
        ls -la /var/log/saltgoat/
        echo
    fi
}

# 测试定时任务配置
test_schedules() {
    log_info "测试定时任务配置..."
    echo
    
    # 测试内存监控
    log_info "测试内存监控..."
    /usr/local/bin/saltgoat-memory-monitor
    echo
    
    # 测试服务状态
    log_info "测试服务状态..."
    salt-call --local service.status nginx mysql php8.3-fpm valkey opensearch rabbitmq
    echo
    
    # 测试磁盘使用
    log_info "测试磁盘使用..."
    salt-call --local disk.usage
    echo
    
    log_success "定时任务配置测试完成"
}

# 主函数
main() {
    case "${1:-help}" in
        "list")
            list_schedules
            ;;
        "enable")
            enable_schedules
            ;;
        "disable")
            disable_schedules
            ;;
        "status")
            show_status
            ;;
        "logs")
            show_logs
            ;;
        "test")
            test_schedules
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            log_error "未知命令: $1"
            echo
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"

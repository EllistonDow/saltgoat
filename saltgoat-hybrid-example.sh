#!/bin/bash
# SaltGoat 主入口脚本 - 混合模式设计

set -e

# 脚本信息
SCRIPT_NAME="SaltGoat"
SCRIPT_VERSION="0.1.3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载公共库
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/config.sh"

# 加载核心功能
source "${SCRIPT_DIR}/core/install.sh"
source "${SCRIPT_DIR}/core/system.sh"
source "${SCRIPT_DIR}/core/optimize.sh"

# 加载服务管理
source "${SCRIPT_DIR}/services/mysql.sh"
source "${SCRIPT_DIR}/services/nginx.sh"
source "${SCRIPT_DIR}/services/rabbitmq.sh"

# 加载监控功能
source "${SCRIPT_DIR}/monitoring/memory.sh"
source "${SCRIPT_DIR}/monitoring/schedule.sh"

# 主命令路由
main() {
    # 显示横幅
    show_banner
    
    # 检查权限
    check_permissions "$@"
    
    # 解析参数
    parse_arguments "$@"
    
    # 执行命令
    case "$1" in
        "install")
            install_handler "$@"
            ;;
        "system")
            system_handler "$@"
            ;;
        "mysql")
            mysql_handler "$@"
            ;;
        "nginx")
            nginx_handler "$@"
            ;;
        "rabbitmq")
            rabbitmq_handler "$@"
            ;;
        "memory")
            memory_handler "$@"
            ;;
        "schedule")
            schedule_handler "$@"
            ;;
        "optimize")
            optimize_handler "$@"
            ;;
        "status"|"versions"|"passwords")
            info_handler "$@"
            ;;
        "help"|"--help"|"-h"|"")
            show_help
            ;;
        *)
            log_error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 显示横幅
show_banner() {
    echo "=========================================="
    echo "    $SCRIPT_NAME 简化安装脚本 v$SCRIPT_VERSION"
    echo "=========================================="
}

# 执行主函数
main "$@"

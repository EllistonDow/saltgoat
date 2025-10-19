#!/bin/bash

# SaltGoat RabbitMQ 多站点管理脚本
# 用于创建和管理多个站点的 RabbitMQ 用户和虚拟主机

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

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        exit 1
    fi
}

# 加载环境变量
load_env() {
    # 使用默认密码或从 Salt Pillars 获取
    RABBITMQ_ADMIN_PASSWORD=${RABBITMQ_ADMIN_PASSWORD:-"RabbitMQ2024!"}
    
    if [[ -z "$RABBITMQ_ADMIN_PASSWORD" ]]; then
        log_error "RABBITMQ_ADMIN_PASSWORD 未设置，请使用环境变量或 Salt Pillars"
        exit 1
    fi
}

# 检查 RabbitMQ 服务状态
check_rabbitmq() {
    if ! systemctl is-active --quiet rabbitmq-server; then
        log_error "RabbitMQ 服务未运行，请先启动服务"
        exit 1
    fi
}

# 创建站点用户和虚拟主机
create_site() {
    local site_name="$1"
    local site_password="$2"
    
    if [[ -z "$site_name" ]] || [[ -z "$site_password" ]]; then
        log_error "用法: $0 create <site_name> <password>"
        exit 1
    fi
    
    log_info "为站点 $site_name 创建 RabbitMQ 用户和虚拟主机..."
    
    # 创建虚拟主机
    rabbitmqctl add_vhost "$site_name"
    
    # 创建用户
    rabbitmqctl add_user "$site_name" "$site_password"
    
    # 设置用户权限
    rabbitmqctl set_permissions -p "$site_name" "$site_name" ".*" ".*" ".*"
    
    # 设置用户标签
    rabbitmqctl set_user_tags "$site_name" management
    
    log_success "站点 $site_name 创建成功"
    echo "虚拟主机: ${site_name}"
    echo "用户名: ${site_name}"
    echo "密码: ${site_password}"
    echo "管理界面: http://your-server-ip:15672"
}

# 删除站点
delete_site() {
    local site_name="$1"
    
    if [[ -z "$site_name" ]]; then
        log_error "用法: $0 delete <site_name>"
        exit 1
    fi
    
    log_warning "确定要删除站点 $site_name 吗？这将删除用户和虚拟主机！"
    read -p "输入 'yes' 确认: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "操作已取消"
        exit 0
    fi
    
    log_info "删除站点 $site_name..."
    
    # 删除用户权限
    rabbitmqctl clear_permissions -p "$site_name" "$site_name"
    
    # 删除用户
    rabbitmqctl delete_user "$site_name"
    
    # 删除虚拟主机
    rabbitmqctl delete_vhost "$site_name"
    
    log_success "站点 $site_name 删除成功"
}

# 列出所有站点
list_sites() {
    log_info "列出所有站点用户和虚拟主机..."
    
    echo "=== 虚拟主机列表 ==="
    rabbitmqctl list_vhosts
    
    echo ""
    echo "=== 用户列表 ==="
    rabbitmqctl list_users
    
    echo ""
    echo "=== 用户权限列表 ==="
    rabbitmqctl list_permissions
}

# 重置站点密码
reset_password() {
    local site_name="$1"
    local new_password="$2"
    
    if [[ -z "$site_name" ]] || [[ -z "$new_password" ]]; then
        log_error "用法: $0 reset-password <site_name> <new_password>"
        exit 1
    fi
    
    log_info "重置站点 $site_name 的密码..."
    
    rabbitmqctl change_password "$site_name" "$new_password"
    
    log_success "站点 $site_name 密码重置成功"
    echo "新密码: ${new_password}"
}

# 设置用户权限
set_permissions() {
    local site_name="$1"
    local vhost="$2"
    local configure="$3"
    local write="$4"
    local read="$5"
    
    if [[ -z "$site_name" ]] || [[ -z "$vhost" ]]; then
        log_error "用法: $0 set-permissions <site_name> <vhost> [configure] [write] [read]"
        log_info "默认权限: configure='.*' write='.*' read='.*'"
        exit 1
    fi
    
    configure="${configure:-.*}"
    write="${write:-.*}"
    read="${read:-.*}"
    
    log_info "设置站点 $site_name 在虚拟主机 $vhost 的权限..."
    
    rabbitmqctl set_permissions -p "$vhost" "$site_name" "$configure" "$write" "$read"
    
    log_success "权限设置成功"
}

# 清除用户权限
clear_permissions() {
    local site_name="$1"
    local vhost="$2"
    
    if [[ -z "$site_name" ]] || [[ -z "$vhost" ]]; then
        log_error "用法: $0 clear-permissions <site_name> <vhost>"
        exit 1
    fi
    
    log_info "清除站点 $site_name 在虚拟主机 $vhost 的权限..."
    
    rabbitmqctl clear_permissions -p "$vhost" "$site_name"
    
    log_success "权限清除成功"
}

# 显示站点状态
show_status() {
    local site_name="$1"
    
    if [[ -z "$site_name" ]]; then
        log_error "用法: $0 status <site_name>"
        exit 1
    fi
    
    log_info "显示站点 $site_name 的状态..."
    
    echo "=== 用户信息 ==="
    rabbitmqctl list_users | grep "$site_name" || echo "用户不存在"
    
    echo ""
    echo "=== 虚拟主机信息 ==="
    rabbitmqctl list_vhosts | grep "$site_name" || echo "虚拟主机不存在"
    
    echo ""
    echo "=== 权限信息 ==="
    rabbitmqctl list_permissions | grep "$site_name" || echo "无权限信息"
    
    echo ""
    echo "=== 队列信息 ==="
    rabbitmqctl list_queues -p "$site_name" || echo "无队列信息"
    
    echo ""
    echo "=== 交换器信息 ==="
    rabbitmqctl list_exchanges -p "$site_name" || echo "无交换器信息"
}

# 显示帮助信息
show_help() {
    echo "SaltGoat RabbitMQ 多站点管理脚本"
    echo ""
    echo "用法: $0 <command> [options]"
    echo ""
    echo "命令:"
    echo "  create <site_name> <password>                    - 创建新站点用户和虚拟主机"
    echo "  delete <site_name>                               - 删除站点用户和虚拟主机"
    echo "  list                                            - 列出所有站点"
    echo "  reset-password <site_name> <new_password>       - 重置站点密码"
    echo "  set-permissions <site> <vhost> [conf] [write] [read] - 设置用户权限"
    echo "  clear-permissions <site_name> <vhost>           - 清除用户权限"
    echo "  status <site_name>                              - 显示站点状态"
    echo "  help                                            - 显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 create mysite mypassword"
    echo "  $0 list"
    echo "  $0 set-permissions mysite mysite"
    echo "  $0 status mysite"
}

# 主函数
main() {
    check_root
    load_env
    check_rabbitmq
    
    case "${1:-help}" in
        "create")
            create_site "$2" "$3"
            ;;
        "delete")
            delete_site "$2"
            ;;
        "list")
            list_sites
            ;;
        "reset-password")
            reset_password "$2" "$3"
            ;;
        "set-permissions")
            set_permissions "$2" "$3" "$4" "$5" "$6"
            ;;
        "clear-permissions")
            clear_permissions "$2" "$3"
            ;;
        "status")
            show_status "$2"
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "无效的命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"

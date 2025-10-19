#!/bin/bash

# SaltGoat MySQL 多站点管理脚本
# 用于创建和管理多个站点的数据库用户和数据库

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
    MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-"SaltGoat2024!"}
    
    if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
        log_error "MYSQL_ROOT_PASSWORD 未设置，请使用环境变量或 Salt Pillars"
        exit 1
    fi
}

# 创建站点数据库和用户
create_site() {
    local site_name="$1"
    local site_password="$2"
    
    if [[ -z "$site_name" ]] || [[ -z "$site_password" ]]; then
        log_error "用法: $0 create <site_name> <password>"
        exit 1
    fi
    
    log_info "为站点 $site_name 创建数据库和用户..."
    
    # 创建数据库
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS \`${site_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    
    # 创建用户
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE USER IF NOT EXISTS '${site_name}'@'localhost' IDENTIFIED BY '${site_password}';"
    
    # 授权
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON \`${site_name}\`.* TO '${site_name}'@'localhost';"
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"
    
    log_success "站点 $site_name 创建成功"
    echo "数据库: ${site_name}"
    echo "用户名: ${site_name}"
    echo "密码: ${site_password}"
    echo "主机: localhost"
}

# 删除站点
delete_site() {
    local site_name="$1"
    
    if [[ -z "$site_name" ]]; then
        log_error "用法: $0 delete <site_name>"
        exit 1
    fi
    
    log_warning "确定要删除站点 $site_name 吗？这将删除数据库和用户！"
    read -p "输入 'yes' 确认: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "操作已取消"
        exit 0
    fi
    
    log_info "删除站点 $site_name..."
    
    # 删除用户
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "DROP USER IF EXISTS '${site_name}'@'localhost';"
    
    # 删除数据库
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS \`${site_name}\`;"
    
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"
    
    log_success "站点 $site_name 删除成功"
}

# 列出所有站点
list_sites() {
    log_info "列出所有站点数据库和用户..."
    
    echo "=== 数据库列表 ==="
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES;" | grep -v -E "(Database|information_schema|performance_schema|mysql|sys)"
    
    echo ""
    echo "=== 用户列表 ==="
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT User, Host FROM mysql.user WHERE User != 'root' AND User != 'mysql.session' AND User != 'mysql.sys' AND User != 'debian-sys-maint';"
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
    
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "ALTER USER '${site_name}'@'localhost' IDENTIFIED BY '${new_password}';"
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"
    
    log_success "站点 $site_name 密码重置成功"
    echo "新密码: ${new_password}"
}

# 备份站点数据库
backup_site() {
    local site_name="$1"
    local backup_file="$2"
    
    if [[ -z "$site_name" ]]; then
        log_error "用法: $0 backup <site_name> [backup_file]"
        exit 1
    fi
    
    if [[ -z "$backup_file" ]]; then
        backup_file="/var/backups/mysql/${site_name}_$(date +%Y%m%d_%H%M%S).sql"
    fi
    
    log_info "备份站点 $site_name 到 $backup_file..."
    
    # 创建备份目录
    mkdir -p "$(dirname "$backup_file")"
    
    # 备份数据库
    mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" --single-transaction --routines --triggers "$site_name" > "$backup_file"
    
    log_success "备份完成: $backup_file"
}

# 恢复站点数据库
restore_site() {
    local site_name="$1"
    local backup_file="$2"
    
    if [[ -z "$site_name" ]] || [[ -z "$backup_file" ]]; then
        log_error "用法: $0 restore <site_name> <backup_file>"
        exit 1
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "备份文件不存在: $backup_file"
        exit 1
    fi
    
    log_warning "确定要恢复站点 $site_name 吗？这将覆盖现有数据！"
    read -p "输入 'yes' 确认: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "操作已取消"
        exit 0
    fi
    
    log_info "恢复站点 $site_name 从 $backup_file..."
    
    mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$site_name" < "$backup_file"
    
    log_success "恢复完成"
}

# 显示帮助信息
show_help() {
    echo "SaltGoat MySQL 多站点管理脚本"
    echo ""
    echo "用法: $0 <command> [options]"
    echo ""
    echo "命令:"
    echo "  create <site_name> <password>     - 创建新站点数据库和用户"
    echo "  delete <site_name>                 - 删除站点数据库和用户"
    echo "  list                              - 列出所有站点"
    echo "  reset-password <site_name> <pass>  - 重置站点密码"
    echo "  backup <site_name> [file]         - 备份站点数据库"
    echo "  restore <site_name> <file>        - 恢复站点数据库"
    echo "  help                              - 显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 create mysite mypassword"
    echo "  $0 list"
    echo "  $0 backup mysite"
    echo "  $0 restore mysite /var/backups/mysql/mysite_20231201_120000.sql"
}

# 主函数
main() {
    check_root
    load_env
    
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
        "backup")
            backup_site "$2" "$3"
            ;;
        "restore")
            restore_site "$2" "$3"
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

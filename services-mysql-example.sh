#!/bin/bash
# MySQL 服务管理模块

# MySQL 处理函数
mysql_handler() {
    case "$2" in
        "create")
            if [[ -z "$3" || -z "$4" || -z "$5" ]]; then
                log_error "用法: saltgoat mysql create <dbname> <username> <password>"
                log_info "示例: saltgoat mysql create hawkmage hawk 'hawk.2010'"
                exit 1
            fi
            log_highlight "创建 MySQL 数据库和用户: $3 / $4"
            mysql_create_site "$3" "$4" "$5"
            ;;
        "list")
            log_highlight "列出所有 MySQL 数据库..."
            mysql_list_sites
            ;;
        "backup")
            if [[ -z "$3" ]]; then
                log_error "用法: saltgoat mysql backup <dbname>"
                exit 1
            fi
            log_highlight "备份数据库: $3"
            mysql_backup_site "$3"
            ;;
        "delete")
            if [[ -z "$3" ]]; then
                log_error "用法: saltgoat mysql delete <dbname>"
                exit 1
            fi
            log_highlight "删除数据库: $3"
            mysql_delete_site "$3"
            ;;
        *)
            log_error "未知的 MySQL 操作: $2"
            log_info "支持: create, list, backup, delete"
            exit 1
            ;;
    esac
}

# 创建 MySQL 数据库和用户
mysql_create_site() {
    local dbname="$1"
    local username="$2"
    local password="$3"
    
    log_info "创建数据库: $dbname"
    salt-call --local mysql.db_create "$dbname"
    
    log_info "创建用户: $username"
    salt-call --local mysql.user_create "$username" password="$password" auth_plugin="caching_sha2_password"
    
    log_info "授权用户访问数据库"
    salt-call --local mysql.grant_add "$username" "$dbname" "ALL PRIVILEGES"
    
    log_success "MySQL 数据库和用户创建成功: $dbname / $username"
}

# 列出所有数据库
mysql_list_sites() {
    salt-call --local mysql.db_list
}

# 备份数据库
mysql_backup_site() {
    local dbname="$1"
    local backup_file="/backup/${dbname}_$(date +%Y%m%d_%H%M%S).sql"
    
    log_info "备份数据库到: $backup_file"
    salt-call --local cmd.run "mysqldump $dbname > $backup_file"
    
    log_success "数据库备份完成: $backup_file"
}

# 删除数据库
mysql_delete_site() {
    local dbname="$1"
    
    log_warning "删除数据库: $dbname"
    salt-call --local mysql.db_remove "$dbname"
    
    log_success "数据库删除成功: $dbname"
}

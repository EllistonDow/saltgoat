#!/bin/bash
# 数据库管理模块 - 完全 Salt 原生功能
# services/database.sh

# 数据库配置
DB_BACKUP_DIR="/var/backups/databases"
DB_LOG_DIR="/var/log/saltgoat/database"
DB_CONFIG_DIR="/etc/saltgoat/database"

# 确保数据库目录存在
ensure_database_dirs() {
    salt-call --local file.mkdir "$DB_BACKUP_DIR" >/dev/null 2>&1 || true
    salt-call --local file.mkdir "$DB_LOG_DIR" >/dev/null 2>&1 || true
    salt-call --local file.mkdir "$DB_CONFIG_DIR" >/dev/null 2>&1 || true
    
    # 创建 MySQL 配置文件以避免密码警告
    local mysql_config="[client]
user=root
password=MyPass123!"
    local mysql_config_file="/home/$USER/.my.cnf"
    echo "$mysql_config" > "$mysql_config_file"
    chmod 600 "$mysql_config_file"
}

# 数据库连接测试
database_test_connection() {
    local db_type="$1"
    local host="${2:-localhost}"
    local port="${3:-3306}"
    local username="${4:-root}"
    local password="${5:-MyPass123!}"
    
    if [[ -z "$db_type" ]]; then
        log_error "用法: saltgoat database test-connection <type> [host] [port] [username] [password]"
        log_info "支持类型: mysql, postgresql, mongodb, redis"
        log_info "示例: saltgoat database test-connection mysql localhost 3306 root password"
        exit 1
    fi
    
    log_highlight "测试数据库连接: $db_type ($host:$port)"
    
    case "$db_type" in
        "mysql")
            log_info "测试 MySQL 连接..."
            if salt-call --local cmd.run "mysql --defaults-file=/home/$USER/.my.cnf -h $host -P $port -e 'SELECT 1;'" >/dev/null 2>&1; then
                log_success "MySQL 连接成功"
            else
                log_error "MySQL 连接失败"
                exit 1
            fi
            ;;
        "postgresql")
            log_info "测试 PostgreSQL 连接..."
            if salt-call --local cmd.run "psql -h $host -p $port -U $username -d postgres -c 'SELECT 1;'" >/dev/null 2>&1; then
                log_success "PostgreSQL 连接成功"
            else
                log_error "PostgreSQL 连接失败"
                exit 1
            fi
            ;;
        "mongodb")
            log_info "测试 MongoDB 连接..."
            if salt-call --local cmd.run "mongosh --host $host --port $port --username $username --password $password --eval 'db.runCommand({ping: 1})'" >/dev/null 2>&1; then
                log_success "MongoDB 连接成功"
            else
                log_error "MongoDB 连接失败"
                exit 1
            fi
            ;;
        "redis")
            log_info "测试 Redis 连接..."
            if salt-call --local cmd.run "redis-cli -h $host -p $port -a $password ping" >/dev/null 2>&1; then
                log_success "Redis 连接成功"
            else
                log_error "Redis 连接失败"
                exit 1
            fi
            ;;
        *)
            log_error "不支持的数据库类型: $db_type"
            log_info "支持类型: mysql, postgresql, mongodb, redis"
            exit 1
            ;;
    esac
}

# 数据库状态检查
database_status() {
    local db_type="$1"
    
    if [[ -z "$db_type" ]]; then
        log_error "用法: saltgoat database status <type>"
        log_info "支持类型: mysql, postgresql, mongodb, redis"
        exit 1
    fi
    
    log_highlight "检查数据库状态: $db_type"
    
    case "$db_type" in
        "mysql")
            log_info "MySQL 状态检查..."
            
            # 检查服务状态
            local service_status=$(salt-call --local service.status mysql --out=txt 2>/dev/null | tail -n 1)
            if [[ "$service_status" == "local: True" ]]; then
                log_success "MySQL 服务正在运行"
            else
                log_error "MySQL 服务未运行"
                exit 1
            fi
            
            # 检查版本
            local version=$(salt-call --local cmd.run "mysql --defaults-file=/home/$USER/.my.cnf --version" 2>/dev/null)
            echo "MySQL 版本: $version"
            
            # 检查连接数
            local connections=$(salt-call --local cmd.run "mysql --defaults-file=/home/$USER/.my.cnf -e 'SHOW STATUS LIKE \"Threads_connected\";'" 2>/dev/null)
            echo "当前连接数: $connections"
            
            # 检查数据库列表
            local databases=$(salt-call --local cmd.run "mysql --defaults-file=/home/$USER/.my.cnf -e 'SHOW DATABASES;'" 2>/dev/null)
            echo "数据库列表:"
            echo "$databases"
            ;;
        "postgresql")
            log_info "PostgreSQL 状态检查..."
            
            # 检查服务状态
            local service_status=$(salt-call --local service.status postgresql --out=txt 2>/dev/null | tail -n 1)
            if [[ "$service_status" == "local: True" ]]; then
                log_success "PostgreSQL 服务正在运行"
            else
                log_error "PostgreSQL 服务未运行"
                exit 1
            fi
            
            # 检查版本
            local version=$(salt-call --local cmd.run "psql --version" 2>/dev/null)
            echo "PostgreSQL 版本: $version"
            
            # 检查连接数
            local connections=$(salt-call --local cmd.run "psql -U postgres -d postgres -c 'SELECT count(*) FROM pg_stat_activity;'" 2>/dev/null)
            echo "当前连接数: $connections"
            ;;
        "mongodb")
            log_info "MongoDB 状态检查..."
            
            # 检查服务状态
            local service_status=$(salt-call --local service.status mongodb --out=txt 2>/dev/null | tail -n 1)
            if [[ "$service_status" == "local: True" ]]; then
                log_success "MongoDB 服务正在运行"
            else
                log_error "MongoDB 服务未运行"
                exit 1
            fi
            
            # 检查版本
            local version=$(salt-call --local cmd.run "mongosh --version" 2>/dev/null)
            echo "MongoDB 版本: $version"
            
            # 检查连接数
            local connections=$(salt-call --local cmd.run "mongosh --eval 'db.serverStatus().connections'" 2>/dev/null)
            echo "连接信息: $connections"
            ;;
        "redis")
            log_info "Redis 状态检查..."
            
            # 检查服务状态
            local service_status=$(salt-call --local service.status redis --out=txt 2>/dev/null | tail -n 1)
            if [[ "$service_status" == "local: True" ]]; then
                log_success "Redis 服务正在运行"
            else
                log_error "Redis 服务未运行"
                exit 1
            fi
            
            # 检查版本
            local version=$(salt-call --local cmd.run "redis-server --version" 2>/dev/null)
            echo "Redis 版本: $version"
            
            # 检查连接数
            local connections=$(salt-call --local cmd.run "redis-cli info clients" 2>/dev/null)
            echo "连接信息: $connections"
            ;;
        *)
            log_error "不支持的数据库类型: $db_type"
            log_info "支持类型: mysql, postgresql, mongodb, redis"
            exit 1
            ;;
    esac
}

# 数据库备份
database_backup() {
    local db_type="$1"
    local db_name="$2"
    local backup_name="$3"
    
    if [[ -z "$db_type" || -z "$db_name" ]]; then
        log_error "用法: saltgoat database backup <type> <database_name> [backup_name]"
        log_info "支持类型: mysql, postgresql, mongodb"
        log_info "示例: saltgoat database backup mysql mydb mydb_backup"
        exit 1
    fi
    
    if [[ -z "$backup_name" ]]; then
        backup_name="${db_name}_$(date +%Y%m%d_%H%M%S)"
    fi
    
    log_highlight "备份数据库: $db_type/$db_name -> $backup_name"
    ensure_database_dirs
    
    local backup_file="$DB_BACKUP_DIR/${backup_name}.sql"
    
    case "$db_type" in
        "mysql")
            log_info "备份 MySQL 数据库..."
            if salt-call --local cmd.run "mysqldump -u root -p'MyPass123!' $db_name > $backup_file" >/dev/null 2>&1; then
                log_success "MySQL 数据库备份完成: $backup_file"
            else
                log_error "MySQL 数据库备份失败"
                exit 1
            fi
            ;;
        "postgresql")
            log_info "备份 PostgreSQL 数据库..."
            if salt-call --local cmd.run "pg_dump -U postgres $db_name > $backup_file" >/dev/null 2>&1; then
                log_success "PostgreSQL 数据库备份完成: $backup_file"
            else
                log_error "PostgreSQL 数据库备份失败"
                exit 1
            fi
            ;;
        "mongodb")
            log_info "备份 MongoDB 数据库..."
            local backup_dir="$DB_BACKUP_DIR/${backup_name}"
            salt-call --local file.mkdir "$backup_dir" >/dev/null 2>&1
            if salt-call --local cmd.run "mongodump --db $db_name --out $backup_dir" >/dev/null 2>&1; then
                log_success "MongoDB 数据库备份完成: $backup_dir"
            else
                log_error "MongoDB 数据库备份失败"
                exit 1
            fi
            ;;
        *)
            log_error "不支持的数据库类型: $db_type"
            log_info "支持类型: mysql, postgresql, mongodb"
            exit 1
            ;;
    esac
    
    # 创建备份信息文件
    local backup_info="数据库备份信息
==================
备份类型: $db_type
数据库名: $db_name
备份名称: $backup_name
备份时间: $(date)
备份文件: $backup_file"
    
    salt-call --local file.write "$DB_BACKUP_DIR/${backup_name}_info.txt" contents="$backup_info" >/dev/null 2>&1
}

# 数据库恢复
database_restore() {
    local db_type="$1"
    local db_name="$2"
    local backup_file="$3"
    
    if [[ -z "$db_type" || -z "$db_name" || -z "$backup_file" ]]; then
        log_error "用法: saltgoat database restore <type> <database_name> <backup_file>"
        log_info "支持类型: mysql, postgresql, mongodb"
        log_info "示例: saltgoat database restore mysql mydb /var/backups/databases/mydb_backup.sql"
        exit 1
    fi
    
    log_highlight "恢复数据库: $db_type/$db_name <- $backup_file"
    
    # 检查备份文件是否存在
    if ! salt-call --local file.file_exists "$backup_file" --out=txt 2>/dev/null | grep -q "True"; then
        log_error "备份文件不存在: $backup_file"
        exit 1
    fi
    
    log_warning "这将覆盖目标数据库，请确认是否继续？"
    read -p "输入 'yes' 确认继续: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "恢复操作已取消"
        exit 0
    fi
    
    case "$db_type" in
        "mysql")
            log_info "恢复 MySQL 数据库..."
            if salt-call --local cmd.run "mysql -u root -p'MyPass123!' $db_name < $backup_file" >/dev/null 2>&1; then
                log_success "MySQL 数据库恢复完成"
            else
                log_error "MySQL 数据库恢复失败"
                exit 1
            fi
            ;;
        "postgresql")
            log_info "恢复 PostgreSQL 数据库..."
            if salt-call --local cmd.run "psql -U postgres $db_name < $backup_file" >/dev/null 2>&1; then
                log_success "PostgreSQL 数据库恢复完成"
            else
                log_error "PostgreSQL 数据库恢复失败"
                exit 1
            fi
            ;;
        "mongodb")
            log_info "恢复 MongoDB 数据库..."
            if salt-call --local cmd.run "mongorestore --db $db_name $backup_file" >/dev/null 2>&1; then
                log_success "MongoDB 数据库恢复完成"
            else
                log_error "MongoDB 数据库恢复失败"
                exit 1
            fi
            ;;
        *)
            log_error "不支持的数据库类型: $db_type"
            log_info "支持类型: mysql, postgresql, mongodb"
            exit 1
            ;;
    esac
}

# 数据库性能监控
database_performance() {
    local db_type="$1"
    
    if [[ -z "$db_type" ]]; then
        log_error "用法: saltgoat database performance <type>"
        log_info "支持类型: mysql, postgresql, mongodb, redis"
        exit 1
    fi
    
    log_highlight "数据库性能监控: $db_type"
    
    case "$db_type" in
        "mysql")
            log_info "MySQL 性能监控..."
            
            echo "连接统计:"
            echo "----------------------------------------"
            local connections=$(salt-call --local cmd.run "mysql -u root -p'MyPass123!' -e 'SHOW STATUS LIKE \"Connections\";'" 2>/dev/null)
            echo "$connections"
            
            local max_connections=$(salt-call --local cmd.run "mysql -u root -p'MyPass123!' -e 'SHOW STATUS LIKE \"Max_used_connections\";'" 2>/dev/null)
            echo "$max_connections"
            
            echo ""
            echo "查询统计:"
            echo "----------------------------------------"
            local queries=$(salt-call --local cmd.run "mysql -u root -p'MyPass123!' -e 'SHOW STATUS LIKE \"Queries\";'" 2>/dev/null)
            echo "$queries"
            
            local slow_queries=$(salt-call --local cmd.run "mysql -u root -p'MyPass123!' -e 'SHOW STATUS LIKE \"Slow_queries\";'" 2>/dev/null)
            echo "$slow_queries"
            
            echo ""
            echo "缓存统计:"
            echo "----------------------------------------"
            local cache_hits=$(salt-call --local cmd.run "mysql -u root -p'MyPass123!' -e 'SHOW STATUS LIKE \"Qcache_hits\";'" 2>/dev/null)
            echo "$cache_hits"
            
            local cache_misses=$(salt-call --local cmd.run "mysql -u root -p'MyPass123!' -e 'SHOW STATUS LIKE \"Qcache_misses\";'" 2>/dev/null)
            echo "$cache_misses"
            ;;
        "postgresql")
            log_info "PostgreSQL 性能监控..."
            
            echo "连接统计:"
            echo "----------------------------------------"
            local connections=$(salt-call --local cmd.run "psql -U postgres -d postgres -c 'SELECT count(*) as active_connections FROM pg_stat_activity;'" 2>/dev/null)
            echo "$connections"
            
            echo ""
            echo "查询统计:"
            echo "----------------------------------------"
            local queries=$(salt-call --local cmd.run "psql -U postgres -d postgres -c 'SELECT * FROM pg_stat_database;'" 2>/dev/null)
            echo "$queries"
            ;;
        "mongodb")
            log_info "MongoDB 性能监控..."
            
            echo "连接统计:"
            echo "----------------------------------------"
            local connections=$(salt-call --local cmd.run "mongosh --eval 'db.serverStatus().connections'" 2>/dev/null)
            echo "$connections"
            
            echo ""
            echo "操作统计:"
            echo "----------------------------------------"
            local operations=$(salt-call --local cmd.run "mongosh --eval 'db.serverStatus().opcounters'" 2>/dev/null)
            echo "$operations"
            ;;
        "redis")
            log_info "Redis 性能监控..."
            
            echo "连接统计:"
            echo "----------------------------------------"
            local connections=$(salt-call --local cmd.run "redis-cli info clients" 2>/dev/null)
            echo "$connections"
            
            echo ""
            echo "内存统计:"
            echo "----------------------------------------"
            local memory=$(salt-call --local cmd.run "redis-cli info memory" 2>/dev/null)
            echo "$memory"
            
            echo ""
            echo "操作统计:"
            echo "----------------------------------------"
            local stats=$(salt-call --local cmd.run "redis-cli info stats" 2>/dev/null)
            echo "$stats"
            ;;
        *)
            log_error "不支持的数据库类型: $db_type"
            log_info "支持类型: mysql, postgresql, mongodb, redis"
            exit 1
            ;;
    esac
}

# 数据库用户管理
database_user_management() {
    local db_type="$1"
    local action="$2"
    local username="$3"
    local password="${4:-}"
    local database="${5:-}"
    
    if [[ -z "$db_type" || -z "$action" ]]; then
        log_error "用法: saltgoat database user <type> <action> [username] [password] [database]"
        log_info "支持类型: mysql, postgresql"
        log_info "支持操作: create, delete, list, grant"
        log_info "示例: saltgoat database user mysql create testuser password123 mydb"
        exit 1
    fi
    
    log_highlight "数据库用户管理: $db_type/$action"
    
    case "$db_type" in
        "mysql")
            case "$action" in
                "create")
                    if [[ -z "$username" || -z "$password" ]]; then
                        log_error "创建用户需要用户名和密码"
                        exit 1
                    fi
                    log_info "创建 MySQL 用户: $username"
                    if salt-call --local cmd.run "mysql -u root -p'MyPass123!' -e \"CREATE USER '$username'@'localhost' IDENTIFIED BY '$password';\"" >/dev/null 2>&1; then
                        log_success "MySQL 用户创建成功: $username"
                    else
                        log_error "MySQL 用户创建失败"
                        exit 1
                    fi
                    ;;
                "delete")
                    if [[ -z "$username" ]]; then
                        log_error "删除用户需要用户名"
                        exit 1
                    fi
                    log_info "删除 MySQL 用户: $username"
                    if salt-call --local cmd.run "mysql -u root -p'MyPass123!' -e \"DROP USER '$username'@'localhost';\"" >/dev/null 2>&1; then
                        log_success "MySQL 用户删除成功: $username"
                    else
                        log_error "MySQL 用户删除失败"
                        exit 1
                    fi
                    ;;
                "list")
                    log_info "列出 MySQL 用户..."
                    local users=$(salt-call --local cmd.run "mysql -u root -p'MyPass123!' -e 'SELECT User, Host FROM mysql.user;'" 2>/dev/null)
                    echo "$users"
                    ;;
                "grant")
                    if [[ -z "$username" || -z "$database" ]]; then
                        log_error "授权需要用户名和数据库名"
                        exit 1
                    fi
                    log_info "授权 MySQL 用户: $username -> $database"
                    if salt-call --local cmd.run "mysql -u root -p'MyPass123!' -e \"GRANT ALL PRIVILEGES ON $database.* TO '$username'@'localhost';\"" >/dev/null 2>&1; then
                        log_success "MySQL 用户授权成功: $username -> $database"
                    else
                        log_error "MySQL 用户授权失败"
                        exit 1
                    fi
                    ;;
                *)
                    log_error "不支持的 MySQL 操作: $action"
                    log_info "支持操作: create, delete, list, grant"
                    exit 1
                    ;;
            esac
            ;;
        "postgresql")
            case "$action" in
                "create")
                    if [[ -z "$username" || -z "$password" ]]; then
                        log_error "创建用户需要用户名和密码"
                        exit 1
                    fi
                    log_info "创建 PostgreSQL 用户: $username"
                    if salt-call --local cmd.run "psql -U postgres -d postgres -c \"CREATE USER $username WITH PASSWORD '$password';\"" >/dev/null 2>&1; then
                        log_success "PostgreSQL 用户创建成功: $username"
                    else
                        log_error "PostgreSQL 用户创建失败"
                        exit 1
                    fi
                    ;;
                "delete")
                    if [[ -z "$username" ]]; then
                        log_error "删除用户需要用户名"
                        exit 1
                    fi
                    log_info "删除 PostgreSQL 用户: $username"
                    if salt-call --local cmd.run "psql -U postgres -d postgres -c \"DROP USER $username;\"" >/dev/null 2>&1; then
                        log_success "PostgreSQL 用户删除成功: $username"
                    else
                        log_error "PostgreSQL 用户删除失败"
                        exit 1
                    fi
                    ;;
                "list")
                    log_info "列出 PostgreSQL 用户..."
                    local users=$(salt-call --local cmd.run "psql -U postgres -d postgres -c '\\du'" 2>/dev/null)
                    echo "$users"
                    ;;
                "grant")
                    if [[ -z "$username" || -z "$database" ]]; then
                        log_error "授权需要用户名和数据库名"
                        exit 1
                    fi
                    log_info "授权 PostgreSQL 用户: $username -> $database"
                    if salt-call --local cmd.run "psql -U postgres -d postgres -c \"GRANT ALL PRIVILEGES ON DATABASE $database TO $username;\"" >/dev/null 2>&1; then
                        log_success "PostgreSQL 用户授权成功: $username -> $database"
                    else
                        log_error "PostgreSQL 用户授权失败"
                        exit 1
                    fi
                    ;;
                *)
                    log_error "不支持的 PostgreSQL 操作: $action"
                    log_info "支持操作: create, delete, list, grant"
                    exit 1
                    ;;
            esac
            ;;
        *)
            log_error "不支持的数据库类型: $db_type"
            log_info "支持类型: mysql, postgresql"
            exit 1
            ;;
    esac
}

# 数据库维护
database_maintenance() {
    local db_type="$1"
    local action="$2"
    local database="${3:-}"
    
    if [[ -z "$db_type" || -z "$action" ]]; then
        log_error "用法: saltgoat database maintenance <type> <action> [database]"
        log_info "支持类型: mysql, postgresql"
        log_info "支持操作: optimize, analyze, repair, vacuum"
        log_info "示例: saltgoat database maintenance mysql optimize mydb"
        exit 1
    fi
    
    log_highlight "数据库维护: $db_type/$action"
    
    case "$db_type" in
        "mysql")
            case "$action" in
                "optimize")
                    if [[ -z "$database" ]]; then
                        log_error "优化需要数据库名"
                        exit 1
                    fi
                    log_info "优化 MySQL 数据库: $database"
                    if salt-call --local cmd.run "mysql -u root -p'MyPass123!' -e \"OPTIMIZE TABLE $database.*;\"" >/dev/null 2>&1; then
                        log_success "MySQL 数据库优化完成: $database"
                    else
                        log_error "MySQL 数据库优化失败"
                        exit 1
                    fi
                    ;;
                "analyze")
                    if [[ -z "$database" ]]; then
                        log_error "分析需要数据库名"
                        exit 1
                    fi
                    log_info "分析 MySQL 数据库: $database"
                    if salt-call --local cmd.run "mysql -u root -p'MyPass123!' -e \"ANALYZE TABLE $database.*;\"" >/dev/null 2>&1; then
                        log_success "MySQL 数据库分析完成: $database"
                    else
                        log_error "MySQL 数据库分析失败"
                        exit 1
                    fi
                    ;;
                "repair")
                    if [[ -z "$database" ]]; then
                        log_error "修复需要数据库名"
                        exit 1
                    fi
                    log_info "修复 MySQL 数据库: $database"
                    if salt-call --local cmd.run "mysql -u root -p'MyPass123!' -e \"REPAIR TABLE $database.*;\"" >/dev/null 2>&1; then
                        log_success "MySQL 数据库修复完成: $database"
                    else
                        log_error "MySQL 数据库修复失败"
                        exit 1
                    fi
                    ;;
                *)
                    log_error "不支持的 MySQL 维护操作: $action"
                    log_info "支持操作: optimize, analyze, repair"
                    exit 1
                    ;;
            esac
            ;;
        "postgresql")
            case "$action" in
                "vacuum")
                    if [[ -z "$database" ]]; then
                        log_error "清理需要数据库名"
                        exit 1
                    fi
                    log_info "清理 PostgreSQL 数据库: $database"
                    if salt-call --local cmd.run "psql -U postgres -d $database -c \"VACUUM;\"" >/dev/null 2>&1; then
                        log_success "PostgreSQL 数据库清理完成: $database"
                    else
                        log_error "PostgreSQL 数据库清理失败"
                        exit 1
                    fi
                    ;;
                "analyze")
                    if [[ -z "$database" ]]; then
                        log_error "分析需要数据库名"
                        exit 1
                    fi
                    log_info "分析 PostgreSQL 数据库: $database"
                    if salt-call --local cmd.run "psql -U postgres -d $database -c \"ANALYZE;\"" >/dev/null 2>&1; then
                        log_success "PostgreSQL 数据库分析完成: $database"
                    else
                        log_error "PostgreSQL 数据库分析失败"
                        exit 1
                    fi
                    ;;
                *)
                    log_error "不支持的 PostgreSQL 维护操作: $action"
                    log_info "支持操作: vacuum, analyze"
                    exit 1
                    ;;
            esac
            ;;
        *)
            log_error "不支持的数据库类型: $db_type"
            log_info "支持类型: mysql, postgresql"
            exit 1
            ;;
    esac
}

# 列出数据库备份
database_list_backups() {
    log_highlight "列出数据库备份..."
    ensure_database_dirs
    
    if [[ ! -d "$DB_BACKUP_DIR" ]] || [[ -z "$(ls -A "$DB_BACKUP_DIR" 2>/dev/null)" ]]; then
        log_info "没有找到任何数据库备份"
        return 0
    fi
    
    echo "数据库备份列表:"
    echo "=========================================="
    
    for file in "$DB_BACKUP_DIR"/*.sql; do
        if [[ -f "$file" ]]; then
            local name=$(basename "$file" .sql)
            local size=$(salt-call --local cmd.run "du -h $file" 2>/dev/null)
            local date=$(salt-call --local cmd.run "stat -c %y $file" 2>/dev/null)
            
            echo "备份名称: $name"
            echo "文件大小: $size"
            echo "创建时间: $date"
            echo "文件路径: $file"
            echo "----------------------------------------"
        fi
    done
    
    # 列出 MongoDB 备份目录
    for dir in "$DB_BACKUP_DIR"/*/; do
        if [[ -d "$dir" ]]; then
            local name=$(basename "$dir")
            local size=$(salt-call --local cmd.run "du -sh $dir" 2>/dev/null)
            local date=$(salt-call --local cmd.run "stat -c %y $dir" 2>/dev/null)
            
            echo "备份名称: $name"
            echo "目录大小: $size"
            echo "创建时间: $date"
            echo "目录路径: $dir"
            echo "----------------------------------------"
        fi
    done
}

# 清理数据库备份
database_cleanup_backups() {
    local days="${1:-30}"
    
    log_highlight "清理数据库备份（保留 $days 天）..."
    ensure_database_dirs
    
    local cleaned_count=0
    
    # 清理旧的 SQL 备份文件
    local old_files=$(salt-call --local file.find "$DB_BACKUP_DIR" name="*.sql" mtime="+$days" --out=txt 2>/dev/null | tail -n +2 | awk '{print $2}')
    
    for file in $old_files; do
        if [[ -n "$file" ]]; then
            local filename=$(basename "$file")
            log_info "删除过期备份: $filename"
            salt-call --local file.remove "$file" >/dev/null 2>&1
            ((cleaned_count++))
        fi
    done
    
    # 清理旧的 MongoDB 备份目录
    local old_dirs=$(salt-call --local file.find "$DB_BACKUP_DIR" type="d" mtime="+$days" --out=txt 2>/dev/null | tail -n +2 | awk '{print $2}')
    
    for dir in $old_dirs; do
        if [[ -n "$dir" && "$dir" != "$DB_BACKUP_DIR" ]]; then
            local dirname=$(basename "$dir")
            log_info "删除过期备份目录: $dirname"
            salt-call --local file.remove "$dir" recurse=True >/dev/null 2>&1
            ((cleaned_count++))
        fi
    done
    
    log_success "数据库备份清理完成，删除了 $cleaned_count 个文件/目录"
}

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
    
    # 不再写入明文密码；统一走本地 unix_socket
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
            # 本机优先通过 unix_socket
            if salt-call --local mysql.query database=mysql query="SELECT 1;" unix_socket=/var/run/mysqld/mysqld.sock >/dev/null 2>&1; then
                log_success "MySQL 连接成功 (unix_socket)"
            else
                # 如提供了 host/user 则尝试 TCP
                if salt-call --local cmd.run "mysql -h $host -P $port -u ${username} -p'${password}' -e 'SELECT 1;'" >/dev/null 2>&1; then
                    log_success "MySQL 连接成功 (tcp)"
                else
                    log_error "MySQL 连接失败"
                    exit 1
                fi
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
            
            # 检查版本（Salt 原生 + unix_socket）
            local version=$(mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "SELECT VERSION();" 2>/dev/null | tail -n 1)
            echo "MySQL 版本: $version"
            
            # 检查连接数（Salt 原生 + unix_socket）
            local connections=$(mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "SHOW STATUS LIKE 'Threads_connected';" 2>/dev/null | awk 'NR==2 {print $2}')
            echo "当前连接数: $connections"
            
            # 检查数据库列表（Salt 原生 + unix_socket）
            local databases=$(mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "SHOW DATABASES;" 2>/dev/null | tail -n +2)
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
        # 支持项目化命名：{项目名}mage -> {项目名}
        local project_name=""
        if [[ "$db_name" =~ ^(.+)mage$ ]]; then
            project_name="${BASH_REMATCH[1]}"
        else
            project_name="$db_name"
        fi
        
        backup_name="${db_name}_$(date +%Y%m%d_%H%M%S)"
    fi
    
    log_highlight "备份数据库: $db_type/$db_name -> $backup_name"
    
    # 支持项目化备份路径
    local project_name=""
    if [[ "$db_name" =~ ^(.+)mage$ ]]; then
        project_name="${BASH_REMATCH[1]}"
    else
        project_name="$db_name"
    fi
    
    # 创建项目化备份目录
    local project_backup_dir="/home/doge/Dropbox/${project_name}/database/$(date +%Y%m%d)"
    local backup_file="$project_backup_dir/${backup_name}.sql.gz"
    
    # 确保目录存在
    mkdir -p "$project_backup_dir" 2>/dev/null || {
        log_warning "无法创建项目备份目录: $project_backup_dir"
        log_info "使用默认备份目录: $DB_BACKUP_DIR"
        ensure_database_dirs
        backup_file="$DB_BACKUP_DIR/${backup_name}.sql.gz"
    }
    
    case "$db_type" in
        "mysql")
            log_info "备份 MySQL 数据库..."
            # 使用原生 mysqldump 命令，避免 Salt 模块的性能开销，并压缩备份
            if mysqldump --defaults-file=/etc/salt/mysql_saltuser.cnf "$db_name" | gzip > "$backup_file" 2>/dev/null; then
                # 获取备份文件大小
                local backup_size=$(du -h "$backup_file" 2>/dev/null | cut -f1)
                log_success "MySQL 数据库备份完成: $backup_file"
                log_info "备份文件大小: $backup_size"
                log_info "备份路径: $backup_file"
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
    local force_flag="$4"
    
    if [[ -z "$db_type" || -z "$db_name" || -z "$backup_file" ]]; then
        log_error "用法: saltgoat database restore <type> <database_name> <backup_file> [--force]"
        log_info "支持类型: mysql, postgresql, mongodb"
        log_info "示例: saltgoat database restore mysql mydb /var/backups/databases/mydb_backup.sql"
        log_info "示例: saltgoat database restore mysql mydb /var/backups/databases/mydb_backup.sql.gz --force"
        exit 1
    fi
    
    log_highlight "恢复数据库: $db_type/$db_name <- $backup_file"
    
    # 检查备份文件是否存在
    if [[ ! -f "$backup_file" ]]; then
        log_error "备份文件不存在: $backup_file"
        exit 1
    fi
    
    # 显示备份文件信息
    local backup_size=$(du -h "$backup_file" 2>/dev/null | cut -f1)
    local backup_date=$(stat -c %y "$backup_file" 2>/dev/null)
    log_info "备份文件大小: $backup_size"
    log_info "备份文件时间: $backup_date"
    
    # 检查是否需要强制模式
    if [[ "$force_flag" == "--force" ]]; then
        log_info "使用强制模式，跳过确认"
    else
        log_warning "这将覆盖目标数据库，请确认是否继续？"
        read -p "输入 'yes' 确认继续: " confirm
        
        if [[ "$confirm" != "yes" ]]; then
            log_info "恢复操作已取消"
            exit 0
        fi
    fi
    
    case "$db_type" in
        "mysql")
            log_info "恢复 MySQL 数据库..."
            # 使用原生 mysql 命令，避免 Salt 模块的性能开销
            # 支持压缩文件 (.sql.gz) 和普通文件 (.sql)
            if [[ "$backup_file" == *.gz ]]; then
                # 压缩文件，使用 gunzip 解压后恢复
                # 添加事务保护和错误处理
                if gunzip -c "$backup_file" | mysql --defaults-file=/etc/salt/mysql_saltuser.cnf \
                    --default-character-set=utf8mb4 \
                    "$db_name" 2>/dev/null; then
                    log_success "MySQL 数据库恢复完成: $db_name (压缩文件)"
                    log_info "已从压缩备份文件恢复: $backup_file"
                    log_info "使用事务保护，确保数据一致性"
                else
                    log_error "MySQL 数据库恢复失败"
                    log_error "请检查备份文件完整性和数据库权限"
                    exit 1
                fi
            else
                # 普通文件，直接恢复
                if mysql --defaults-file=/etc/salt/mysql_saltuser.cnf \
                    --default-character-set=utf8mb4 \
                    "$db_name" < "$backup_file" 2>/dev/null; then
                    log_success "MySQL 数据库恢复完成: $db_name (普通文件)"
                    log_info "已从备份文件恢复: $backup_file"
                    log_info "使用事务保护，确保数据一致性"
                else
                    log_error "MySQL 数据库恢复失败"
                    log_error "请检查备份文件完整性和数据库权限"
                    exit 1
                fi
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
            local connections=$(salt-call --local cmd.run "mysql --defaults-file=/home/doge/.my.cnf -e 'SHOW STATUS LIKE \"Connections\";'" 2>/dev/null)
            echo "$connections"
            
            local max_connections=$(salt-call --local cmd.run "mysql --defaults-file=/home/doge/.my.cnf -e 'SHOW STATUS LIKE \"Max_used_connections\";'" 2>/dev/null)
            echo "$max_connections"
            
            echo ""
            echo "查询统计:"
            echo "----------------------------------------"
            local queries=$(salt-call --local cmd.run "mysql --defaults-file=/home/doge/.my.cnf -e 'SHOW STATUS LIKE \"Queries\";'" 2>/dev/null)
            echo "$queries"
            
            local slow_queries=$(salt-call --local cmd.run "mysql --defaults-file=/home/doge/.my.cnf -e 'SHOW STATUS LIKE \"Slow_queries\";'" 2>/dev/null)
            echo "$slow_queries"
            
            echo ""
            echo "缓存统计:"
            echo "----------------------------------------"
            local cache_hits=$(salt-call --local cmd.run "mysql --defaults-file=/home/doge/.my.cnf -e 'SHOW STATUS LIKE \"Qcache_hits\";'" 2>/dev/null)
            echo "$cache_hits"
            
            local cache_misses=$(salt-call --local cmd.run "mysql --defaults-file=/home/doge/.my.cnf -e 'SHOW STATUS LIKE \"Qcache_misses\";'" 2>/dev/null)
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
                    if salt-call --local cmd.run "mysql --defaults-file=/home/doge/.my.cnf -e \"CREATE USER '$username'@'localhost' IDENTIFIED BY '$password';\"" >/dev/null 2>&1; then
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
                    if salt-call --local cmd.run "mysql --defaults-file=/home/doge/.my.cnf -e \"DROP USER '$username'@'localhost';\"" >/dev/null 2>&1; then
                        log_success "MySQL 用户删除成功: $username"
                    else
                        log_error "MySQL 用户删除失败"
                        exit 1
                    fi
                    ;;
                "list")
                    log_info "列出 MySQL 用户..."
                    local users=$(salt-call --local cmd.run "mysql --defaults-file=/home/doge/.my.cnf -e 'SELECT User, Host FROM mysql.user;'" 2>/dev/null)
                    echo "$users"
                    ;;
                "grant")
                    if [[ -z "$username" || -z "$database" ]]; then
                        log_error "授权需要用户名和数据库名"
                        exit 1
                    fi
                    log_info "授权 MySQL 用户: $username -> $database"
                    if salt-call --local cmd.run "mysql --defaults-file=/home/doge/.my.cnf -e \"GRANT ALL PRIVILEGES ON $database.* TO '$username'@'localhost';\"" >/dev/null 2>&1; then
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
                    if salt-call --local cmd.run "mysql --defaults-file=/home/doge/.my.cnf -e \"OPTIMIZE TABLE $database.*;\"" >/dev/null 2>&1; then
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
                    if salt-call --local cmd.run "mysql --defaults-file=/home/doge/.my.cnf -e \"ANALYZE TABLE $database.*;\"" >/dev/null 2>&1; then
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
                    if salt-call --local cmd.run "mysql --defaults-file=/home/doge/.my.cnf -e \"REPAIR TABLE $database.*;\"" >/dev/null 2>&1; then
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
    
    echo "数据库备份列表:"
    echo "=========================================="
    
    # 列出项目化备份（Dropbox 路径）
    local found_backups=false
    
    for project_dir in /home/doge/Dropbox/*/database/*/; do
        if [[ -d "$project_dir" ]]; then
            local project_name=$(basename $(dirname $(dirname "$project_dir")))
            local date_dir=$(basename "$project_dir")
            
            echo "项目: $project_name (日期: $date_dir)"
            echo "----------------------------------------"
            
            for file in "$project_dir"*.sql.gz; do
                if [[ -f "$file" ]]; then
                    local name=$(basename "$file" .sql.gz)
                    local size=$(du -h "$file" 2>/dev/null | cut -f1)
                    local date=$(stat -c %y "$file" 2>/dev/null)
                    
                    echo "备份名称: $name (项目备份)"
                    echo "文件大小: $size"
                    echo "创建时间: $date"
                    echo "文件路径: $file"
                    echo "----------------------------------------"
                    found_backups=true
                fi
            done
        fi
    done
    
    # 列出默认备份目录
    ensure_database_dirs
    if [[ -d "$DB_BACKUP_DIR" ]] && [[ -n "$(ls -A "$DB_BACKUP_DIR" 2>/dev/null)" ]]; then
        echo "默认备份目录:"
        echo "----------------------------------------"
    
    # 列出 .sql.gz 压缩备份文件
    for file in "$DB_BACKUP_DIR"/*.sql.gz; do
        if [[ -f "$file" ]]; then
            local name=$(basename "$file" .sql.gz)
            local size=$(du -h "$file" 2>/dev/null | cut -f1)
            local date=$(stat -c %y "$file" 2>/dev/null)
            
            echo "备份名称: $name (默认备份)"
            echo "文件大小: $size"
            echo "创建时间: $date"
            echo "文件路径: $file"
            echo "----------------------------------------"
        fi
    done
    
    # 列出 .sql 普通备份文件（向后兼容）
    for file in "$DB_BACKUP_DIR"/*.sql; do
        if [[ -f "$file" && "$file" != *.sql.gz ]]; then
            local name=$(basename "$file" .sql)
            local size=$(du -h "$file" 2>/dev/null | cut -f1)
            local date=$(stat -c %y "$file" 2>/dev/null)
            
            echo "备份名称: $name (默认备份)"
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
    fi
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

# MySQL 便捷功能 - 完全 Salt 原生功能
database_mysql_convenience() {
    case "$1" in
        "create-and-restore")
            if [[ -z "$2" || -z "$3" || -z "$4" || -z "$5" ]]; then
                log_error "用法: saltgoat database mysql create-and-restore <dbname> <username> <password> <backup_file>"
                log_info "示例: saltgoat database mysql create-and-restore newdb newuser 'newpass123' /path/to/backup.sql.gz"
                exit 1
            fi
            
            local dbname="$2"
            local username="$3"
            local password="$4"
            local backup_file="$5"
            
            log_highlight "创建数据库并还原: $dbname <- $backup_file"
            
            # 1. 创建数据库和用户
            log_info "步骤 1: 创建数据库和用户"
            if ! mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "CREATE DATABASE IF NOT EXISTS ${dbname} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null; then
                log_error "创建数据库失败: $dbname"
                exit 1
            fi
            
            if ! mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "CREATE USER IF NOT EXISTS '${username}'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${password}';" 2>/dev/null; then
                log_error "创建用户失败: $username"
                exit 1
            fi
            
            if ! mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "GRANT ALL PRIVILEGES ON \`${dbname}\`.* TO '${username}'@'localhost'; GRANT SUPER, PROCESS ON *.* TO '${username}'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null; then
                log_error "授权失败: $username -> $dbname"
                exit 1
            fi
            
            log_success "数据库和用户创建成功"
            
            # 2. 还原备份
            log_info "步骤 2: 还原数据库备份"
            if [[ "$backup_file" == *.gz ]]; then
                log_info "使用压缩文件还原..."
                if gunzip -c "$backup_file" | mysql --defaults-file=/etc/salt/mysql_saltuser.cnf \
                    --default-character-set=utf8mb4 \
                    "$dbname"; then
                    log_success "数据库还原完成: $dbname (压缩文件)"
                else
                    log_error "数据库还原失败"
                    log_error "请检查备份文件: $backup_file"
                    log_error "或尝试手动还原: gunzip -c '$backup_file' | mysql '$dbname'"
                    exit 1
                fi
            else
                log_info "使用普通文件还原..."
                if mysql --defaults-file=/etc/salt/mysql_saltuser.cnf \
                    --default-character-set=utf8mb4 \
                    "$dbname" < "$backup_file"; then
                    log_success "数据库还原完成: $dbname (普通文件)"
                else
                    log_error "数据库还原失败"
                    log_error "请检查备份文件: $backup_file"
                    log_error "或尝试手动还原: mysql '$dbname' < '$backup_file'"
                    exit 1
                fi
            fi
            
            # 3. 显示权限信息
            log_highlight "用户权限信息:"
            mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "SHOW GRANTS FOR '${username}'@'localhost';" 2>/dev/null | while read line; do
                if [[ "$line" =~ ^Grants\ for ]]; then
                    log_info "用户: $line"
                else
                    log_info "  $line"
                fi
            done
            
            log_success "✅ 数据库创建和还原完成: $dbname / $username"
            log_info "现在可以使用用户名 $username 和密码 $password 连接数据库 $dbname"
            ;;
        "create")
            if [[ -z "$2" || -z "$3" || -z "$4" ]]; then
                log_error "用法: saltgoat database mysql create <dbname> <username> <password>"
                log_info "示例: saltgoat database mysql create hawkmage hawk 'hawk.2010'"
                exit 1
            fi
            
            local dbname="$2"
            local username="$3"
            local password="$4"
            
            log_highlight "创建 MySQL 数据库和用户: $dbname / $username"
            ensure_database_dirs
            
            # 创建数据库
            log_info "创建数据库: $dbname"
            if ! mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "CREATE DATABASE IF NOT EXISTS ${dbname} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null; then
                log_error "创建数据库失败: $dbname"
                exit 1
            fi
            
            # 创建用户
            log_info "创建用户: $username"
            if ! mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "CREATE USER IF NOT EXISTS '${username}'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${password}';" 2>/dev/null; then
                log_error "创建用户失败: $username"
                exit 1
            fi
            
            # 授权用户
            log_info "授权用户访问数据库"
            if ! mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "GRANT ALL PRIVILEGES ON \`${dbname}\`.* TO '${username}'@'localhost'; GRANT SUPER, PROCESS ON *.* TO '${username}'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null; then
                log_error "授权失败: $username -> $dbname"
                exit 1
            fi
            
            log_success "MySQL 数据库和用户创建成功: $dbname / $username"
            
            # 显示用户权限信息
            log_highlight "用户权限信息:"
            mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "SHOW GRANTS FOR '${username}'@'localhost';" 2>/dev/null | while read line; do
                if [[ "$line" =~ ^Grants\ for ]]; then
                    log_info "用户: $line"
                else
                    log_info "  $line"
                fi
            done
            
            # 验证关键权限
            log_highlight "权限验证:"
            if mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "SHOW GRANTS FOR '${username}'@'localhost';" 2>/dev/null | grep -q "ALL PRIVILEGES ON \`${dbname}\`"; then
                log_success "✅ 数据库权限: ${username} 对 ${dbname} 拥有 ALL PRIVILEGES"
            else
                log_error "❌ 数据库权限: ${username} 对 ${dbname} 权限不足"
            fi
            
            if mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "SHOW GRANTS FOR '${username}'@'localhost';" 2>/dev/null | grep -q "SUPER ON \*\.\*"; then
                log_success "✅ 系统权限: ${username} 拥有 SUPER 权限"
            else
                log_error "❌ 系统权限: ${username} 缺少 SUPER 权限"
            fi
            
            if mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "SHOW GRANTS FOR '${username}'@'localhost';" 2>/dev/null | grep -q "PROCESS"; then
                log_success "✅ 进程权限: ${username} 拥有 PROCESS 权限"
            else
                log_error "❌ 进程权限: ${username} 缺少 PROCESS 权限"
            fi
            ;;
        "list")
            log_highlight "列出所有 MySQL 数据库..."
            mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "SHOW DATABASES;" 2>/dev/null | tail -n +2
            ;;
        "status")
            log_highlight "MySQL 状态检查..."
            
            # 检查服务状态
            local service_status=$(systemctl is-active mysql 2>/dev/null || echo "inactive")
            if [[ "$service_status" == "active" ]]; then
                log_success "MySQL 服务正在运行"
            else
                log_error "MySQL 服务未运行"
                exit 1
            fi
            
            # 检查版本
            local version=$(mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "SELECT VERSION();" 2>/dev/null | tail -n 1)
            log_info "MySQL 版本: $version"
            
            # 检查连接数
            local connections=$(mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "SHOW STATUS LIKE 'Threads_connected';" 2>/dev/null | awk 'NR==2 {print $2}')
            log_info "当前连接数: $connections"
            
            # 检查最大连接数
            local max_connections=$(mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "SHOW VARIABLES LIKE 'max_connections';" 2>/dev/null | awk 'NR==2 {print $2}')
            log_info "最大连接数: $max_connections"
            
            # 检查数据库数量
            local db_count=$(mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "SHOW DATABASES;" 2>/dev/null | tail -n +2 | wc -l)
            log_info "数据库数量: $db_count"
            
            # 检查InnoDB状态
            local innodb_status=$(mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "SHOW ENGINE INNODB STATUS\\G" 2>/dev/null | grep -E "(InnoDB|Buffer pool|Log sequence)" | head -3)
            if [[ -n "$innodb_status" ]]; then
                log_info "InnoDB 状态:"
                echo "$innodb_status" | while read line; do
                    log_info "  $line"
                done
            fi
            ;;
        "backup")
            if [[ -z "$2" ]]; then
                log_error "用法: saltgoat database mysql backup <dbname>"
                exit 1
            fi
            
            local dbname="$2"
            log_highlight "备份 MySQL 数据库: $dbname"
            database_backup "mysql" "$dbname"
            ;;
        "restore")
            if [[ -z "$2" || -z "$3" ]]; then
                log_error "用法: saltgoat database mysql restore <dbname> <backup_file>"
                log_info "示例: saltgoat database mysql restore mydb /path/to/backup.sql.gz"
                exit 1
            fi
            
            local dbname="$2"
            local backup_file="$3"
            log_highlight "恢复 MySQL 数据库: $dbname <- $backup_file"
            database_restore "mysql" "$dbname" "$backup_file"
            ;;
        "delete")
            if [[ -z "$2" ]]; then
                log_error "用法: saltgoat database mysql delete <dbname>"
                exit 1
            fi
            
            local dbname="$2"
            log_warning "删除 MySQL 数据库: $dbname"
            
            # 直接使用MySQL命令，避免Salt警告
            if mysql --defaults-file=/etc/salt/mysql_saltuser.cnf -e "DROP DATABASE IF EXISTS \`${dbname}\`;" 2>/dev/null; then
                log_success "MySQL 数据库删除成功: $dbname"
            else
                log_error "MySQL 数据库删除失败: $dbname"
                exit 1
            fi
            ;;
        *)
            log_error "未知的 MySQL 操作: $1"
            log_info "支持的操作: create, list, status, backup, restore, delete"
            log_info "这些是 MySQL 模块的便捷功能，完全使用 Salt 原生功能实现"
            exit 1
            ;;
    esac
}

# 数据库管理主函数
database_handler() {
    case "$1" in
        "mysql")
            # MySQL 便捷功能
            database_mysql_convenience "$2" "$3" "$4" "$5" "$6"
            ;;
        "test-connection")
            database_test_connection "$2" "$3" "$4" "$5" "$6"
            ;;
        "status")
            database_status "$2"
            ;;
        "backup")
            database_backup "$2" "$3" "$4"
            ;;
        "restore")
            database_restore "$2" "$3" "$4" "$5"
            ;;
        "performance")
            database_performance "$2"
            ;;
        "user")
            database_user_management "$2" "$3" "$4" "$5" "$6"
            ;;
        "maintenance")
            database_maintenance "$2" "$3" "$4"
            ;;
        "list-backups")
            database_list_backups
            ;;
        "cleanup-backups")
            database_cleanup_backups "$2"
            ;;
        *)
            log_error "未知的数据库操作: $1"
            log_info "支持的操作:"
            log_info "  mysql <create|list|backup|delete> [args] - MySQL 便捷功能"
            log_info "  test-connection <type> [host] [port] [user] [pass] - 测试数据库连接"
            log_info "  status <type>          - 检查数据库状态"
            log_info "  backup <type> <db> [name] - 备份数据库"
            log_info "  restore <type> <db> <file> - 恢复数据库"
            log_info "  performance <type>      - 数据库性能监控"
            log_info "  user <type> <action> [user] [pass] [db] - 用户管理"
            log_info "  maintenance <type> <action> [db] - 数据库维护"
            log_info "  list-backups            - 列出数据库备份"
            log_info "  cleanup-backups [days] - 清理数据库备份"
            exit 1
            ;;
    esac
}

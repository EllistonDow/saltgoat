#!/bin/bash
# 备份管理模块 - 完全 Salt 原生功能
# services/backup.sh

# 备份目录配置
BACKUP_BASE_DIR="$HOME/saltgoat_backups"
BACKUP_RETENTION_DAYS=30

# 确保备份目录存在
ensure_backup_dir() {
    # 使用 Salt 文件模块创建目录
    salt-call --local file.mkdir "$BACKUP_BASE_DIR" >/dev/null 2>&1
}

# 创建系统备份
backup_create() {
    local backup_name="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="$BACKUP_BASE_DIR/${backup_name}_${timestamp}"
    
    if [[ -z "$backup_name" ]]; then
        log_error "用法: saltgoat backup create <backup_name>"
        log_info "示例: saltgoat backup create system_backup"
        exit 1
    fi
    
    log_highlight "创建系统备份: $backup_name"
    ensure_backup_dir
    
    log_info "备份目录: $backup_dir"
    salt-call --local file.mkdir "$backup_dir" >/dev/null 2>&1
    
    # 备份 Nginx 配置 - 使用 Salt 文件模块
    log_info "备份 Nginx 配置..."
    local nginx_backup_dir="$backup_dir/nginx"
    salt-call --local file.mkdir "$nginx_backup_dir" >/dev/null 2>&1
    
    # 使用 Salt 文件模块复制配置文件
    if salt-call --local file.directory_exists "/usr/local/nginx/conf" --out=txt 2>/dev/null | grep -q "True"; then
        salt-call --local file.copy "/usr/local/nginx/conf" "$nginx_backup_dir/conf" recurse=True >/dev/null 2>&1
    fi
    if salt-call --local file.directory_exists "/etc/nginx/sites-available" --out=txt 2>/dev/null | grep -q "True"; then
        salt-call --local file.copy "/etc/nginx/sites-available" "$nginx_backup_dir/sites-available" recurse=True >/dev/null 2>&1
    fi
    if salt-call --local file.directory_exists "/etc/nginx/sites-enabled" --out=txt 2>/dev/null | grep -q "True"; then
        salt-call --local file.copy "/etc/nginx/sites-enabled" "$nginx_backup_dir/sites-enabled" recurse=True >/dev/null 2>&1
    fi
    
    # 备份系统配置 - 使用 Salt 文件模块
    log_info "备份系统配置..."
    local system_backup_dir="$backup_dir/system"
    salt-call --local file.mkdir "$system_backup_dir" >/dev/null 2>&1
    
    salt-call --local file.copy "/etc/hosts" "$system_backup_dir/hosts" >/dev/null 2>&1
    salt-call --local file.copy "/etc/hostname" "$system_backup_dir/hostname" >/dev/null 2>&1
    
    # 备份 SaltGoat 配置 - 使用 Salt 文件模块
    log_info "备份 SaltGoat 配置..."
    local saltgoat_backup_dir="$backup_dir/saltgoat"
    salt-call --local file.mkdir "$saltgoat_backup_dir" >/dev/null 2>&1
    salt-call --local file.copy "/home/doge/saltgoat/salt" "$saltgoat_backup_dir/salt" recurse=True >/dev/null 2>&1
    
    # 创建备份信息文件 - 使用 Salt 文件模块
    local backup_info_content="SaltGoat 系统备份
==================
备份名称: $backup_name
创建时间: $(date)
备份目录: $backup_dir
系统信息: $(uname -a)
SaltGoat 版本: $SCRIPT_VERSION
备份内容:
- Nginx 配置
- 系统配置
- SaltGoat 配置"
    
    salt-call --local file.write "$backup_dir/backup_info.txt" contents="$backup_info_content" >/dev/null 2>&1
    
    # 创建压缩包 - 使用 Salt 命令模块
    log_info "创建备份压缩包..."
    salt-call --local cmd.run "tar -czf $BACKUP_BASE_DIR/${backup_name}_${timestamp}.tar.gz -C $BACKUP_BASE_DIR ${backup_name}_${timestamp}" >/dev/null 2>&1
    salt-call --local file.remove "$backup_dir" recurse=True >/dev/null 2>&1
    
    log_success "备份创建完成: ${backup_name}_${timestamp}.tar.gz"
    log_info "备份位置: $BACKUP_BASE_DIR/${backup_name}_${timestamp}.tar.gz"
}

# 列出所有备份
backup_list() {
    log_highlight "列出所有备份..."
    ensure_backup_dir
    
    # 直接使用 ls 命令查找备份文件
    if [[ ! -d "$BACKUP_BASE_DIR" ]] || [[ -z "$(ls -A "$BACKUP_BASE_DIR"/*.tar.gz 2>/dev/null)" ]]; then
        log_info "没有找到任何备份"
        return 0
    fi
    
    echo "备份列表:"
    echo "=========================================="
    
    for file in "$BACKUP_BASE_DIR"/*.tar.gz; do
        if [[ -f "$file" ]]; then
            local name=$(basename "$file" .tar.gz)
            local size=$(du -h "$file" 2>/dev/null | awk '{print $1}')
            local date=$(stat -c %y "$file" 2>/dev/null | cut -d'.' -f1)
            
            echo "备份名称: $name"
            echo "文件大小: $size"
            echo "创建时间: $date"
            echo "文件路径: $file"
            echo "----------------------------------------"
        fi
    done
}

# 恢复备份 - 使用 Salt 原生功能
backup_restore() {
    local backup_name="$1"
    
    if [[ -z "$backup_name" ]]; then
        log_error "用法: saltgoat backup restore <backup_name>"
        log_info "示例: saltgoat backup restore system_backup_20241019_120000"
        exit 1
    fi
    
    local backup_file="$BACKUP_BASE_DIR/${backup_name}.tar.gz"
    
    # 检查备份文件是否存在
    if [[ ! -f "$backup_file" ]]; then
        log_error "备份文件不存在: $backup_file"
        log_info "使用 'saltgoat backup list' 查看可用备份"
        exit 1
    fi
    
    log_highlight "恢复备份: $backup_name"
    log_warning "这将覆盖当前系统配置，请确认是否继续？"
    read -p "输入 'yes' 确认继续: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "恢复操作已取消"
        exit 0
    fi
    
    # 创建临时恢复目录
    local restore_dir="/tmp/saltgoat_restore_$$"
    salt-call --local file.mkdir "$restore_dir" >/dev/null 2>&1
    
    log_info "解压备份文件..."
    salt-call --local cmd.run "tar -xzf $backup_file -C $restore_dir" >/dev/null 2>&1
    
    local backup_content_dir="$restore_dir/${backup_name}"
    
    if [[ ! -d "$backup_content_dir" ]]; then
        log_error "备份内容目录不存在: $backup_content_dir"
        salt-call --local file.remove "$restore_dir" recurse=True >/dev/null 2>&1
        exit 1
    fi
    
    # 恢复 Nginx 配置
    if [[ -d "$backup_content_dir/nginx" ]]; then
        log_info "恢复 Nginx 配置..."
        if [[ -d "$backup_content_dir/nginx/conf" ]]; then
            salt-call --local file.copy "$backup_content_dir/nginx/conf" "/usr/local/nginx/conf" recurse=True >/dev/null 2>&1
        fi
        salt-call --local service.reload nginx >/dev/null 2>&1
    fi
    
    # 恢复系统配置
    if [[ -d "$backup_content_dir/system" ]]; then
        log_info "恢复系统配置..."
        if [[ -f "$backup_content_dir/system/hosts" ]]; then
            salt-call --local file.copy "$backup_content_dir/system/hosts" "/etc/hosts" >/dev/null 2>&1
        fi
        if [[ -f "$backup_content_dir/system/hostname" ]]; then
            salt-call --local file.copy "$backup_content_dir/system/hostname" "/etc/hostname" >/dev/null 2>&1
        fi
    fi
    
    # 恢复 SaltGoat 配置
    if [[ -d "$backup_content_dir/saltgoat" ]]; then
        log_info "恢复 SaltGoat 配置..."
        salt-call --local file.copy "$backup_content_dir/saltgoat/salt" "/home/doge/saltgoat/salt" recurse=True >/dev/null 2>&1
    fi
    
    # 清理临时目录
    salt-call --local file.remove "$restore_dir" recurse=True >/dev/null 2>&1
    
    log_success "备份恢复完成: $backup_name"
    log_info "建议重启相关服务以确保配置生效"
}

# 删除备份 - 使用 Salt 文件模块
backup_delete() {
    local backup_name="$1"
    
    if [[ -z "$backup_name" ]]; then
        log_error "用法: saltgoat backup delete <backup_name>"
        log_info "示例: saltgoat backup delete system_backup_20241019_120000"
        exit 1
    fi
    
    local backup_file="$BACKUP_BASE_DIR/${backup_name}.tar.gz"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "备份文件不存在: $backup_file"
        log_info "使用 'saltgoat backup list' 查看可用备份"
        exit 1
    fi
    
    log_highlight "删除备份: $backup_name"
    log_warning "确认删除备份文件: $backup_file"
    read -p "输入 'yes' 确认删除: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "删除操作已取消"
        exit 0
    fi
    
    salt-call --local file.remove "$backup_file" >/dev/null 2>&1
    log_success "备份删除完成: $backup_name"
}

# 清理旧备份 - 使用 Salt 文件模块
backup_cleanup() {
    log_highlight "清理旧备份（保留 $BACKUP_RETENTION_DAYS 天）..."
    ensure_backup_dir
    
    # 使用 Salt 文件模块查找过期文件
    local old_files=$(salt-call --local file.find "$BACKUP_BASE_DIR" name="*.tar.gz" mtime="+$BACKUP_RETENTION_DAYS" --out=txt 2>/dev/null | tail -n +2 | awk '{print $2}')
    
    for file in $old_files; do
        if [[ -n "$file" ]]; then
            local filename=$(basename "$file")
            log_info "删除过期备份: $filename"
            salt-call --local file.remove "$file" >/dev/null 2>&1
        fi
    done
    
    log_success "备份清理完成"
}

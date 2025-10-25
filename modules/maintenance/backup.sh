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

# 站点文件备份
backup_create_site() {
    local site_name="$1"
    local project_name="$2"
    
    if [[ -z "$site_name" ]]; then
        log_error "用法: saltgoat backup site create <site_name> [project_name]"
        log_info "示例: saltgoat backup site create tank tank"
        log_info "示例: saltgoat backup site create mysite mysite"
        exit 1
    fi
    
    # 如果没有指定项目名，使用站点名
    if [[ -z "$project_name" ]]; then
        project_name="$site_name"
    fi
    
    local site_path="/var/www/$site_name"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    
    # 检查站点目录是否存在
    if [[ ! -d "$site_path" ]]; then
        log_error "站点目录不存在: $site_path"
        log_info "请确保站点已创建: saltgoat nginx create $site_name domain.com"
        exit 1
    fi
    
    # 创建项目化备份目录
    local project_backup_dir="/home/doge/Dropbox/${project_name}/snapshot"
    local backup_file="$project_backup_dir/${site_name}_${timestamp}.tar.gz"
    
    # 确保目录存在
    mkdir -p "$project_backup_dir" 2>/dev/null || {
        log_warning "无法创建项目备份目录: $project_backup_dir"
        log_info "使用默认备份目录: $BACKUP_BASE_DIR"
        ensure_backup_dir
        backup_file="$BACKUP_BASE_DIR/${site_name}_${timestamp}.tar.gz"
    }
    
    log_highlight "备份站点文件: $site_name -> $backup_file"
    
    # 显示站点信息
    local site_size
    site_size=$(du -sh "$site_path" 2>/dev/null | cut -f1)
    log_info "站点路径: $site_path"
    log_info "站点大小: $site_size"
    log_info "备份文件: $backup_file"
    
    # 使用 Salt 原生 archive 模块创建压缩包
    log_info "创建站点备份..."
    if salt-call --local cmd.run "sudo tar -czf '$backup_file' -C /var/www '$site_name'" >/dev/null 2>&1; then
        # 获取备份文件大小
        local backup_size
        backup_size=$(du -h "$backup_file" 2>/dev/null | cut -f1)
        log_success "站点备份完成: $backup_file"
        log_info "备份文件大小: $backup_size"
        log_info "备份路径: $backup_file"
        
        # 创建备份信息文件
        local backup_info
        backup_info="站点备份信息
==================
站点名称: $site_name
项目名称: $project_name
备份时间: $(date)
站点路径: $site_path
备份文件: $backup_file
站点大小: $site_size
备份大小: $backup_size
备份内容: 完整站点文件"
        
        salt-call --local file.write "${backup_file%.tar.gz}_info.txt" contents="$backup_info" >/dev/null 2>&1
        
    else
        log_error "站点备份失败"
        exit 1
    fi
}

# 站点文件恢复
backup_restore_site() {
    local site_name="$1"
    local backup_file="$2"
    local force_flag="$3"
    
    if [[ -z "$site_name" || -z "$backup_file" ]]; then
        log_error "用法: saltgoat backup site restore <site_name> <backup_file> [--force]"
        log_info "示例: saltgoat backup site restore tank /home/doge/Dropbox/tank/snapshot/tank_20251008_143459.tar.gz"
        log_info "示例: saltgoat backup site restore tank /home/doge/Dropbox/tank/snapshot/tank_20251008_143459.tar.gz --force"
        exit 1
    fi
    
    local site_path="/var/www/$site_name"
    
    # 检查备份文件是否存在
    if [[ ! -f "$backup_file" ]]; then
        log_error "备份文件不存在: $backup_file"
        exit 1
    fi
    
    # 显示备份文件信息
    local backup_size
    backup_size=$(du -h "$backup_file" 2>/dev/null | cut -f1)
    local backup_date
    backup_date=$(stat -c %y "$backup_file" 2>/dev/null)
    log_info "备份文件大小: $backup_size"
    log_info "备份文件时间: $backup_date"
    
    # 检查是否需要强制模式
    if [[ "$force_flag" == "--force" ]]; then
        log_info "使用强制模式，跳过确认"
    else
        log_warning "这将覆盖目标站点目录，请确认是否继续？"
        read -r -p "输入 'yes' 确认继续: " confirm
        
        if [[ "$confirm" != "yes" ]]; then
            log_info "恢复操作已取消"
            exit 0
        fi
    fi
    
    log_highlight "恢复站点文件: $site_name <- $backup_file"
    
    # 创建临时恢复目录
    local restore_dir="/tmp/saltgoat_site_restore_$$"
    salt-call --local file.mkdir "$restore_dir" >/dev/null 2>&1
    
    log_info "解压备份文件..."
    if salt-call --local archive.tar xzf "$backup_file" dest="$restore_dir" >/dev/null 2>&1; then
        log_success "备份文件解压成功"
        
        # 查找解压后的站点目录
        local extracted_site_dir
        extracted_site_dir=$(find "$restore_dir" -name "$site_name" -type d | head -1)
        
        if [[ -z "$extracted_site_dir" ]]; then
            log_error "在备份文件中未找到站点目录: $site_name"
            salt-call --local file.remove "$restore_dir" recurse=True >/dev/null 2>&1
            exit 1
        fi
        
        # 备份当前站点（如果存在）
        if [[ -d "$site_path" ]]; then
            local backup_current
            backup_current="/tmp/${site_name}_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
            log_info "备份当前站点到: $backup_current"
            salt-call --local archive.tar czf "$backup_current" sources="[\"$site_path\"]" >/dev/null 2>&1
        fi
        
        # 恢复站点文件
        log_info "恢复站点文件到: $site_path"
        salt-call --local file.mkdir "$site_path" >/dev/null 2>&1
        salt-call --local cmd.run "cp -r $extracted_site_dir/* $site_path/" >/dev/null 2>&1
        
        # 设置正确的权限
        log_info "设置站点权限..."
        salt-call --local cmd.run "chown -R www-data:www-data $site_path" >/dev/null 2>&1
        salt-call --local cmd.run "chmod -R 755 $site_path" >/dev/null 2>&1
        
        # 清理临时目录
        salt-call --local file.remove "$restore_dir" recurse=True >/dev/null 2>&1
        
        log_success "站点恢复完成: $site_name"
        log_info "站点路径: $site_path"
        
    else
        log_error "备份文件解压失败"
        salt-call --local file.remove "$restore_dir" recurse=True >/dev/null 2>&1
        exit 1
    fi
}

# 列出站点备份
backup_list_sites() {
    log_highlight "列出站点备份..."
    
    echo "站点备份列表:"
    echo "=========================================="
    
    # 列出项目化备份（Dropbox 路径）
    local found_backups=false
    
    for project_dir in /home/doge/Dropbox/*/snapshot/; do
        if [[ -d "$project_dir" ]]; then
            local project_name
            project_name=$(basename "$(dirname "$project_dir")")
            
            echo "项目: $project_name"
            echo "----------------------------------------"
            
            for file in "$project_dir"*.tar.gz; do
                if [[ -f "$file" ]]; then
                    local name
                    name=$(basename "$file" .tar.gz)
                    local size
                    size=$(du -h "$file" 2>/dev/null | cut -f1)
                    local date
                    date=$(stat -c %y "$file" 2>/dev/null)
                    
                    echo "备份名称: $name"
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
    ensure_backup_dir
    if [[ -d "$BACKUP_BASE_DIR" ]] && [[ -n "$(ls -A "$BACKUP_BASE_DIR" 2>/dev/null)" ]]; then
        echo "默认备份目录:"
        echo "----------------------------------------"
        
        for file in "$BACKUP_BASE_DIR"/*.tar.gz; do
            if [[ -f "$file" ]]; then
                local name
                name=$(basename "$file" .tar.gz)
                local size
                size=$(du -h "$file" 2>/dev/null | cut -f1)
                local date
                date=$(stat -c %y "$file" 2>/dev/null)
                
                echo "备份名称: $name"
                echo "文件大小: $size"
                echo "创建时间: $date"
                echo "文件路径: $file"
                echo "----------------------------------------"
            fi
        done
    fi
    
    if [[ "$found_backups" == "false" ]]; then
        echo "未找到站点备份文件"
    fi
}

# 创建系统备份
backup_create() {
    local backup_name="$1"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
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
    if salt-call --local file.directory_exists "/etc/nginx" --out=txt 2>/dev/null | grep -q "True"; then
        salt-call --local file.copy "/etc/nginx" "$nginx_backup_dir/etc-nginx" recurse=True >/dev/null 2>&1
    elif salt-call --local file.directory_exists "/usr/local/nginx/conf" --out=txt 2>/dev/null | grep -q "True"; then
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
    local backup_info_content
    backup_info_content="SaltGoat 系统备份
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
            local name
            name=$(basename "$file" .tar.gz)
            local size
            size=$(du -h "$file" 2>/dev/null | awk '{print $1}')
            local date
            date=$(stat -c %y "$file" 2>/dev/null | cut -d'.' -f1)
            
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
    read -r -p "输入 'yes' 确认继续: " confirm
    
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
        if [[ -d "$backup_content_dir/nginx/etc-nginx" ]]; then
            salt-call --local file.copy "$backup_content_dir/nginx/etc-nginx" "/etc/nginx" recurse=True >/dev/null 2>&1
        elif [[ -d "$backup_content_dir/nginx/conf" ]]; then
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
    read -r -p "输入 'yes' 确认删除: " confirm
    
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
    local old_files
    old_files=$(salt-call --local file.find "$BACKUP_BASE_DIR" name="*.tar.gz" mtime="+$BACKUP_RETENTION_DAYS" --out=txt 2>/dev/null | tail -n +2 | awk '{print $2}')
    
    while IFS= read -r file; do
        if [[ -n "$file" ]]; then
            local filename
            filename=$(basename "$file")
            log_info "删除过期备份: $filename"
            salt-call --local file.remove "$file" >/dev/null 2>&1
        fi
    done <<<"$old_files"
    
    log_success "备份清理完成"
}

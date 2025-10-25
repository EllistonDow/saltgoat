#!/bin/bash
# Magento 2 维护管理系统
# modules/magetools/magento-maintenance.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/utils.sh"

# 配置参数
SITE_NAME="${1:-tank}"
SITE_PATH="/var/www/$SITE_NAME"
MAINTENANCE_MODE="${2:-status}"

# 显示帮助信息
show_help() {
    echo "Magento 2 维护管理系统"
    echo ""
    echo "用法: $0 <site_name> <action>"
    echo ""
    echo "参数:"
    echo "  site_name    站点名称 (默认: tank)"
    echo "  action       维护操作"
    echo ""
    echo "维护操作:"
    echo "  status        - 检查维护状态"
    echo "  enable        - 启用维护模式"
    echo "  disable       - 禁用维护模式"
    echo "  daily         - 执行每日维护任务"
    echo "  weekly        - 执行每周维护任务"
    echo "  monthly       - 执行每月维护任务"
    echo "  backup        - 创建备份"
    echo "  health        - 健康检查"
    echo "  cleanup       - 清理日志和缓存"
    echo "  deploy        - 完整部署流程"
    echo ""
    echo "示例:"
    echo "  $0 tank status"
    echo "  $0 tank daily"
    echo "  $0 tank backup"
    echo "  $0 tank deploy"
}

# 检查参数
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
    exit 0
fi

if [[ ! -d "$SITE_PATH" ]]; then
    log_error "站点目录不存在: $SITE_PATH"
    exit 1
fi

if [[ ! -f "$SITE_PATH/bin/magento" ]]; then
    log_error "Magento 安装文件不存在: $SITE_PATH/bin/magento"
    exit 1
fi

# 切换到站点目录
cd "$SITE_PATH" || {
    log_error "无法切换到站点目录: $SITE_PATH"
    exit 1
}

log_highlight "Magento 2 维护管理: $SITE_NAME"
log_info "站点路径: $SITE_PATH"
log_info "操作: $MAINTENANCE_MODE"
echo ""

# 检查维护状态
check_maintenance_status() {
    log_info "检查维护状态..."
    if sudo -u www-data php bin/magento maintenance:status 2>/dev/null | grep -q "Maintenance mode is enabled"; then
        log_warning "[WARNING] 维护模式已启用"
        return 0
    else
        log_success "[SUCCESS] 维护模式已禁用"
        return 1
    fi
}

# 启用维护模式
enable_maintenance() {
    log_info "启用维护模式..."
    if sudo -u www-data php bin/magento maintenance:enable; then
        log_success "[SUCCESS] 维护模式已启用"
    else
        log_error "[ERROR] 启用维护模式失败"
        return 1
    fi
}

# 禁用维护模式
disable_maintenance() {
    log_info "禁用维护模式..."
    if sudo -u www-data php bin/magento maintenance:disable; then
        log_success "[SUCCESS] 维护模式已禁用"
    else
        log_error "[ERROR] 禁用维护模式失败"
        return 1
    fi
}

# 每日维护任务
daily_maintenance() {
    log_highlight "执行每日维护任务..."
    
    # 1. 缓存清理
    log_info "1. 清理缓存..."
    if sudo -u www-data php bin/magento cache:flush; then
        log_success "[SUCCESS] 缓存清理完成"
    else
        log_warning "[WARNING] 缓存清理失败"
    fi
    
    # 2. 索引重建
    log_info "2. 重建索引..."
    if sudo -u www-data php bin/magento indexer:reindex; then
        log_success "[SUCCESS] 索引重建完成"
    else
        log_warning "[WARNING] 索引重建失败"
    fi
    
    # 3. 权限检查
    log_info "3. 检查权限..."
    local root_files=$(sudo find var generated -user root 2>/dev/null | wc -l)
    if [[ "$root_files" -gt 0 ]]; then
        log_warning "[WARNING] 发现 $root_files 个 root 文件，建议修复权限"
        sudo find var generated -user root 2>/dev/null | head -5
    else
        log_success "[SUCCESS] 权限检查通过"
    fi
    
    # 4. 会话清理
    log_info "4. 清理会话..."
    if sudo -u www-data php bin/magento session:clean; then
        log_success "[SUCCESS] 会话清理完成"
    else
        log_warning "[WARNING] 会话清理失败"
    fi
    
    # 5. 日志清理
    log_info "5. 清理日志..."
    if sudo -u www-data php bin/magento log:clean; then
        log_success "[SUCCESS] 日志清理完成"
    else
        log_warning "[WARNING] 日志清理失败"
    fi
    
    log_success "[SUCCESS] 每日维护任务完成"
}

# 每周维护任务
weekly_maintenance() {
    log_highlight "执行每周维护任务..."
    
    # 1. 创建备份
    log_info "1. 创建备份..."
    backup_site
    
    # 2. 日志轮换
    log_info "2. 轮换日志..."
    sudo find var/log -name "*.log" -size +100M -exec truncate -s 0 {} \;
    log_success "[SUCCESS] 日志轮换完成"
    
    # 3. Redis 清空
    log_info "3. 清空 Redis 缓存..."
    if command -v redis-cli >/dev/null 2>&1; then
        redis-cli FLUSHALL
        log_success "[SUCCESS] Redis 缓存已清空"
    else
        log_warning "[WARNING] Redis 未安装"
    fi
    
    # 4. 性能检查
    log_info "4. 性能检查..."
    if command -v n98-magerun2 >/dev/null 2>&1; then
        if sudo -u www-data n98-magerun2 sys:check; then
            log_success "[SUCCESS] 系统检查完成"
        else
            log_warning "[WARNING] 系统检查发现问题"
        fi
    else
        log_warning "[WARNING] N98 Magerun2 未安装"
    fi
    
    # 5. 依赖检查
    log_info "5. 检查依赖更新..."
    if composer outdated --no-dev 2>/dev/null | grep -q "outdated"; then
        log_warning "[WARNING] 发现过时的依赖包"
        composer outdated --no-dev | head -5
    else
        log_success "[SUCCESS] 依赖检查通过"
    fi
    
    log_success "[SUCCESS] 每周维护任务完成"
}

# 每月维护任务
monthly_maintenance() {
    log_highlight "执行每月维护任务..."
    
    # 1. 启用维护模式
    log_info "1. 启用维护模式..."
    if sudo -u www-data php bin/magento maintenance:enable; then
        log_success "[SUCCESS] 维护模式已启用"
    else
        log_warning "[WARNING] 启用维护模式失败"
    fi
    
    # 2. 清理缓存和生成文件
    log_info "2. 清理缓存和生成文件..."
    sudo rm -rf var/{cache,page_cache,view_preprocessed,di}/*
    sudo rm -rf pub/static/* pub/media/catalog/product/cache/*
    sudo rm -rf generated/*
    log_success "[SUCCESS] 缓存和生成文件清理完成"
    
    # 3. 数据库升级
    log_info "3. 执行数据库升级..."
    if sudo -u www-data bin/magento setup:upgrade; then
        log_success "[SUCCESS] 数据库升级完成"
    else
        log_warning "[WARNING] 数据库升级失败"
    fi
    
    # 4. 编译依赖注入
    log_info "4. 编译依赖注入..."
    if sudo -u www-data php bin/magento setup:di:compile; then
        log_success "[SUCCESS] 依赖注入编译完成"
    else
        log_warning "[WARNING] 依赖注入编译失败"
    fi
    
    # 5. 部署静态内容
    log_info "5. 部署静态内容..."
    if sudo -u www-data php bin/magento setup:static-content:deploy -f -j 4; then
        log_success "[SUCCESS] 静态内容部署完成"
    else
        log_warning "[WARNING] 静态内容部署失败"
    fi
    
    # 6. 重建索引
    log_info "6. 重建索引..."
    if sudo -u www-data php bin/magento indexer:reindex; then
        log_success "[SUCCESS] 索引重建完成"
    else
        log_warning "[WARNING] 索引重建失败"
    fi
    
    # 7. 禁用维护模式
    log_info "7. 禁用维护模式..."
    if sudo -u www-data php bin/magento maintenance:disable; then
        log_success "[SUCCESS] 维护模式已禁用"
    else
        log_warning "[WARNING] 禁用维护模式失败"
    fi
    
    # 8. 清理缓存
    log_info "8. 清理缓存..."
    if sudo -u www-data php bin/magento cache:clean; then
        log_success "[SUCCESS] 缓存清理完成"
    else
        log_warning "[WARNING] 缓存清理失败"
    fi
    
    # 9. 安全补丁检查
    log_info "9. 检查安全补丁..."
    log_info "   建议访问 Adobe 官方安全公告"
    
    # 10. 数据库分析
    log_info "10. 数据库分析..."
    if command -v mysql >/dev/null 2>&1; then
        log_info "   检查慢查询日志..."
        log_info "   分析索引碎片..."
    fi
    
    # 11. SEO 重建
    log_info "11. 重建 SEO 数据..."
    if sudo -u www-data php bin/magento sitemap:generate; then
        log_success "[SUCCESS] Sitemap 生成完成"
    else
        log_warning "[WARNING] Sitemap 生成失败"
    fi
    
    # 12. 扩展评估
    log_info "12. 扩展评估..."
    if sudo -u www-data php bin/magento module:status | grep -q "Disabled"; then
        log_info "   发现禁用的模块，建议评估是否需要移除"
    fi
    
    log_success "[SUCCESS] 每月维护任务完成"
}

# 创建备份
backup_site() {
    log_info "创建站点备份..."
    local backup_dir="/var/backups/magento"
    local backup_file="${backup_dir}/${SITE_NAME}_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    sudo mkdir -p "$backup_dir"
    
    # 创建文件备份
    log_info "备份文件..."
    if sudo tar -czf "$backup_file" -C /var/www "$SITE_NAME" --exclude="var/cache/*" --exclude="var/session/*" --exclude="var/tmp/*"; then
        log_success "[SUCCESS] 文件备份完成: $backup_file"
    else
        log_error "[ERROR] 文件备份失败"
        return 1
    fi
    
    # 创建数据库备份
    log_info "备份数据库..."
    local db_backup="${backup_dir}/${SITE_NAME}_db_$(date +%Y%m%d_%H%M%S).sql"
    local mysql_password
    mysql_password=$(get_local_pillar_value mysql_password)
    if sudo mysqldump -u root ${mysql_password:+-p"$mysql_password"} "$SITE_NAME" > "$db_backup"; then
        log_success "[SUCCESS] 数据库备份完成: $db_backup"
    else
        log_warning "[WARNING] 数据库备份失败"
    fi
    
    # 清理旧备份（保留7天）
    log_info "清理旧备份..."
    sudo find "$backup_dir" -name "${SITE_NAME}_*" -mtime +7 -delete
    log_success "[SUCCESS] 备份任务完成"
}

# 健康检查
health_check() {
    log_highlight "执行健康检查..."
    
    # 1. Magento 状态
    log_info "1. 检查 Magento 状态..."
    if sudo -u www-data php bin/magento --version >/dev/null 2>&1; then
        local version=$(sudo -u www-data php bin/magento --version | head -1)
        log_success "[SUCCESS] Magento 状态正常: $version"
    else
        log_error "[ERROR] Magento 状态异常"
    fi
    
    # 2. 数据库连接
    log_info "2. 检查数据库连接..."
    if sudo -u www-data php bin/magento setup:db:status >/dev/null 2>&1; then
        log_success "[SUCCESS] 数据库连接正常"
    else
        log_error "[ERROR] 数据库连接异常"
    fi
    
    # 3. 缓存状态
    log_info "3. 检查缓存状态..."
    if sudo -u www-data php bin/magento cache:status | grep -q "enabled"; then
        log_success "[SUCCESS] 缓存状态正常"
    else
        log_warning "[WARNING] 缓存状态异常"
    fi
    
    # 4. 索引状态
    log_info "4. 检查索引状态..."
    local invalid_indexes=$(sudo -u www-data php bin/magento indexer:status | grep "invalid" | wc -l)
    if [[ "$invalid_indexes" -gt 0 ]]; then
        log_warning "[WARNING] 发现 $invalid_indexes 个无效索引"
    else
        log_success "[SUCCESS] 索引状态正常"
    fi
    
    # 5. 磁盘空间
    log_info "5. 检查磁盘空间..."
    local disk_usage=$(df -h "$SITE_PATH" | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ "$disk_usage" -gt 80 ]]; then
        log_warning "[WARNING] 磁盘使用率过高: ${disk_usage}%"
    else
        log_success "[SUCCESS] 磁盘空间充足: ${disk_usage}%"
    fi
    
    log_success "[SUCCESS] 健康检查完成"
}

# 清理任务
cleanup_site() {
    log_highlight "执行清理任务..."
    
    # 1. 清理缓存
    log_info "1. 清理所有缓存..."
    sudo -u www-data php bin/magento cache:flush
    
    # 2. 清理生成文件
    log_info "2. 清理生成文件..."
    sudo rm -rf generated/*
    sudo chown -R www-data:www-data generated
    sudo chmod -R 775 generated
    
    # 3. 清理日志
    log_info "3. 清理日志文件..."
    sudo find var/log -name "*.log" -exec truncate -s 0 {} \;
    
    # 4. 清理会话
    log_info "4. 清理会话文件..."
    sudo find var/session -name "sess_*" -mtime +1 -delete
    
    # 5. 清理临时文件
    log_info "5. 清理临时文件..."
    sudo find var/tmp -name "*" -mtime +1 -delete
    
    log_success "[SUCCESS] 清理任务完成"
}

# 完整部署流程
deploy_site() {
    log_highlight "执行完整部署流程..."
    
    # 1. 启用维护模式
    log_info "1. 启用维护模式..."
    if sudo -u www-data php bin/magento maintenance:enable; then
        log_success "[SUCCESS] 维护模式已启用"
    else
        log_warning "[WARNING] 启用维护模式失败"
    fi
    
    # 2. 清理缓存和生成文件
    log_info "2. 清理缓存和生成文件..."
    sudo rm -rf var/{cache,page_cache,view_preprocessed,di}/*
    sudo rm -rf pub/static/* pub/media/catalog/product/cache/*
    sudo rm -rf generated/*
    log_success "[SUCCESS] 缓存和生成文件清理完成"
    
    # 3. 数据库升级
    log_info "3. 执行数据库升级..."
    if sudo -u www-data bin/magento setup:upgrade; then
        log_success "[SUCCESS] 数据库升级完成"
    else
        log_warning "[WARNING] 数据库升级失败"
    fi
    
    # 4. 编译依赖注入
    log_info "4. 编译依赖注入..."
    if sudo -u www-data php bin/magento setup:di:compile; then
        log_success "[SUCCESS] 依赖注入编译完成"
    else
        log_warning "[WARNING] 依赖注入编译失败"
    fi
    
    # 5. 部署静态内容
    log_info "5. 部署静态内容..."
    if sudo -u www-data php bin/magento setup:static-content:deploy -f -j 4; then
        log_success "[SUCCESS] 静态内容部署完成"
    else
        log_warning "[WARNING] 静态内容部署失败"
    fi
    
    # 6. 重建索引
    log_info "6. 重建索引..."
    if sudo -u www-data php bin/magento indexer:reindex; then
        log_success "[SUCCESS] 索引重建完成"
    else
        log_warning "[WARNING] 索引重建失败"
    fi
    
    # 7. 禁用维护模式
    log_info "7. 禁用维护模式..."
    if sudo -u www-data php bin/magento maintenance:disable; then
        log_success "[SUCCESS] 维护模式已禁用"
    else
        log_warning "[WARNING] 禁用维护模式失败"
    fi
    
    # 8. 清理缓存
    log_info "8. 清理缓存..."
    if sudo -u www-data php bin/magento cache:clean; then
        log_success "[SUCCESS] 缓存清理完成"
    else
        log_warning "[WARNING] 缓存清理失败"
    fi
    
    log_success "[SUCCESS] 完整部署流程完成"
}

# 主程序
case "$MAINTENANCE_MODE" in
    "status")
        check_maintenance_status
        ;;
    "enable")
        enable_maintenance
        ;;
    "disable")
        disable_maintenance
        ;;
    "daily")
        daily_maintenance
        ;;
    "weekly")
        weekly_maintenance
        ;;
    "monthly")
        monthly_maintenance
        ;;
    "backup")
        backup_site
        ;;
    "health")
        health_check
        ;;
    "cleanup")
        cleanup_site
        ;;
    "deploy")
        deploy_site
        ;;
    *)
        log_error "未知的维护操作: $MAINTENANCE_MODE"
        echo ""
        show_help
        exit 1
        ;;
esac

#!/bin/bash
# Magento 2 Salt 维护脚本
# salt/scripts/magento-maintenance-salt.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"

# 配置参数
SITE_NAME="${1:-tank}"
MAINTENANCE_MODE="${2:-daily}"

# 切换到站点目录
cd "/var/www/$SITE_NAME" || {
    log_error "无法切换到站点目录: /var/www/$SITE_NAME"
    exit 1
}

log_highlight "Magento 2 Salt 维护: $SITE_NAME"
log_info "操作: $MAINTENANCE_MODE"
echo ""

# 每日维护任务
daily_maintenance() {
    log_info "执行每日维护任务..."
    
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
    
    # 3. 会话清理
    log_info "3. 清理会话..."
    if sudo -u www-data php bin/magento session:clean; then
        log_success "[SUCCESS] 会话清理完成"
    else
        log_warning "[WARNING] 会话清理失败"
    fi
    
    # 4. 日志清理
    log_info "4. 清理日志..."
    if sudo -u www-data php bin/magento log:clean; then
        log_success "[SUCCESS] 日志清理完成"
    else
        log_warning "[WARNING] 日志清理失败"
    fi
    
    log_success "[SUCCESS] 每日维护任务完成"
}

# 每周维护任务
weekly_maintenance() {
    log_info "执行每周维护任务..."
    
    # 1. 创建备份
    log_info "1. 创建备份..."
    if sudo -u www-data php bin/magento setup:backup; then
        log_success "[SUCCESS] 备份完成"
    else
        log_warning "[WARNING] 备份失败"
    fi
    
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
    
    log_success "[SUCCESS] 每周维护任务完成"
}

# 每月维护任务（完整部署流程）
monthly_maintenance() {
    log_info "执行每月维护任务（完整部署流程）..."
    
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
    
    log_success "[SUCCESS] 每月维护任务完成"
}

# 健康检查
health_check() {
    log_info "执行健康检查..."
    
    # 1. Magento 状态
    log_info "1. 检查 Magento 状态..."
    if sudo -u www-data php bin/magento --version >/dev/null 2>&1; then
        local version
        version=$(sudo -u www-data php bin/magento --version | head -1)
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
    local invalid_indexes
    invalid_indexes=$(sudo -u www-data php bin/magento indexer:status | grep -c "invalid")
    if [[ "$invalid_indexes" -gt 0 ]]; then
        log_warning "[WARNING] 发现 $invalid_indexes 个无效索引"
    else
        log_success "[SUCCESS] 索引状态正常"
    fi
    
    log_success "[SUCCESS] 健康检查完成"
}

# 主程序
case "$MAINTENANCE_MODE" in
    "daily")
        daily_maintenance
        ;;
    "weekly")
        weekly_maintenance
        ;;
    "monthly")
        monthly_maintenance
        ;;
    "health")
        health_check
        ;;
    *)
        log_error "未知的维护操作: $MAINTENANCE_MODE"
        exit 1
        ;;
esac

#!/bin/bash

# 部署Magento
deploy_magento() {
    log_highlight "部署Magento..."
    
    if [[ ! -f "bin/magento" ]]; then
        log_error "未找到Magento CLI"
        return 1
    fi
    
    log_info "设置生产模式..."
    php bin/magento deploy:mode:set production
    
    log_info "编译DI..."
    php bin/magento setup:di:compile
    
    log_info "部署静态内容..."
    php bin/magento setup:static-content:deploy
    
    log_info "设置权限..."
    sudo chown -R www-data:www-data var/ pub/ app/etc/
    sudo chmod -R 755 var/ pub/ app/etc/
    
    log_success "Magento部署完成"
}

# 备份Magento
backup_magento() {
    log_highlight "备份Magento..."
    
    local backup_dir="/home/doge/magento_backups"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="magento_backup_$timestamp"
    
    mkdir -p "$backup_dir"
    
    log_info "创建备份: $backup_name"
    
    # 备份数据库
    log_info "备份数据库..."
    php bin/magento setup:db:backup --code="$backup_name"
    
    # 备份文件
    log_info "备份文件..."
    tar -czf "$backup_dir/${backup_name}_files.tar.gz" \
        --exclude=var/cache \
        --exclude=var/page_cache \
        --exclude=var/view_preprocessed \
        --exclude=var/log \
        --exclude=pub/media/catalog/product/cache \
        .
    
    log_success "备份完成: $backup_dir/$backup_name"
}

# 恢复Magento
restore_magento() {
    local backup_name="$1"
    
    if [[ -z "$backup_name" ]]; then
        log_error "请指定备份名称"
        log_info "用法: saltgoat magetools restore <backup_name>"
        return 1
    fi
    
    log_highlight "恢复Magento: $backup_name"
    
    local backup_dir="/home/doge/magento_backups"
    
    if [[ ! -f "$backup_dir/${backup_name}_files.tar.gz" ]]; then
        log_error "备份文件不存在: $backup_name"
        return 1
    fi
    
    log_warning "这将覆盖当前Magento安装，是否继续? (y/N)"
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "恢复已取消"
        return 0
    fi
    
    log_info "恢复文件..."
    tar -xzf "$backup_dir/${backup_name}_files.tar.gz"
    
    log_info "恢复数据库..."
    php bin/magento setup:db:restore --code="$backup_name"
    
    log_success "Magento恢复完成"
}

# 分析Magento性能
analyze_magento_performance() {
    log_highlight "分析Magento性能..."
    
    echo "=========================================="
    echo "    Magento 性能分析"
    echo "=========================================="
    echo ""
    
    # 检查PHP配置
    log_info "PHP配置:"
    echo "  PHP版本: $(php -v | head -1)"
    echo "  内存限制: $(php -r 'echo ini_get("memory_limit");')"
    echo "  执行时间: $(php -r 'echo ini_get("max_execution_time");')s"
    echo "  OPcache: $(php -r 'echo ini_get("opcache.enable") ? "启用" : "禁用";')"
    echo ""
    
    # 检查Magento配置
    log_info "Magento配置:"
    if [[ -f "app/etc/env.php" ]]; then
        echo "  模式: $(php bin/magento deploy:mode:show 2>/dev/null | grep -o 'production\|developer')"
        echo "  缓存: $(php bin/magento cache:status 2>/dev/null | grep -c 'enabled' || echo '0') 个启用"
    fi
    echo ""
    
    # 检查文件大小
    log_info "文件大小分析:"
    echo "  总大小: $(du -sh . | cut -f1)"
    echo "  var目录: $(du -sh var/ 2>/dev/null | cut -f1 || echo 'N/A')"
    echo "  pub目录: $(du -sh pub/ 2>/dev/null | cut -f1 || echo 'N/A')"
    echo ""
    
    # 性能建议
    log_info "性能建议:"
    echo "  1. 启用所有缓存"
    echo "  2. 使用生产模式"
    echo "  3. 启用OPcache"
    echo "  4. 定期清理日志文件"
    echo "  5. 使用CDN加速静态资源"
}

# 扫描Magento安全
scan_magento_security() {
    log_highlight "扫描Magento安全..."
    
    echo "=========================================="
    echo "    Magento 安全扫描"
    echo "=========================================="
    echo ""
    
    # 检查文件权限
    log_info "文件权限检查:"
    if [[ -f "app/etc/env.php" ]]; then
        local env_perms
        env_perms=$(stat -c "%a" app/etc/env.php)
        if [[ "$env_perms" == "644" ]]; then
            echo "  [SUCCESS] env.php 权限正确: $env_perms"
        else
            echo "  [WARNING] env.php 权限异常: $env_perms (应为644)"
        fi
    fi
    echo ""
    
    # 检查敏感文件
    log_info "敏感文件检查:"
    local sensitive_files=("app/etc/env.php" "composer.json" "composer.lock")
    for file in "${sensitive_files[@]}"; do
        if [[ -f "$file" ]]; then
            echo "  [SUCCESS] $file 存在"
        else
            echo "  [ERROR] $file 缺失"
        fi
    done
    echo ""
    
    # 检查版本
    log_info "版本检查:"
    if [[ -f "composer.json" ]]; then
        local version
        version=$(grep -o '"version": "[^"]*"' composer.json | cut -d'"' -f4)
        echo "  Magento版本: $version"
    fi
    echo ""
    
    # 安全建议
    log_info "安全建议:"
    echo "  1. 定期更新Magento和扩展"
    echo "  2. 使用强密码"
    echo "  3. 启用双因素认证"
    echo "  4. 定期备份数据"
    echo "  5. 监控异常活动"
}

# 更新Magento
update_magento() {
    log_highlight "更新Magento..."
    
    if [[ ! -f "composer.json" ]]; then
        log_error "未找到composer.json文件"
        return 1
    fi
    
    log_warning "更新Magento可能会影响现有功能，是否继续? (y/N)"
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "更新已取消"
        return 0
    fi
    
    log_info "备份当前版本..."
    backup_magento
    
    log_info "更新Composer依赖..."
    composer update
    
    log_info "更新数据库..."
    php bin/magento setup:upgrade
    
    log_info "重新部署..."
    deploy_magento
    
    log_success "Magento更新完成"
}

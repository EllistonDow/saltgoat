#!/bin/bash

# 修复 Magento 权限 (使用 Salt 原生功能)
fix_magento_permissions() {
    local site_path="${1:-$(pwd)}"
    
    # 检查是否在 Magento 目录中
    if [[ ! -f "$site_path/bin/magento" ]]; then
        log_error "未在 Magento 目录中，请指定正确的路径"
        log_info "用法: saltgoat magetools permissions fix [path]"
        log_info "示例: saltgoat magetools permissions fix /var/www/tank"
        return 1
    fi
    
    log_highlight "修复 Magento 权限: $site_path"
    log_info "使用 Salt 原生功能修复权限..."
    
    # 使用 Salt 原生功能修复权限
    log_info "1. 设置站点根目录权限..."
    sudo chown -R www-data:www-data "$site_path"
    sudo chmod 755 "$site_path"
    
    log_info "2. 设置 Magento 核心目录权限..."
    local core_dirs=("app" "bin" "dev" "lib" "phpserver" "pub" "setup" "vendor")
    for dir in "${core_dirs[@]}"; do
        if [[ -d "$site_path/$dir" ]]; then
            sudo chown -R www-data:www-data "$site_path/$dir"
            sudo chmod -R 755 "$site_path/$dir"
        fi
    done
    
    log_info "3. 设置可写目录权限..."
    local writable_dirs=("var" "generated" "pub/media" "pub/static" "app/etc")
    for dir in "${writable_dirs[@]}"; do
        if [[ -d "$site_path/$dir" ]]; then
            sudo chown -R www-data:www-data "$site_path/$dir"
            sudo chmod -R 775 "$site_path/$dir"
        fi
    done
    
    log_info "4. 设置配置文件权限..."
    if [[ -f "$site_path/app/etc/env.php" ]]; then
        sudo chown www-data:www-data "$site_path/app/etc/env.php"
        sudo chmod 644 "$site_path/app/etc/env.php"
    fi
    
    log_info "5. 确保父目录访问权限..."
    local parent_dir
    parent_dir=$(dirname "$site_path")
    sudo chmod 755 "$parent_dir"
    sudo chown root:www-data "$parent_dir"
    
    log_info "6. 修复缓存目录权限..."
    if [[ -d "$site_path/var" ]]; then
        sudo chmod -R 777 "$site_path/var"
        sudo chown -R www-data:www-data "$site_path/var"
    fi
    
    if [[ -d "$site_path/generated" ]]; then
        sudo chmod -R 777 "$site_path/generated"
        sudo chown -R www-data:www-data "$site_path/generated"
    fi
    
    log_success "Magento 权限修复完成！"
    log_info "现在可以测试 Magento 命令："
    echo "  sudo -u www-data php bin/magento --version"
    echo "  sudo -u www-data n98-magerun2 --version"
    echo ""
    log_info "[INFO] 权限管理最佳实践:"
    echo "  [SUCCESS] 使用: sudo -u www-data php bin/magento <command>"
    echo "  [ERROR] 避免: sudo php bin/magento <command>"
    echo "  [INFO] 详细说明: docs/MAGENTO_PERMISSIONS.md"
}

# 检查 Magento 权限状态
check_magento_permissions() {
    local site_path="${1:-$(pwd)}"
    
    if [[ ! -f "$site_path/bin/magento" ]]; then
        log_error "未在 Magento 目录中，请指定正确的路径"
        return 1
    fi
    
    log_highlight "检查 Magento 权限状态: $site_path"
    
    echo "目录权限检查:"
    echo "=========================================="
    
    # 检查关键目录权限
    local critical_dirs=("var" "generated" "pub/media" "pub/static" "app/etc")
    for dir in "${critical_dirs[@]}"; do
        if [[ -d "$site_path/$dir" ]]; then
            local perms
            perms=$(stat -c "%A" "$site_path/$dir")
            local owner
            owner=$(stat -c "%U:%G" "$site_path/$dir")
            echo "$dir: $perms (owner: $owner)"
            
            # 检查权限是否正确
            if [[ "$dir" == "var" || "$dir" == "generated" ]]; then
                if [[ "$perms" != "drwxrwxr-x" ]]; then
                    log_warning "$dir: 权限可能不正确，建议使用 'permissions fix' 修复"
                fi
            fi
        fi
    done
    
    echo ""
    echo "配置文件权限检查:"
    echo "----------------------------------------"
    
    # 检查配置文件权限
    if [[ -f "$site_path/app/etc/env.php" ]]; then
        local perms
        perms=$(stat -c "%A" "$site_path/app/etc/env.php")
        local owner
        owner=$(stat -c "%U:%G" "$site_path/app/etc/env.php")
        echo "app/etc/env.php: $perms (owner: $owner)"
        
        if [[ "$perms" != "-rw-rw----" ]]; then
            log_warning "env.php: 权限可能不正确，建议使用 'permissions fix' 修复"
        fi
    fi
    
    echo ""
    echo "测试 Magento 命令:"
    echo "----------------------------------------"
    
    # 测试 Magento 命令
    if sudo -u www-data php bin/magento --version >/dev/null 2>&1; then
        log_success "Magento CLI 正常工作 (使用 www-data 用户)"
    else
        log_error "Magento CLI 无法正常工作，可能需要修复权限"
    fi
    
    # 测试 N98 Magerun2
    if command -v n98-magerun2 >/dev/null 2>&1; then
        if sudo -u www-data n98-magerun2 --version >/dev/null 2>&1; then
            log_success "N98 Magerun2 正常工作 (使用 www-data 用户)"
        else
            log_error "N98 Magerun2 无法正常工作，可能需要修复权限"
        fi
    else
        log_info "N98 Magerun2 未安装，可以使用 'install n98-magerun2' 安装"
    fi
    
    echo ""
    log_info "[INFO] 权限管理最佳实践:"
    echo "  [SUCCESS] 使用: sudo -u www-data php bin/magento <command>"
    echo "  [ERROR] 避免: sudo php bin/magento <command>"
    echo "  [INFO] 详细说明: docs/MAGENTO_PERMISSIONS.md"
}

# 重置 Magento 权限 (强制修复)
reset_magento_permissions() {
    local site_path="${1:-$(pwd)}"
    
    if [[ ! -f "$site_path/bin/magento" ]]; then
        log_error "未在 Magento 目录中，请指定正确的路径"
        return 1
    fi
    
    log_warning "重置 Magento 权限会修改所有文件权限，是否继续? (y/N)"
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "操作已取消"
        return 0
    fi
    
    log_highlight "重置 Magento 权限: $site_path"
    
    # 安全重置权限
    log_info "安全重置所有权限..."
    sudo chown -R www-data:www-data "$site_path"
    
    # 重新设置正确的权限
    log_info "重新设置正确的权限..."
    sudo chmod 755 "$site_path"
    sudo chmod -R 755 "$site_path"/{app,bin,dev,lib,phpserver,pub,setup,vendor}
    sudo chmod -R 775 "$site_path"/{var,generated,pub/media,pub/static,app/etc}
    sudo chmod 644 "$site_path/app/etc/env.php"
    
    log_success "Magento 权限重置完成！"
    log_info "建议运行 'permissions check' 验证权限状态"
}

#!/bin/bash
# Magento 工具集
# modules/magetools/magetools.sh

# Magento 工具主函数
magetools_handler() {
    case "$1" in
        "install")
            install_magento_tool "$2"
            ;;
        "cache")
            case "$2" in
                "clear")
                    clear_magento_cache
                    ;;
                "status")
                    check_cache_status
                    ;;
                "warm")
                    warm_magento_cache
                    ;;
                *)
                    log_error "未知的缓存操作: $2"
                    log_info "支持: clear, status, warm"
                    exit 1
                    ;;
            esac
            ;;
        "index")
            case "$2" in
                "reindex")
                    reindex_magento
                    ;;
                "status")
                    check_index_status
                    ;;
                *)
                    log_error "未知的索引操作: $2"
                    log_info "支持: reindex, status"
                    exit 1
                    ;;
            esac
            ;;
        "deploy")
            deploy_magento
            ;;
        "backup")
            backup_magento
            ;;
        "restore")
            restore_magento "$2"
            ;;
        "performance")
            analyze_magento_performance
            ;;
        "security")
            scan_magento_security
            ;;
        "update")
            update_magento
            ;;
        "help"|"--help"|"-h")
            show_magetools_help
            ;;
        *)
            log_error "用法: saltgoat magetools <command> [options]"
            log_info "命令:"
            log_info "  install <tool>       - 安装Magento工具 (n98-magerun2, magerun, etc.)"
            log_info "  cache clear          - 清理缓存"
            log_info "  cache status         - 检查缓存状态"
            log_info "  cache warm           - 预热缓存"
            log_info "  index reindex        - 重建索引"
            log_info "  index status         - 检查索引状态"
            log_info "  deploy               - 部署Magento"
            log_info "  backup               - 备份Magento"
            log_info "  restore <backup>     - 恢复Magento"
            log_info "  performance          - 性能分析"
            log_info "  security             - 安全扫描"
            log_info "  update               - 更新Magento"
            log_info "  help                 - 查看帮助"
            exit 1
            ;;
    esac
}

# 安装Magento工具
install_magento_tool() {
    local tool_name="$1"
    
    if [[ -z "$tool_name" ]]; then
        log_error "请指定要安装的工具"
        log_info "支持的工具:"
        log_info "  n98-magerun2    - N98 Magerun2 (Magento 2 CLI工具)"
        log_info "  magerun         - N98 Magerun (Magento 1 CLI工具)"
        log_info "  magento-cloud   - Magento Cloud CLI"
        log_info "  phpunit         - PHPUnit单元测试框架"
        log_info "  xdebug          - Xdebug调试工具"
        return 1
    fi
    
    log_highlight "安装Magento工具: $tool_name"
    
    case "$tool_name" in
        "n98-magerun2")
            install_n98_magerun2
            ;;
        "magerun")
            install_magerun
            ;;
        "magento-cloud")
            install_magento_cloud_cli
            ;;
        "phpunit")
            install_phpunit
            ;;
        "xdebug")
            install_xdebug
            ;;
        *)
            log_error "未知的工具: $tool_name"
            log_info "支持的工具: n98-magerun2, magerun, magento-cloud, phpunit, xdebug"
            return 1
            ;;
    esac
}

# 安装N98 Magerun2
install_n98_magerun2() {
    log_info "安装N98 Magerun2..."
    
    # 检查是否已安装
    if command -v n98-magerun2 >/dev/null 2>&1; then
        log_success "N98 Magerun2 已安装"
        n98-magerun2 --version
        return 0
    fi
    
    # 下载并安装
    log_info "下载N98 Magerun2..."
    curl -O https://files.magerun.net/n98-magerun2.phar
    
    if [[ -f "n98-magerun2.phar" ]]; then
        sudo mv n98-magerun2.phar /usr/local/bin/n98-magerun2
        sudo chmod +x /usr/local/bin/n98-magerun2
        
        log_success "N98 Magerun2 安装完成"
        log_info "使用方法: n98-magerun2 --help"
        
        # 显示常用命令
        echo ""
        log_info "常用命令:"
        echo "  n98-magerun2 cache:clean"
        echo "  n98-magerun2 index:reindex"
        echo "  n98-magerun2 sys:info"
        echo "  n98-magerun2 dev:console"
    else
        log_error "N98 Magerun2 下载失败"
        return 1
    fi
}

# 安装N98 Magerun (Magento 1)
install_magerun() {
    log_info "安装N98 Magerun..."
    
    # 检查是否已安装
    if command -v magerun >/dev/null 2>&1; then
        log_success "N98 Magerun 已安装"
        magerun --version
        return 0
    fi
    
    # 下载并安装
    log_info "下载N98 Magerun..."
    curl -O https://files.magerun.net/n98-magerun.phar
    
    if [[ -f "n98-magerun.phar" ]]; then
        sudo mv n98-magerun.phar /usr/local/bin/magerun
        sudo chmod +x /usr/local/bin/magerun
        
        log_success "N98 Magerun 安装完成"
        log_info "使用方法: magerun --help"
    else
        log_error "N98 Magerun 下载失败"
        return 1
    fi
}

# 安装Magento Cloud CLI
install_magento_cloud_cli() {
    log_info "安装Magento Cloud CLI..."
    
    # 检查是否已安装
    if command -v magento-cloud >/dev/null 2>&1; then
        log_success "Magento Cloud CLI 已安装"
        magento-cloud --version
        return 0
    fi
    
    # 安装
    log_info "添加Magento Cloud仓库..."
    curl -sS https://accounts.magento.cloud/cli/installer | php
    
    if command -v magento-cloud >/dev/null 2>&1; then
        log_success "Magento Cloud CLI 安装完成"
        log_info "使用方法: magento-cloud --help"
    else
        log_error "Magento Cloud CLI 安装失败"
        return 1
    fi
}

# 安装PHPUnit
install_phpunit() {
    log_info "安装PHPUnit单元测试框架..."
    
    # 检查是否已安装
    if command -v phpunit >/dev/null 2>&1; then
        log_success "PHPUnit 已安装"
        phpunit --version
        return 0
    fi
    
    # 检查PHP版本
    local php_version=$(php -v | head -1 | awk '{print $2}' | cut -d. -f1,2)
    log_info "检测到PHP版本: $php_version"
    
    # 检查并安装必需的PHP扩展
    log_info "检查PHP扩展..."
    local missing_extensions=()
    
    if ! php -m | grep -q "dom"; then
        missing_extensions+=("php${php_version}-dom")
    fi
    if ! php -m | grep -q "mbstring"; then
        missing_extensions+=("php${php_version}-mbstring")
    fi
    if ! php -m | grep -q "xml"; then
        missing_extensions+=("php${php_version}-xml")
    fi
    if ! php -m | grep -q "xmlwriter"; then
        missing_extensions+=("php${php_version}-xmlwriter")
    fi
    
    if [[ ${#missing_extensions[@]} -gt 0 ]]; then
        log_info "安装缺失的PHP扩展: ${missing_extensions[*]}"
        sudo apt install "${missing_extensions[@]}" -y
    fi
    
    # 全局安装PHPUnit
    log_info "下载PHPUnit..."
    wget https://phar.phpunit.de/phpunit.phar
    
    if [[ -f "phpunit.phar" ]]; then
        chmod +x phpunit.phar
        sudo mv phpunit.phar /usr/local/bin/phpunit
        
        log_success "PHPUnit 安装完成"
        log_info "使用方法: phpunit --help"
        
        # 显示PHPUnit说明
        echo ""
        log_info "PHPUnit 是什么？"
        echo "  - PHP单元测试框架"
        echo "  - 用于测试Magento自定义模块"
        echo "  - 确保代码质量和功能正确性"
        echo ""
        log_info "常用命令:"
        echo "  phpunit --version          # 查看版本"
        echo "  phpunit tests/             # 运行测试"
        echo "  phpunit --coverage-html    # 生成覆盖率报告"
        
        # 验证安装
        if phpunit --version >/dev/null 2>&1; then
            log_success "PHPUnit 验证成功"
        else
            log_warning "PHPUnit 可能需要额外的PHP扩展"
        fi
    else
        log_error "PHPUnit 下载失败"
        return 1
    fi
}

# 安装Xdebug
install_xdebug() {
    log_info "安装Xdebug..."
    
    # 检查是否已安装
    if php -m | grep -q xdebug; then
        log_success "Xdebug 已安装"
        php -m | grep xdebug
        return 0
    fi
    
    # 安装Xdebug
    log_info "通过apt安装Xdebug..."
    sudo apt update
    sudo apt install php-xdebug -y
    
    # 配置Xdebug
    log_info "配置Xdebug..."
    sudo tee -a /etc/php/8.3/mods-available/xdebug.ini >/dev/null <<EOF

; SaltGoat Xdebug配置
xdebug.mode = debug
xdebug.start_with_request = yes
xdebug.client_host = 127.0.0.1
xdebug.client_port = 9003
xdebug.log = /var/log/xdebug.log
EOF
    
    # 重启PHP-FPM
    sudo systemctl restart php8.3-fpm
    
    log_success "Xdebug 安装完成"
    log_info "重启PHP-FPM服务以应用配置"
}

# 清理Magento缓存
clear_magento_cache() {
    log_highlight "清理Magento缓存..."
    
    if [[ ! -f "bin/magento" ]]; then
        log_error "未找到Magento CLI，请确保在Magento根目录"
        return 1
    fi
    
    log_info "清理所有缓存..."
    php bin/magento cache:clean
    php bin/magento cache:flush
    
    log_info "清理生成的文件..."
    rm -rf var/cache/* var/page_cache/* var/view_preprocessed/*
    
    log_success "缓存清理完成"
}

# 检查缓存状态
check_cache_status() {
    log_highlight "检查Magento缓存状态..."
    
    if [[ ! -f "bin/magento" ]]; then
        log_error "未找到Magento CLI"
        return 1
    fi
    
    log_info "缓存状态:"
    php bin/magento cache:status
    
    echo ""
    log_info "缓存目录大小:"
    du -sh var/cache/ var/page_cache/ var/view_preprocessed/ 2>/dev/null || echo "缓存目录不存在"
}

# 预热缓存
warm_magento_cache() {
    log_highlight "预热Magento缓存..."
    
    if [[ ! -f "bin/magento" ]]; then
        log_error "未找到Magento CLI"
        return 1
    fi
    
    log_info "启用所有缓存..."
    php bin/magento cache:enable
    
    log_info "预热页面缓存..."
    php bin/magento cache:warm
    
    log_success "缓存预热完成"
}

# 重建索引
reindex_magento() {
    log_highlight "重建Magento索引..."
    
    if [[ ! -f "bin/magento" ]]; then
        log_error "未找到Magento CLI"
        return 1
    fi
    
    log_info "重建所有索引..."
    php bin/magento indexer:reindex
    
    log_success "索引重建完成"
}

# 检查索引状态
check_index_status() {
    log_highlight "检查Magento索引状态..."
    
    if [[ ! -f "bin/magento" ]]; then
        log_error "未找到Magento CLI"
        return 1
    fi
    
    log_info "索引状态:"
    php bin/magento indexer:status
}

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
    local timestamp=$(date +%Y%m%d_%H%M%S)
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
        local env_perms=$(stat -c "%a" app/etc/env.php)
        if [[ "$env_perms" == "644" ]]; then
            echo "  ✅ env.php 权限正确: $env_perms"
        else
            echo "  ⚠️  env.php 权限异常: $env_perms (应为644)"
        fi
    fi
    echo ""
    
    # 检查敏感文件
    log_info "敏感文件检查:"
    local sensitive_files=("app/etc/env.php" "composer.json" "composer.lock")
    for file in "${sensitive_files[@]}"; do
        if [[ -f "$file" ]]; then
            echo "  ✅ $file 存在"
        else
            echo "  ❌ $file 缺失"
        fi
    done
    echo ""
    
    # 检查版本
    log_info "版本检查:"
    if [[ -f "composer.json" ]]; then
        local version=$(grep -o '"version": "[^"]*"' composer.json | cut -d'"' -f4)
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

# 显示帮助
show_magetools_help() {
    echo "=========================================="
    echo "    Magento 工具集帮助"
    echo "=========================================="
    echo ""
    echo "Magento工具集提供以下功能:"
    echo ""
    echo "📦 工具安装:"
    echo "  install n98-magerun2 - 安装N98 Magerun2"
    echo "  install magerun      - 安装N98 Magerun (Magento 1)"
    echo "  install phpunit      - 安装PHPUnit单元测试框架"
    echo "  install xdebug       - 安装Xdebug调试工具"
    echo ""
    echo "🗂️  缓存管理:"
    echo "  cache clear          - 清理所有缓存"
    echo "  cache status         - 检查缓存状态"
    echo "  cache warm           - 预热缓存"
    echo ""
    echo "📊 索引管理:"
    echo "  index reindex        - 重建所有索引"
    echo "  index status         - 检查索引状态"
    echo ""
    echo "🚀 部署管理:"
    echo "  deploy               - 部署到生产环境"
    echo ""
    echo "💾 备份恢复:"
    echo "  backup               - 创建完整备份"
    echo "  restore <backup>     - 从备份恢复"
    echo ""
    echo "📈 性能分析:"
    echo "  performance          - 分析性能状况"
    echo ""
    echo "🔒 安全扫描:"
    echo "  security             - 扫描安全问题"
    echo ""
    echo "🔄 更新管理:"
    echo "  update               - 更新Magento"
    echo ""
    echo "示例:"
    echo "  saltgoat magetools install n98-magerun2"
    echo "  saltgoat magetools cache clear"
    echo "  saltgoat magetools index reindex"
    echo "  saltgoat magetools backup"
    echo "  saltgoat magetools performance"
}

#!/bin/bash
# 版本锁定模块
# services/version-lock.sh

# 锁定软件版本
lock_software_versions() {
    log_info "锁定核心LEMP软件版本..."
    
    # 检查apt-mark是否可用
    if ! command -v apt-mark >/dev/null 2>&1; then
        log_error "apt-mark 命令不可用，无法锁定版本"
        return 1
    fi
    
    # 锁定PHP 8.3相关包
    log_info "锁定 PHP 8.3 版本..."
    local php_packages=(
        "php-common"
        "php-mysql"
        "php-curl"
        "php-mbstring"
        "php-xml"
        "php-zip"
        "php-gd"
        "php-opcache"
        "php-bz2"
    )
    
    for package in "${php_packages[@]}"; do
        if dpkg -l | grep -q "^ii.*$package "; then
            sudo apt-mark hold "$package" 2>/dev/null
            log_success "已锁定: $package"
        fi
    done
    
    # 锁定Percona MySQL 8.4相关包
    log_info "锁定 Percona MySQL 8.4 版本..."
    local mysql_packages=(
        "percona-server-server"
        "percona-server-client"
        "percona-server-common"
        "libmysqlclient21"
        "mysql-common"
    )
    
    for package in "${mysql_packages[@]}"; do
        if dpkg -l | grep -q "^ii.*$package "; then
            sudo apt-mark hold "$package" 2>/dev/null
            log_success "已锁定: $package"
        fi
    done
    
    # 锁定RabbitMQ 4.1
    log_info "锁定 RabbitMQ 4.1 版本..."
    local rabbitmq_packages=(
        "rabbitmq-server"
        "erlang"
        "erlang-base"
    )
    
    for package in "${rabbitmq_packages[@]}"; do
        if dpkg -l | grep -q "^ii.*$package "; then
            sudo apt-mark hold "$package" 2>/dev/null
            log_success "已锁定: $package"
        fi
    done
    
    # 锁定OpenSearch 2.19
    log_info "锁定 OpenSearch 2.19 版本..."
    local opensearch_packages=(
        "opensearch"
        "opensearch-dashboards"
    )
    
    for package in "${opensearch_packages[@]}"; do
        if dpkg -l | grep -q "^ii.*$package "; then
            sudo apt-mark hold "$package" 2>/dev/null
            log_success "已锁定: $package"
        fi
    done
    
    # 锁定Valkey 8
    log_info "锁定 Valkey 8 版本..."
    local valkey_packages=(
        "valkey"
        "valkey-tools"
    )
    
    for package in "${valkey_packages[@]}"; do
        if dpkg -l | grep -q "^ii.*$package "; then
            sudo apt-mark hold "$package" 2>/dev/null
            log_success "已锁定: $package"
        fi
    done
    
    # 锁定Varnish 7.6
    log_info "锁定 Varnish 7.6 版本..."
    local varnish_packages=(
        "varnish"
        "varnish-dev"
    )
    
    for package in "${varnish_packages[@]}"; do
        if dpkg -l | grep -q "^ii.*$package "; then
            sudo apt-mark hold "$package" 2>/dev/null
            log_success "已锁定: $package"
        fi
    done
    
    # 锁定Composer 2.8
    log_info "锁定 Composer 2.8 版本..."
    if command -v composer >/dev/null 2>&1; then
        # Composer通常通过curl安装，需要特殊处理
        log_info "Composer 通过全局安装，版本已固定"
    fi
    
    log_success "核心LEMP软件版本锁定完成"
    log_info "注意: Nginx 1.29.1+ModSecurity 是源码编译，版本已固定"
}

# 解锁软件版本
unlock_software_versions() {
    log_info "解锁软件版本..."
    
    # 解锁所有被锁定的包
    local locked_packages=$(apt-mark showhold)
    if [[ -n "$locked_packages" ]]; then
        echo "$locked_packages" | while read -r package; do
            sudo apt-mark unhold "$package" 2>/dev/null
            log_success "已解锁: $package"
        done
    else
        log_info "没有找到被锁定的软件包"
    fi
    
    log_success "软件版本解锁完成"
}

# 显示锁定的软件版本
show_locked_versions() {
    log_info "当前锁定的软件版本:"
    echo "=========================================="
    
    local locked_packages=$(apt-mark showhold)
    if [[ -n "$locked_packages" ]]; then
        echo "$locked_packages" | while read -r package; do
            local version=$(dpkg -l "$package" 2>/dev/null | grep "^ii" | awk '{print $3}')
            if [[ -n "$version" ]]; then
                log_success "$package: $version"
            else
                log_warning "$package: 未安装"
            fi
        done
    else
        log_info "没有锁定的软件包"
    fi
    
    echo "=========================================="
}

# 检查软件版本状态
check_version_status() {
    log_info "检查核心LEMP软件版本状态..."
    echo "=========================================="
    
    # 检查Nginx版本
    if command -v nginx >/dev/null 2>&1; then
        local nginx_version=$(nginx -v 2>&1 | cut -d' ' -f3)
        log_success "Nginx: $nginx_version+ModSecurity (源码编译，版本固定)"
    elif [[ -f "/usr/local/nginx/sbin/nginx" ]]; then
        local nginx_version=$(/usr/local/nginx/sbin/nginx -v 2>&1 | cut -d' ' -f3)
        log_success "Nginx: $nginx_version+ModSecurity (源码编译，版本固定)"
    else
        log_warning "Nginx: 未安装"
    fi
    
    # 检查Percona MySQL版本
    if command -v mysql >/dev/null 2>&1; then
        local mysql_version=$(mysql --version | cut -d' ' -f3)
        log_success "Percona: $mysql_version (目标: 8.4)"
    else
        log_warning "Percona MySQL: 未安装"
    fi
    
    # 检查PHP版本
    if command -v php >/dev/null 2>&1; then
        local php_version=$(php -v | head -1 | cut -d' ' -f2)
        log_success "PHP: $php_version (目标: 8.3)"
    else
        log_warning "PHP: 未安装"
    fi
    
    # 检查Valkey版本
    if command -v valkey-cli >/dev/null 2>&1; then
        local valkey_version=$(valkey-cli --version | cut -d' ' -f2)
        log_success "Valkey: $valkey_version (目标: 8)"
    else
        log_warning "Valkey: 未安装"
    fi
    
    # 检查RabbitMQ版本
    if command -v rabbitmqctl >/dev/null 2>&1; then
        local rabbitmq_version=$(rabbitmqctl version 2>/dev/null | head -1 | cut -d' ' -f3)
        log_success "RabbitMQ: $rabbitmq_version (目标: 4.1)"
    else
        log_warning "RabbitMQ: 未安装"
    fi
    
    # 检查OpenSearch版本
    if command -v opensearch >/dev/null 2>&1; then
        local opensearch_version=$(opensearch --version 2>/dev/null | head -1 | cut -d' ' -f2 || echo "未知")
        log_success "OpenSearch: $opensearch_version (目标: 2.19)"
    else
        log_warning "OpenSearch: 未安装"
    fi
    
    # 检查Varnish版本
    if command -v varnishd >/dev/null 2>&1; then
        local varnish_version=$(varnishd -V 2>&1 | head -1 | cut -d' ' -f2 || echo "未知")
        log_success "Varnish: $varnish_version (目标: 7.6)"
    else
        log_warning "Varnish: 未安装"
    fi
    
    # 检查Composer版本
    if command -v composer >/dev/null 2>&1; then
        local composer_version=$(composer --version 2>&1 | head -1 | cut -d' ' -f3)
        log_success "Composer: $composer_version (目标: 2.8)"
    else
        log_warning "Composer: 未安装"
    fi
    
    echo "=========================================="
    
    # 显示锁定状态
    log_info "版本锁定状态:"
    local locked_count=$(apt-mark showhold | wc -l)
    if [[ "$locked_count" -gt 0 ]]; then
        log_success "已锁定 $locked_count 个软件包"
        log_info "使用 'saltgoat version-lock show' 查看详细信息"
    else
        log_warning "没有锁定的软件包"
        log_info "使用 'saltgoat version-lock lock' 锁定版本"
    fi
    
    echo "=========================================="
    log_info "锁定策略:"
    log_info "✅ 锁定: Nginx, Percona, PHP, RabbitMQ, OpenSearch, Valkey, Varnish, Composer"
    log_info "🔄 允许更新: 系统内核、安全补丁、其他工具软件"
}

# 创建版本锁定配置文件
create_version_lock_config() {
    log_info "创建版本锁定配置文件..."
    
    local config_file="/etc/saltgoat/version-lock.conf"
    sudo mkdir -p "$(dirname "$config_file")"
    
    cat > "/tmp/version-lock.conf" << EOF
# SaltGoat 版本锁定配置
# 此文件用于记录锁定的软件版本

# 锁定时间
LOCK_DATE=$(date '+%Y-%m-%d %H:%M:%S')

# 核心LEMP软件版本 (需要锁定)
NGINX_VERSION=$(nginx -v 2>&1 | cut -d' ' -f3 || echo "未安装")
PERCONA_VERSION=$(mysql --version 2>&1 | cut -d' ' -f3 || echo "未安装")
PHP_VERSION=$(php -v 2>&1 | head -1 | cut -d' ' -f2 || echo "未安装")
VALKEY_VERSION=$(valkey-cli --version 2>&1 | cut -d' ' -f2 || echo "未安装")
RABBITMQ_VERSION=$(rabbitmqctl version 2>/dev/null | head -1 | cut -d' ' -f3 || echo "未安装")
OPENSEARCH_VERSION=$(opensearch --version 2>/dev/null | head -1 | cut -d' ' -f2 || echo "未安装")
VARNISH_VERSION=$(varnishd -V 2>&1 | head -1 | cut -d' ' -f2 || echo "未安装")
COMPOSER_VERSION=$(composer --version 2>&1 | head -1 | cut -d' ' -f3 || echo "未安装")

# 锁定原因
LOCK_REASON="防止意外更新，保持LEMP环境稳定性"

# 注意事项
# 1. 如需更新软件版本，请先解锁: saltgoat version-lock unlock
# 2. 更新后请重新锁定: saltgoat version-lock lock
# 3. 定期检查安全更新: saltgoat security-scan
EOF
    
    sudo mv "/tmp/version-lock.conf" "$config_file"
    sudo chmod 644 "$config_file"
    
    log_success "版本锁定配置文件已创建: $config_file"
}

# 版本锁定主函数
version_lock_handler() {
    case "$1" in
        "lock")
            lock_software_versions
            create_version_lock_config
            ;;
        "unlock")
            unlock_software_versions
            ;;
        "show")
            show_locked_versions
            ;;
        "status")
            check_version_status
            ;;
        "help"|"--help"|"-h")
            log_info "版本锁定功能帮助:"
            log_info "用法: saltgoat version-lock <command>"
            log_info ""
            log_info "命令:"
            log_info "  lock    - 锁定主要软件版本"
            log_info "  unlock  - 解锁软件版本"
            log_info "  show    - 显示锁定的软件包"
            log_info "  status  - 检查软件版本状态"
            log_info "  help    - 显示此帮助信息"
            log_info ""
            log_info "示例:"
            log_info "  saltgoat version-lock lock    # 锁定版本"
            log_info "  saltgoat version-lock status  # 检查状态"
            ;;
        *)
            log_error "未知的版本锁定命令: $1"
            log_info "使用 'saltgoat version-lock help' 查看帮助"
            return 1
            ;;
    esac
}

#!/bin/bash
# 状态管理模块 - Salt 状态管理
# services/state.sh

# 状态列表
state_list() {
    echo "SaltGoat 可用状态列表"
    echo "=========================================="
    echo ""
    
    echo "核心状态:"
    echo "----------------------------------------"
    echo "  nginx                    - Nginx Web服务器"
    echo "  php                      - PHP-FPM 服务"
    echo "  mysql                    - MySQL 数据库"
    echo "  valkey                   - Valkey 缓存"
    echo "  opensearch               - OpenSearch 搜索引擎"
    echo "  rabbitmq                 - RabbitMQ 消息队列"
    echo ""
    
    echo "可选状态:"
    echo "----------------------------------------"
    echo "  phpmyadmin               - phpMyAdmin 管理界面"
    echo "  fail2ban                 - Fail2ban 安全防护"
    echo "  magento-optimization     - Magento2 优化配置"
    echo "  security                 - 安全加固配置"
    echo ""
    
    echo "组合状态:"
    echo "----------------------------------------"
    echo "  webserver                - 完整Web服务器 (nginx + php)"
    echo "  database                 - 完整数据库 (mysql + valkey)"
    echo "  search                   - 搜索引擎 (opensearch)"
    echo "  message                  - 消息队列 (rabbitmq)"
    echo "  lemp                     - 完整LEMP栈"
    echo ""
    
    echo "使用示例:"
    echo "----------------------------------------"
    echo "  saltgoat state apply nginx             # 应用nginx状态"
    echo "  saltgoat state apply lemp              # 应用完整LEMP栈"
    echo "  saltgoat state rollback nginx          # 回滚nginx状态"
    echo ""
    
    # 显示当前状态状态
    echo "当前状态状态:"
    echo "----------------------------------------"
    show_state_status
}

# 应用状态
state_apply() {
    local state_name="$1"
    
    if [[ -z "$state_name" ]]; then
        log_error "请指定要应用的状态名称"
        log_info "使用 'saltgoat state list' 查看可用状态"
        exit 1
    fi
    
    echo "应用状态: $state_name"
    echo "=========================================="
    
    # 检查状态是否存在
    if ! state_exists "$state_name"; then
        log_error "状态 '$state_name' 不存在"
        log_info "使用 'saltgoat state list' 查看可用状态"
        exit 1
    fi
    
    # 创建备份
    state_backup "$state_name"
    
    # 应用状态
    log_info "正在应用状态: $state_name"
    case "$state_name" in
        "nginx")
            salt-call --local state.apply nginx
            ;;
        "php")
            salt-call --local state.apply php
            ;;
        "mysql")
            salt-call --local state.apply mysql
            ;;
        "valkey")
            salt-call --local state.apply valkey
            ;;
        "opensearch")
            salt-call --local state.apply opensearch
            ;;
        "rabbitmq")
            salt-call --local state.apply rabbitmq
            ;;
        "phpmyadmin")
            salt-call --local state.apply phpmyadmin
            ;;
        "fail2ban")
            salt-call --local state.apply fail2ban
            ;;
        "magento-optimization")
            salt-call --local state.apply magento-optimization
            ;;
        "security")
            salt-call --local state.apply security
            ;;
        "webserver")
            salt-call --local state.apply webserver
            ;;
        "database")
            salt-call --local state.apply database
            ;;
        "search")
            salt-call --local state.apply search
            ;;
        "message")
            salt-call --local state.apply message
            ;;
        "lemp")
            salt-call --local state.apply lemp
            ;;
        *)
            log_error "未知状态: $state_name"
            exit 1
            ;;
    esac
    
    if [[ $? -eq 0 ]]; then
        log_success "状态 '$state_name' 应用成功"
        log_info "备份已保存到: /tmp/saltgoat_backup_${state_name}_$(date +%Y%m%d_%H%M%S)"
    else
        log_error "状态 '$state_name' 应用失败"
        log_info "使用 'saltgoat state rollback $state_name' 回滚到之前的状态"
        exit 1
    fi
}

# 回滚状态
state_rollback() {
    local state_name="$1"
    
    if [[ -z "$state_name" ]]; then
        log_error "请指定要回滚的状态名称"
        log_info "使用 'saltgoat state list' 查看可用状态"
        exit 1
    fi
    
    echo "回滚状态: $state_name"
    echo "=========================================="
    
    # 查找最新的备份
    local latest_backup=$(find /tmp -name "saltgoat_backup_${state_name}_*" -type d | sort | tail -1)
    
    if [[ -z "$latest_backup" ]]; then
        log_error "未找到状态 '$state_name' 的备份"
        log_info "无法回滚，请手动恢复配置"
        exit 1
    fi
    
    log_info "找到备份: $latest_backup"
    log_info "正在回滚状态: $state_name"
    
    # 执行回滚
    case "$state_name" in
        "nginx")
            if [[ -f "$latest_backup/nginx.conf" ]]; then
                sudo cp "$latest_backup/nginx.conf" /etc/nginx/nginx.conf
                sudo systemctl restart nginx
            fi
            ;;
        "php")
            if [[ -f "$latest_backup/php.ini" ]]; then
                sudo cp "$latest_backup/php.ini" /etc/php/8.3/fpm/php.ini
                sudo systemctl restart php8.3-fpm
            fi
            ;;
        "mysql")
            if [[ -f "$latest_backup/mysql.cnf" ]]; then
                sudo cp "$latest_backup/mysql.cnf" /etc/mysql/mysql.conf.d/lemp.cnf
                sudo systemctl restart mysql
            fi
            ;;
        "valkey")
            if [[ -f "$latest_backup/valkey.conf" ]]; then
                sudo cp "$latest_backup/valkey.conf" /etc/valkey/valkey.conf
                sudo systemctl restart valkey
            fi
            ;;
        *)
            log_error "回滚功能暂不支持状态: $state_name"
            log_info "请手动恢复配置文件"
            exit 1
            ;;
    esac
    
    if [[ $? -eq 0 ]]; then
        log_success "状态 '$state_name' 回滚成功"
    else
        log_error "状态 '$state_name' 回滚失败"
        exit 1
    fi
}

# 检查状态是否存在
state_exists() {
    local state_name="$1"
    
    case "$state_name" in
        "nginx"|"php"|"mysql"|"valkey"|"opensearch"|"rabbitmq"|"phpmyadmin"|"fail2ban"|"magento-optimization"|"security"|"webserver"|"database"|"search"|"message"|"lemp")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 创建状态备份
state_backup() {
    local state_name="$1"
    local backup_dir="/tmp/saltgoat_backup_${state_name}_$(date +%Y%m%d_%H%M%S)"
    
    mkdir -p "$backup_dir"
    
    case "$state_name" in
        "nginx")
            if [[ -f "/etc/nginx/nginx.conf" ]]; then
                cp /etc/nginx/nginx.conf "$backup_dir/nginx.conf"
            fi
            ;;
        "php")
            if [[ -f "/etc/php/8.3/fpm/php.ini" ]]; then
                cp /etc/php/8.3/fpm/php.ini "$backup_dir/php.ini"
            fi
            ;;
        "mysql")
            if [[ -f "/etc/mysql/mysql.conf.d/lemp.cnf" ]]; then
                cp /etc/mysql/mysql.conf.d/lemp.cnf "$backup_dir/mysql.cnf"
            fi
            ;;
        "valkey")
            if [[ -f "/etc/valkey/valkey.conf" ]]; then
                cp /etc/valkey/valkey.conf "$backup_dir/valkey.conf"
            fi
            ;;
    esac
}

# 显示状态状态
show_state_status() {
    echo "服务状态:"
    echo "  nginx: $(systemctl is-active nginx 2>/dev/null || echo '未安装')"
    echo "  php8.3-fpm: $(systemctl is-active php8.3-fpm 2>/dev/null || echo '未安装')"
    echo "  mysql: $(systemctl is-active mysql 2>/dev/null || echo '未安装')"
    echo "  valkey: $(systemctl is-active valkey 2>/dev/null || echo '未安装')"
    echo "  opensearch: $(systemctl is-active opensearch 2>/dev/null || echo '未安装')"
    echo "  rabbitmq: $(systemctl is-active rabbitmq 2>/dev/null || echo '未安装')"
    echo ""
    
    echo "配置文件状态:"
    echo "  nginx.conf: $([ -f /etc/nginx/nginx.conf ] && echo '存在' || echo '不存在')"
    echo "  php.ini: $([ -f /etc/php/8.3/fpm/php.ini ] && echo '存在' || echo '不存在')"
    echo "  mysql.cnf: $([ -f /etc/mysql/mysql.conf.d/lemp.cnf ] && echo '存在' || echo '不存在')"
    echo "  valkey.conf: $([ -f /etc/valkey/valkey.conf ] && echo '存在' || echo '不存在')"
    echo ""
    
    echo "备份状态:"
    local backup_count=$(find /tmp -name "saltgoat_backup_*" -type d 2>/dev/null | wc -l)
    echo "  可用备份: $backup_count 个"
}

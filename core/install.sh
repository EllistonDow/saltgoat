#!/bin/bash
# 安装管理模块
# core/install.sh

# 加载安装配置
load_install_config() {
    log_info "加载安装配置..."
    
    # 处理命令行参数覆盖（先解析参数）
    parse_install_args "$@"
    
    # 检查是否存在 .env 文件
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        log_info "发现 .env 配置文件，正在加载..."
        source "${SCRIPT_DIR}/lib/env.sh"
        load_env_config "${SCRIPT_DIR}/.env"
        log_success "环境配置加载完成"
    else
        log_warning "未发现 .env 配置文件，将使用默认配置"
        log_info "运行 'saltgoat env create' 创建配置文件"
    fi
    
    # 再次处理命令行参数覆盖（确保命令行参数优先级最高）
    parse_install_args "$@"
    
    # 验证必要的配置
    validate_install_config
}

# 解析安装参数
parse_install_args() {
    log_info "解析命令行参数: $*"
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mysql-password)
                MYSQL_PASSWORD="$2"
                log_info "设置 MySQL 密码: $MYSQL_PASSWORD"
                shift 2
                ;;
            --valkey-password)
                VALKEY_PASSWORD="$2"
                log_info "设置 Valkey 密码: $VALKEY_PASSWORD"
                shift 2
                ;;
            --rabbitmq-password)
                RABBITMQ_PASSWORD="$2"
                log_info "设置 RabbitMQ 密码: $RABBITMQ_PASSWORD"
                shift 2
                ;;
            --webmin-password)
                WEBMIN_PASSWORD="$2"
                log_info "设置 Webmin 密码: $WEBMIN_PASSWORD"
                shift 2
                ;;
            --phpmyadmin-password)
                PHPMYADMIN_PASSWORD="$2"
                log_info "设置 phpMyAdmin 密码: $PHPMYADMIN_PASSWORD"
                shift 2
                ;;
            --ssl-email)
                SSL_EMAIL="$2"
                log_info "设置 SSL 邮箱: $SSL_EMAIL"
                shift 2
                ;;
            --timezone)
                TIMEZONE="$2"
                log_info "设置时区: $TIMEZONE"
                shift 2
                ;;
            --language)
                LANGUAGE="$2"
                log_info "设置语言: $LANGUAGE"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
}

# 验证安装配置
validate_install_config() {
    log_info "验证安装配置..."
    
    # 设置默认值
    MYSQL_PASSWORD="${MYSQL_PASSWORD:-SaltGoat2024!}"
    VALKEY_PASSWORD="${VALKEY_PASSWORD:-Valkey2024!}"
    RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-RabbitMQ2024!}"
    WEBMIN_PASSWORD="${WEBMIN_PASSWORD:-Webmin2024!}"
    PHPMYADMIN_PASSWORD="${PHPMYADMIN_PASSWORD:-phpMyAdmin2024!}"
    SSL_EMAIL="${SSL_EMAIL:-admin@example.com}"
    TIMEZONE="${TIMEZONE:-America/Los_Angeles}"
    LANGUAGE="${LANGUAGE:-en_US.UTF-8}"
    
    # 更新 Pillar 数据
    update_pillar_config
    
    log_success "安装配置验证完成"
}

# 更新 Pillar 配置
update_pillar_config() {
    log_info "更新 Salt Pillar 配置..."
    
    # 创建临时 Pillar 文件
    local pillar_file="/tmp/saltgoat_pillar.sls"
    
    cat > "$pillar_file" << EOF
mysql_password: '$MYSQL_PASSWORD'
valkey_password: '$VALKEY_PASSWORD'
rabbitmq_password: '$RABBITMQ_PASSWORD'
webmin_password: '$WEBMIN_PASSWORD'
phpmyadmin_password: '$PHPMYADMIN_PASSWORD'
ssl_email: '$SSL_EMAIL'
timezone: '$TIMEZONE'
language: '$LANGUAGE'
EOF
    
    # 使用 Salt 原生功能复制到 Pillar 目录
    salt-call --local file.copy "$pillar_file" "${SCRIPT_DIR}/salt/pillar/saltgoat.sls"
    
    # 清理临时文件
    salt-call --local file.remove "$pillar_file"
    
    log_success "Pillar 配置更新完成"
}

# 安装所有组件
install_all() {
    log_info "开始安装所有 SaltGoat 组件..."
    
    # 加载环境配置
    load_install_config
    
    # 安装系统依赖
    install_system_deps
    
    # 安装 Salt
    install_salt
    
    # 安装核心组件
    install_core
    
    # 安装可选组件
    install_optional
    
    log_success "SaltGoat 安装完成！"
    log_info "使用 'saltgoat passwords' 查看配置的密码"
}

# 安装核心组件
install_core() {
    log_info "安装核心组件..."
    
    # 应用核心状态
    salt-call --local state.apply core.nginx
    salt-call --local state.apply core.php
    salt-call --local state.apply core.mysql
    salt-call --local state.apply core.composer
    
    log_success "核心组件安装完成"
}

# 安装可选组件
install_optional() {
    log_info "安装可选组件..."
    
    # 应用可选状态
    salt-call --local state.apply optional.valkey
    salt-call --local state.apply optional.opensearch
    salt-call --local state.apply optional.rabbitmq
    salt-call --local state.apply optional.varnish
    salt-call --local state.apply optional.fail2ban
    salt-call --local state.apply optional.webmin
    salt-call --local state.apply optional.phpmyadmin
    salt-call --local state.apply optional.certbot
    
    log_success "可选组件安装完成"
}

# 安装系统依赖
install_system_deps() {
    log_info "安装系统依赖..."
    
    # 更新包列表
    salt-call --local cmd.run "sudo apt update"
    
    # 安装基础包
    salt-call --local pkg.install curl wget git unzip
    
    log_success "系统依赖安装完成"
}

# 安装 Salt
install_salt() {
    log_info "安装 Salt..."
    
    # 检查 Salt 是否已安装
    if command_exists salt-call; then
        log_info "Salt 已安装，跳过安装步骤"
        return
    fi
    
    # 安装 Salt
    salt-call --local cmd.run "curl -L https://bootstrap.saltproject.io | sudo sh -s -- -M -N"
    
    log_success "Salt 安装完成"
}

#!/bin/bash
# 安装管理模块
# core/install.sh

# 安装所有组件
install_all() {
    log_info "开始安装所有 SaltGoat 组件..."
    
    # 安装系统依赖
    install_system_deps
    
    # 安装 Salt
    install_salt
    
    # 安装核心组件
    install_core
    
    # 安装可选组件
    install_optional
    
    log_success "SaltGoat 安装完成！"
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
    salt-call --local cmd.run "apt update"
    
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

#!/bin/bash
# 环境配置加载模块
# lib/env.sh

# 加载环境配置文件
load_env_config() {
    local env_file="${1:-.env}"
    
    if [[ -f "$env_file" ]]; then
        log_info "加载环境配置: $env_file"
        # 加载环境变量，忽略注释和空行
        while IFS= read -r line; do
            # 跳过注释和空行
            if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
                continue
            fi
            
            # 导出环境变量，支持带引号的值
            if [[ "$line" =~ ^[A-Z_]+=.* ]]; then
                # 使用 eval 来正确处理带引号的值
                eval "export $line"
            fi
        done < "$env_file"
        
        log_success "环境配置加载完成"
        return 0
    else
        log_warning "环境配置文件不存在: $env_file"
        return 1
    fi
}

# 显示当前环境配置
show_env_config() {
    log_highlight "当前环境配置:"
    echo "MySQL 密码: ${MYSQL_PASSWORD:-未设置}"
    echo "Valkey 密码: ${VALKEY_PASSWORD:-未设置}"
    echo "RabbitMQ 密码: ${RABBITMQ_PASSWORD:-未设置}"
    echo "Webmin 密码: ${WEBMIN_PASSWORD:-未设置}"
    echo "phpMyAdmin 密码: ${PHPMYADMIN_PASSWORD:-未设置}"
    echo "SSL 邮箱: ${SSL_EMAIL:-未设置}"
    echo "时区: ${TIMEZONE:-未设置}"
    echo "语言: ${LANGUAGE:-未设置}"
}

# 创建环境配置文件
create_env_config() {
    local env_file="${1:-.env}"
    
    if [[ -f "$env_file" ]]; then
        log_warning "环境配置文件已存在: $env_file"
        read -p "是否覆盖? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "取消创建环境配置文件"
            return 1
        fi
    fi
    
    log_info "创建环境配置文件: $env_file"
    cp env.example "$env_file"
    log_success "环境配置文件已创建: $env_file"
    log_info "请编辑 $env_file 文件并设置您的密码"
}

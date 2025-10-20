#!/bin/bash
# SaltGoat 配置管理库
# lib/config.sh

# 默认配置
DEFAULT_CONFIG=(
    "MYSQL_ROOT_PASSWORD=MyPass123!"
    "VALKEY_PASSWORD=Valkey123!"
    "RABBITMQ_ADMIN_PASSWORD=RabbitMQ123!"
    "WEBMIN_PASSWORD=Webmin123!"
    "PHPMYADMIN_PASSWORD=phpMyAdmin123!"
)

# 内存监控配置
MEMORY_CONFIG=(
    "THRESHOLD_75=75"
    "THRESHOLD_85=85"
    "LOG_FILE=/var/log/saltgoat-memory.log"
)

# 加载配置文件
load_config() {
    local config_file="${1:-/etc/saltgoat.conf}"
    
    if [[ -f "$config_file" ]]; then
        source "$config_file"
    fi
}

# 保存配置到文件
save_config() {
    local config_file="${1:-/etc/saltgoat.conf}"
    local key="$2"
    local value="$3"
    
    # 创建配置目录
    sudo mkdir -p "$(dirname "$config_file")"
    
    # 添加或更新配置项
    if grep -q "^${key}=" "$config_file" 2>/dev/null; then
        sudo sed -i "s/^${key}=.*/${key}=${value}/" "$config_file"
    else
        echo "${key}=${value}" | sudo tee -a "$config_file" > /dev/null
    fi
}

# 获取配置值
get_config() {
    local key="$1"
    local default_value="$2"
    
    # 从环境变量获取
    if [[ -n "${!key}" ]]; then
        echo "${!key}"
        return
    fi
    
    # 从配置文件获取
    local config_file="/etc/saltgoat.conf"
    if [[ -f "$config_file" ]]; then
        local value=$(grep "^${key}=" "$config_file" 2>/dev/null | cut -d'=' -f2-)
        if [[ -n "$value" ]]; then
            echo "$value"
            return
        fi
    fi
    
    # 返回默认值
    echo "${default_value}"
}

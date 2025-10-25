#!/bin/bash
# 网站迁移检测脚本
# modules/magetools/migrate-detect.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../lib/logger.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"

# 检测网站迁移配置
detect_migration_config() {
    local site_path="$1"
    local site_name="$2"
    
    if [[ -z "$site_path" || -z "$site_name" ]]; then
        log_error "用法: detect_migration_config <site_path> <site_name>"
        return 1
    fi
    
    log_highlight "检测网站迁移配置: $site_name"
    
    # 检查 Magento 配置文件
    local env_file="$site_path/app/etc/env.php"
    if [[ ! -f "$env_file" ]]; then
        log_warning "Magento 配置文件不存在: $env_file"
        return 1
    fi
    
    # 检测 AMQP 配置中的旧网站名称
    log_info "检测 AMQP 配置..."
    local amqp_user
    amqp_user=$(grep -A 10 "'amqp'" "$env_file" | grep "'user'" | sed "s/.*'user' => '\([^']*\)'.*/\1/")
    local amqp_vhost
    amqp_vhost=$(grep -A 10 "'amqp'" "$env_file" | grep "'virtualhost'" | sed "s/.*'virtualhost' => '\([^']*\)'.*/\1/")
    
    if [[ -n "$amqp_user" && "$amqp_user" != "${site_name}_user" ]]; then
        log_warning "检测到旧 AMQP 用户: $amqp_user (应为: ${site_name}_user)"
        echo "OLD_AMQP_USER=$amqp_user"
    fi
    
    if [[ -n "$amqp_vhost" && "$amqp_vhost" != "/$site_name" ]]; then
        log_warning "检测到旧 AMQP 虚拟主机: $amqp_vhost (应为: /$site_name)"
        echo "OLD_AMQP_VHOST=$amqp_vhost"
    fi
    
    # 检测数据库配置
    log_info "检测数据库配置..."
    local db_name
    db_name=$(grep -A 20 "'db'" "$env_file" | grep "'dbname'" | sed "s/.*'dbname' => '\([^']*\)'.*/\1/")
    
    if [[ -n "$db_name" && "$db_name" != "$site_name" ]]; then
        log_warning "检测到旧数据库名: $db_name (应为: $site_name)"
        echo "OLD_DB_NAME=$db_name"
    fi
    
    # 检测缓存配置
    log_info "检测缓存配置..."
    local cache_backend
    cache_backend=$(grep -A 10 "'cache'" "$env_file" | grep "'backend'" | sed "s/.*'backend' => '\([^']*\)'.*/\1/")
    
    if [[ "$cache_backend" == "Cm_Cache_Backend_Redis" ]]; then
        local redis_database
        redis_database=$(grep -A 20 "'cache'" "$env_file" | grep "'database'" | sed "s/.*'database' => \([0-9]*\).*/\1/")
        if [[ -n "$redis_database" ]]; then
            log_info "当前 Redis 数据库: $redis_database"
            echo "REDIS_DATABASE=$redis_database"
        fi
    fi
    
    # 检测会话配置
    log_info "检测会话配置..."
    local session_save
    session_save=$(grep -A 10 "'session'" "$env_file" | grep "'save'" | sed "s/.*'save' => '\([^']*\)'.*/\1/")
    
    if [[ "$session_save" == "redis" ]]; then
        local session_database
        session_database=$(grep -A 20 "'session'" "$env_file" | grep "'database'" | sed "s/.*'database' => \([0-9]*\).*/\1/")
        if [[ -n "$session_database" ]]; then
            log_info "当前会话 Redis 数据库: $session_database"
            echo "SESSION_DATABASE=$session_database"
        fi
    fi
    
    # 检测 RabbitMQ 用户是否存在
    log_info "检测 RabbitMQ 用户..."
    if command -v rabbitmqctl >/dev/null 2>&1; then
        local rabbitmq_users
        rabbitmq_users=$(sudo rabbitmqctl list_users 2>/dev/null | grep -v "Listing users" | awk '{print $1}')
        local old_user_found=false
        local new_user_found=false
        
        for user in $rabbitmq_users; do
            if [[ "$user" == "${site_name}_user" ]]; then
                new_user_found=true
            elif [[ "$user" =~ _user$ ]] && [[ "$user" != "${site_name}_user" ]]; then
                old_user_found=true
                log_warning "检测到其他 RabbitMQ 用户: $user"
            fi
        done
        
        if [[ "$old_user_found" == true && "$new_user_found" == false ]]; then
            log_warning "RabbitMQ 用户可能需要迁移"
            echo "NEED_RABBITMQ_MIGRATION=true"
        fi
    fi
    
    # 检测 Valkey 数据库使用情况
    log_info "检测 Valkey 数据库使用情况..."
    if command -v redis-cli >/dev/null 2>&1; then
        local valkey_password
        valkey_password=$(sudo cat /etc/valkey/valkey.conf 2>/dev/null | grep "requirepass" | awk '{print $2}' | head -1)
        if [[ -n "$valkey_password" ]]; then
            for db in {0..99}; do
                local key_count
                key_count=$(redis-cli -a "$valkey_password" -n "$db" dbsize 2>/dev/null | grep -o '[0-9]*')
                if [[ "$key_count" -gt 0 ]]; then
                    log_info "Valkey 数据库 $db 有 $key_count 个键"
                    echo "USED_VALKEY_DB=$db"
                fi
            done
        fi
    fi
    
    log_success "迁移检测完成"
}

# 修复迁移配置
fix_migration_config() {
    local site_path="$1"
    local site_name="$2"
    local old_user="$3"
    local old_vhost="$4"
    
    if [[ -z "$site_path" || -z "$site_name" ]]; then
        log_error "用法: fix_migration_config <site_path> <site_name> [old_user] [old_vhost]"
        return 1
    fi
    
    log_highlight "修复网站迁移配置: $site_name"
    
    local env_file="$site_path/app/etc/env.php"
    if [[ ! -f "$env_file" ]]; then
        log_error "Magento 配置文件不存在: $env_file"
        return 1
    fi
    
    # 备份原文件
    log_info "备份原配置文件..."
    sudo cp "$env_file" "${env_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # 修复 AMQP 配置
    if [[ -n "$old_user" ]]; then
        log_info "修复 AMQP 用户: $old_user -> ${site_name}_user"
        sed -i "s/'user' => '$old_user'/'user' => '${site_name}_user'/g" "$env_file"
    fi
    
    if [[ -n "$old_vhost" ]]; then
        log_info "修复 AMQP 虚拟主机: $old_vhost -> /$site_name"
        sed -i "s|'virtualhost' => '$old_vhost'|'virtualhost' => '/$site_name'|g" "$env_file"
    fi
    
    # 修复密码（使用新的密码生成规则）
    local new_password="${site_name^}#2025!"
    log_info "更新 AMQP 密码为: $new_password"
    sed -i "s/'password' => '[^']*'/'password' => '$new_password'/g" "$env_file"
    
    # 修复数据库名
    log_info "修复数据库名: $site_name"
    sed -i "s/'dbname' => '[^']*'/'dbname' => '$site_name'/g" "$env_file"
    
    log_success "迁移配置修复完成"
    
    # 验证修复结果
    log_info "验证修复结果..."
    detect_migration_config "$site_path" "$site_name"
}

# 主函数
main() {
    if [[ $# -lt 2 ]]; then
        log_error "用法: $0 <site_path> <site_name> [fix]"
        echo ""
        echo "示例:"
        echo "  $0 /var/www/tank tank          # 检测迁移配置"
        echo "  $0 /var/www/tank tank fix      # 检测并修复迁移配置"
        exit 1
    fi
    
    local site_path="$1"
    local site_name="$2"
    local action="${3:-detect}"
    
    if [[ ! -d "$site_path" ]]; then
        log_error "网站目录不存在: $site_path"
        exit 1
    fi
    
    case "$action" in
        "detect")
            detect_migration_config "$site_path" "$site_name"
            ;;
        "fix")
            # 先检测
            local detection_result
            detection_result=$(detect_migration_config "$site_path" "$site_name")
            
            # 提取检测结果
            local old_user
            old_user=$(echo "$detection_result" | grep "OLD_AMQP_USER=" | cut -d'=' -f2)
            local old_vhost
            old_vhost=$(echo "$detection_result" | grep "OLD_AMQP_VHOST=" | cut -d'=' -f2)
            
            # 修复配置
            fix_migration_config "$site_path" "$site_name" "$old_user" "$old_vhost"
            ;;
        *)
            log_error "未知操作: $action"
            exit 1
            ;;
    esac
}

# 如果直接运行脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

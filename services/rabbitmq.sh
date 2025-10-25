#!/bin/bash
# RabbitMQ 服务管理模块
# services/rabbitmq.sh

# RabbitMQ 处理函数
rabbitmq_handler() {
    case "$2" in
        "create")
            if [[ -z "$3" || -z "$4" ]]; then
                log_error "用法: saltgoat rabbitmq create <username> <password>"
                exit 1
            fi
            log_highlight "创建 RabbitMQ 用户: $3"
            rabbitmq_create_user "$3" "$4"
            ;;
        "list")
            log_highlight "列出所有 RabbitMQ 用户..."
            rabbitmq_list_users
            ;;
        "delete")
            if [[ -z "$3" ]]; then
                log_error "用法: saltgoat rabbitmq delete <username>"
                exit 1
            fi
            log_highlight "删除 RabbitMQ 用户: $3"
            rabbitmq_delete_user "$3"
            ;;
        *)
            log_error "未知的 RabbitMQ 操作: $2"
            log_info "支持: create, list, delete"
            exit 1
            ;;
    esac
}

# 创建 RabbitMQ 用户
rabbitmq_create_user() {
    local username="$1"
    local password="$2"
    
    log_info "创建用户: $username"
    salt-call --local rabbitmq.user_create "$username" password="$password"
    
    log_info "设置用户标签"
    salt-call --local rabbitmq.user_set_tags "$username" "administrator"
    
    log_success "RabbitMQ 用户创建成功: $username"
}

# 列出所有用户
rabbitmq_list_users() {
    salt-call --local rabbitmq.user_list
}

# 删除用户
rabbitmq_delete_user() {
    local username="$1"
    
    log_warning "删除用户: $username"
    salt-call --local rabbitmq.user_delete "$username"
    
    log_success "RabbitMQ 用户删除成功: $username"
}

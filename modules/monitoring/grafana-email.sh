#!/bin/bash
# Grafana邮件配置模块
# services/grafana-email.sh

# 配置Grafana邮件通知
configure_grafana_email() {
    log_info "配置Grafana邮件通知..."
    
    # 检查Grafana是否安装
    if ! systemctl is-active --quiet grafana-server 2>/dev/null; then
        log_error "Grafana未安装或未运行"
        return 1
    fi
    
    # 获取邮件配置参数（优先使用环境变量）
    local smtp_host="${1:-${SMTP_HOST:-smtp.gmail.com:587}}"
    local smtp_user="${2:-${SMTP_USER:-}}"
    local smtp_password="${3:-${SMTP_PASSWORD:-}}"
    local from_email="${4:-${SMTP_FROM_EMAIL:-}}"
    local from_name="${5:-${SMTP_FROM_NAME:-SaltGoat Alerts}}"
    
    if [[ -z "$smtp_user" ]] || [[ -z "$smtp_password" ]] || [[ -z "$from_email" ]]; then
        log_error "请提供完整的邮件配置参数"
        log_info "用法: configure_grafana_email <smtp_host> <smtp_user> <smtp_password> <from_email> [from_name]"
        log_info "或设置环境变量: SMTP_HOST, SMTP_USER, SMTP_PASSWORD, SMTP_FROM_EMAIL"
        log_info "示例: configure_grafana_email smtp.gmail.com:587 user@gmail.com password user@gmail.com"
        return 1
    fi
    
    # 备份原始配置
    sudo cp /etc/grafana/grafana.ini /etc/grafana/grafana.ini.backup
    
    # 配置SMTP设置
    sudo tee -a /etc/grafana/grafana.ini > /dev/null <<EOF

[smtp]
enabled = true
host = $smtp_host
user = $smtp_user
password = $smtp_password
from_address = $from_email
from_name = $from_name
skip_verify = false
EOF
    
    # 重启Grafana服务
    sudo systemctl restart grafana-server
    
    if systemctl is-active --quiet grafana-server; then
        log_success "Grafana邮件配置完成"
        log_info "现在可以在Grafana中设置邮件通知渠道"
        log_info "访问: http://$(ip route get 1.1.1.1 | awk '{print $7}' | head -1):3000"
        log_info "路径: Alerting → Contact Points → New Contact Point → Email"
    else
        log_error "Grafana重启失败，恢复原始配置"
        sudo cp /etc/grafana/grafana.ini.backup /etc/grafana/grafana.ini
        sudo systemctl restart grafana-server
        return 1
    fi
}

# 测试邮件发送
test_email_sending() {
    log_info "测试邮件发送..."
    
    local test_email="${1:-}"
    if [[ -z "$test_email" ]]; then
        log_error "请提供测试邮箱地址"
        log_info "用法: test_email_sending <email_address>"
        return 1
    fi
    
    # 使用系统mail命令测试SMTP配置
    log_info "使用系统mail命令测试SMTP配置..."
    
    # 创建测试邮件
    local test_message
    test_message=$(cat <<EOF
SaltGoat SMTP测试邮件
发送时间: $(date)
服务器: $(hostname)
IP地址: $(ip route get 1.1.1.1 | awk '{print $7}' | head -1)

如果您收到此邮件，说明SMTP配置成功！
EOF
)
    
    # 发送测试邮件
    if echo "$test_message" | mail -s "SaltGoat SMTP测试" "$test_email" 2>/dev/null; then
        log_success "测试邮件发送成功"
        log_info "请检查邮箱: $test_email"
        log_info "如果未收到邮件，请检查垃圾邮件文件夹"
    else
        log_warning "系统mail命令不可用，请手动在Grafana中测试"
        log_info "访问: http://$(ip route get 1.1.1.1 | awk '{print $7}' | head -1):3000"
        log_info "路径: Alerting → Contact Points → New Contact Point → Email"
        log_info "配置完成后点击 'Test' 按钮测试邮件发送"
    fi
}

# 获取Grafana API密钥
get_grafana_api_key() {
    # 这里需要实现获取Grafana API密钥的逻辑
    # 暂时返回空，需要用户手动设置
    echo ""
}

# 显示邮件配置帮助
show_email_config_help() {
    echo "=========================================="
    echo "    Grafana邮件配置帮助"
    echo "=========================================="
    echo ""
    echo "支持的SMTP服务:"
    echo "  Gmail: smtp.gmail.com:587"
    echo "  QQ邮箱: smtp.qq.com:587"
    echo "  163邮箱: smtp.163.com:25"
    echo "  企业邮箱: 请联系管理员获取SMTP设置"
    echo ""
    echo "配置步骤:"
    echo "  1. 获取SMTP服务商的应用密码或授权码"
    echo "  2. 运行: saltgoat grafana email <smtp_host> <user> <password> <from_email>"
    echo "  3. 在Grafana中创建邮件通知渠道"
    echo "  4. 测试邮件发送"
    echo ""
    echo "示例:"
    echo "  # Gmail配置"
    echo "  saltgoat grafana email smtp.gmail.com:587 user@gmail.com app_password user@gmail.com"
    echo ""
    echo "  # QQ邮箱配置"
    echo "  saltgoat grafana email smtp.qq.com:587 user@qq.com auth_code user@qq.com"
    echo ""
    echo "注意事项:"
    echo "  - Gmail需要启用两步验证并生成应用密码"
    echo "  - QQ邮箱需要开启SMTP服务并获取授权码"
    echo "  - 163邮箱需要开启SMTP服务并获取授权码"
    echo ""
}

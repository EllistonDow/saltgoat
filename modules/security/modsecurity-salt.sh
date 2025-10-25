#!/bin/bash
# modules/security/modsecurity-salt.sh
# 使用 Salt 原生语法管理 ModSecurity

# 加载日志函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../lib/logger.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"

# ModSecurity Salt 处理器
modsecurity_salt_handler() {
    local command="$2"
    local arg1="$3"

    case "$command" in
        "level")
            if [[ -z "$arg1" ]]; then
                log_error "用法: saltgoat nginx modsecurity level [1-10]"
                exit 1
            fi
            set_modsecurity_level_salt "$arg1"
            ;;
        "status")
            check_modsecurity_status_salt
            ;;
        "disable")
            disable_modsecurity_salt
            ;;
        "enable")
            enable_modsecurity_salt
            ;;
        *)
            log_error "未知的 ModSecurity 操作: $command"
            log_info "支持: level [1-10], status, disable, enable"
            exit 1
            ;;
    esac
}

# 使用 Salt 设置 ModSecurity 等级
set_modsecurity_level_salt() {
    local level="$1"
    
    # 检查等级有效性
    if [[ ! "$level" =~ ^[1-9]$|^10$ ]]; then
        log_error "无效的 ModSecurity 等级: $level (支持 1-10)"
        return 1
    fi
    
    log_highlight "使用 Salt 设置 ModSecurity 等级: $level"
    
    # 动态检测 Magento 后台路径
    local admin_path="/admin"
    if [[ -f "/var/www/tank/bin/magento" ]]; then
        local detected_admin_path
        detected_admin_path=$(cd /var/www/tank && sudo -u www-data php bin/magento info:adminuri 2>/dev/null | grep "Admin URI:" | sed 's/Admin URI: //' | tr -d ' ')
        if [[ -n "$detected_admin_path" ]]; then
            admin_path="$detected_admin_path"
            log_info "检测到 Magento 后台路径: $admin_path"
        fi
    fi
    
    # 使用 Salt 应用配置
    log_info "应用 Salt State: optional.modsecurity"
    if sudo salt-call --local state.apply optional.modsecurity pillar='{"modsecurity_level": '"$level"', "magento_admin_path": "'"$admin_path"'"}'; then
        log_success "ModSecurity 等级 $level 设置成功！"
        log_info "配置特点: $(get_level_description "$level")"
        
        # 重新加载 Nginx
        sudo systemctl reload nginx
        log_info "Nginx 已重新加载"
    else
        log_error "Salt State 应用失败"
        return 1
    fi
}

# 使用 Salt 检查 ModSecurity 状态
check_modsecurity_status_salt() {
    log_highlight "检查 ModSecurity 状态..."
    
    if [[ -f "/etc/nginx/conf/modsecurity.conf" ]]; then
        local engine_status
        engine_status=$(grep "SecRuleEngine" /etc/nginx/conf/modsecurity.conf | head -1)
        local level
        level=$(grep "ModSecurity 等级" /etc/nginx/conf/modsecurity.conf | head -1 | sed 's/.*等级 \([0-9]*\).*/\1/')
        
        if [[ "$engine_status" == *"On"* ]]; then
            log_success "ModSecurity 已启用"
            if [[ -n "$level" ]]; then
                log_info "当前等级: $level"
                log_info "等级描述: $(get_level_description "$level")"
            fi
        else
            log_warning "ModSecurity 已禁用"
        fi
        
        # 检查 Nginx 配置
        if sudo /usr/sbin/nginx -t -c /etc/nginx/nginx.conf >/dev/null 2>&1; then
            log_success "Nginx 配置正常"
        else
            log_error "Nginx 配置有误"
        fi
    else
        log_error "ModSecurity 配置文件不存在"
    fi
}

# 使用 Salt 禁用 ModSecurity
disable_modsecurity_salt() {
    log_highlight "使用 Salt 禁用 ModSecurity..."
    
    # 创建禁用配置
    sudo tee /etc/nginx/conf/modsecurity.conf >/dev/null <<EOF
# ModSecurity 已禁用
SecRuleEngine Off
SecRequestBodyAccess Off
SecResponseBodyAccess Off
EOF
    
    # 测试 Nginx 配置
    if sudo /usr/sbin/nginx -t -c /etc/nginx/nginx.conf; then
        sudo systemctl reload nginx
        log_success "ModSecurity 已禁用"
    else
        log_error "Nginx 配置有误"
        return 1
    fi
}

# 使用 Salt 启用 ModSecurity
enable_modsecurity_salt() {
    log_highlight "使用 Salt 启用 ModSecurity..."
    
    # 使用默认等级 5 启用
    set_modsecurity_level_salt 5
}

# 获取等级描述
get_level_description() {
    local level="$1"
    case "$level" in
        1) echo "开发环境 - 最宽松" ;;
        2) echo "测试环境 - 宽松" ;;
        3) echo "预生产环境 - 中等宽松" ;;
        4) echo "生产环境 - 中等" ;;
        5) echo "生产环境 - 标准" ;;
        6) echo "生产环境 - 严格" ;;
        7) echo "高安全环境 - 很严格" ;;
        8) echo "高安全环境 - 极严格" ;;
        9) echo "最高安全环境 - 最严格" ;;
        10) echo "军事级安全 - 最高级别" ;;
        *) echo "未知等级" ;;
    esac
}

#!/bin/bash
# SaltGoat CSP Salt 原生管理系统
# 使用 Salt 状态管理 CSP 配置

# 加载日志函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ -f "${SCRIPT_DIR}/lib/logger.sh" ]]; then
    # shellcheck source=../../lib/logger.sh
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/lib/logger.sh"
else
    echo "错误: 无法找到 logger.sh"
    exit 1
fi

# CSP 等级配置
declare -A CSP_LEVELS

# 等级 1: 开发环境 - 最宽松
CSP_LEVELS[1]="default-src 'self' http: https: data: blob: 'unsafe-inline' 'unsafe-eval'"

# 等级 2: 测试环境 - 宽松
CSP_LEVELS[2]="default-src 'self' http: https: data: blob: 'unsafe-inline' 'unsafe-eval'; script-src 'self' 'unsafe-inline' 'unsafe-eval'"

# 等级 3: 预生产环境 - 中等宽松
CSP_LEVELS[3]="default-src 'self' http: https: data: blob: 'unsafe-inline'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'"

# 等级 4: 生产环境 - 中等
CSP_LEVELS[4]="default-src 'self' http: https: data: blob:; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' http: https: data:; font-src 'self' http: https: data:"

# 等级 5: 生产环境 - 严格
CSP_LEVELS[5]="default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' http: https: data:; font-src 'self' http: https: data:; connect-src 'self' http: https:; frame-src 'self'"

# 获取等级描述
get_csp_level_description() {
    local level="$1"
    case "$level" in
        1) echo "开发环境 - 最宽松 (允许 unsafe-eval)" ;;
        2) echo "测试环境 - 宽松 (允许 unsafe-eval)" ;;
        3) echo "预生产环境 - 中等宽松" ;;
        4) echo "生产环境 - 中等" ;;
        5) echo "生产环境 - 严格" ;;
        *) echo "未知等级" ;;
    esac
}

# 设置 CSP 等级
set_csp_level() {
    local level="$1"
    
    if [[ -z "$level" ]] || [[ ! "$level" =~ ^[1-5]$ ]]; then
        log_error "无效的 CSP 等级: $level"
        log_info "支持的等级: 1-5"
        return 1
    fi
    
    local csp_policy="${CSP_LEVELS[$level]}"
    log_highlight "设置 CSP 等级 $level: $(get_csp_level_description "$level")"
    log_info "策略: $csp_policy"
    
    # 备份配置文件
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="/etc/nginx/nginx.conf.backup.${timestamp}"
    sudo cp /etc/nginx/nginx.conf "$backup_file"
    
    # 直接更新 Nginx 配置
    sudo sed -i "s|^[[:space:]]*add_header Content-Security-Policy.*|    add_header Content-Security-Policy \"$csp_policy\" always;|" /etc/nginx/nginx.conf
    
    # 测试配置
    if sudo /usr/sbin/nginx -t -c /etc/nginx/nginx.conf; then
        sudo systemctl reload nginx
        log_success "CSP 等级 $level 设置成功"
        log_info "Nginx 已重新加载配置"
    else
        log_error "Nginx 配置有误，恢复备份"
        sudo cp "$backup_file" /etc/nginx/nginx.conf
        return 1
    fi
}

# 检查 CSP 状态
check_csp_status() {
    log_highlight "检查 CSP 状态..."
    
    # 直接检查 Nginx 配置文件
    local csp_line=""
    
    # 最直接的检测方法
    if [[ -f "/etc/nginx/nginx.conf" ]]; then
        # 查找第一个未注释的 CSP 行
        while IFS= read -r line; do
            if [[ "$line" == *"add_header Content-Security-Policy"* ]] && [[ "$line" != "#"* ]] && [[ "$line" != " "*"#"* ]]; then
                csp_line="$line"
                break
            fi
        done < /etc/nginx/nginx.conf
    fi
    
    if [[ -n "$csp_line" ]]; then
        local current_csp="${csp_line#*\"}"
        current_csp="${current_csp%\"*}"
        log_success "CSP 已启用"
        log_info "当前策略: $current_csp"
        
        # 检测当前等级
        local detected_level=""
        for level in {1..5}; do
            if [[ "$current_csp" == "${CSP_LEVELS[$level]}" ]]; then
                detected_level="$level"
                break
            fi
        done
        
        # 如果没有精确匹配，检查部分匹配
        if [[ -z "$detected_level" ]]; then
            if [[ "$current_csp" == *"default-src 'self' http: https: data: blob: 'unsafe-inline'"* ]] && [[ "$current_csp" != *"'unsafe-eval'"* ]]; then
                detected_level="1-"
                log_info "检测到类似等级1的配置（缺少 unsafe-eval）"
            fi
        fi
        
        if [[ -n "$detected_level" ]]; then
            if [[ "$detected_level" != "1-" ]]; then
                log_info "检测到等级: $detected_level"
                log_info "等级描述: $(get_csp_level_description "$detected_level")"
            fi
        else
            log_warning "无法识别 CSP 等级，可能是自定义配置"
        fi
        
        # 验证 Nginx 配置
        if sudo /usr/sbin/nginx -t -c /etc/nginx/nginx.conf >/dev/null 2>&1; then
            log_success "Nginx 配置正常"
        else
            log_warning "Nginx 配置有误"
        fi
    else
        log_warning "CSP 未配置或被注释"
    fi
}

# 禁用 CSP
disable_csp() {
    log_highlight "禁用 CSP..."
    
    # 备份配置文件
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="/etc/nginx/nginx.conf.backup.${timestamp}"
    sudo cp /etc/nginx/nginx.conf "$backup_file"
    
    # 注释掉 CSP 配置
    sudo sed -i 's|^[[:space:]]*add_header Content-Security-Policy|    # add_header Content-Security-Policy|' /etc/nginx/nginx.conf
    
    # 测试配置
    if sudo /usr/sbin/nginx -t -c /etc/nginx/nginx.conf; then
        sudo systemctl reload nginx
        log_success "CSP 已禁用"
    else
        log_error "Nginx 配置有误，恢复备份"
        sudo cp "$backup_file" /etc/nginx/nginx.conf
        return 1
    fi
}

# 启用 CSP
enable_csp() {
    log_highlight "启用 CSP..."
    
    # 备份配置文件
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="/etc/nginx/nginx.conf.backup.${timestamp}"
    sudo cp /etc/nginx/nginx.conf "$backup_file"
    
    # 取消注释 CSP 配置
    sudo sed -i 's|^[[:space:]]*# add_header Content-Security-Policy|    add_header Content-Security-Policy|' /etc/nginx/nginx.conf
    
    # 测试配置
    if sudo /usr/sbin/nginx -t -c /etc/nginx/nginx.conf; then
        sudo systemctl reload nginx
        log_success "CSP 已启用"
    else
        log_error "Nginx 配置有误，恢复备份"
        sudo cp "$backup_file" /etc/nginx/nginx.conf
        return 1
    fi
}

# 主处理函数
csp_salt_handler() {
    case "$2" in
        "level")
            if [[ -z "$3" ]]; then
                log_error "用法: saltgoat nginx csp level <1-5>"
                log_info "等级说明:"
                for i in {1..5}; do
                    log_info "  $i: $(get_csp_level_description "$i")"
                done
                exit 1
            fi
            set_csp_level "$3"
            ;;
        "status")
            check_csp_status
            ;;
        "disable")
            disable_csp
            ;;
        "enable")
            enable_csp
            ;;
        *)
            log_error "未知的 CSP 操作: $2"
            log_info "用法: saltgoat nginx csp <level|status|disable|enable>"
            log_info "示例:"
            log_info "  saltgoat nginx csp level 3"
            log_info "  saltgoat nginx csp status"
            log_info "  saltgoat nginx csp disable"
            log_info "  saltgoat nginx csp enable"
            exit 1
            ;;
    esac
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    csp_salt_handler "$@"
fi

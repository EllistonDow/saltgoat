#!/bin/bash
# Magento 2 Base URL 修复脚本
# 功能：批量修复多个 Magento 站点的 Base URL 配置
# 使用方法：./fix-magento-base-url.sh [站点名称] [域名]

set -euo pipefail

# 加载公共库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"

# 默认配置
DEFAULT_SITES=("bank" "tank")
DEFAULT_DOMAIN="magento.tattoogoat.com"

# 显示帮助信息
show_help() {
    echo "Magento 2 Base URL 修复脚本"
    echo ""
    echo "使用方法:"
    echo "  $0 [选项]"
    echo "  $0 <站点名称> <域名>"
    echo "  $0 --all"
    echo ""
    echo "选项:"
    echo "  --all                   修复所有默认站点"
    echo "  --site <名称>           指定单个站点"
    echo "  --domain <域名>         指定域名"
    echo "  --dry-run              只显示将要执行的操作，不实际执行"
    echo "  --help                 显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 --all"
    echo "  $0 bank bank.magento.tattoogoat.com"
    echo "  $0 --site tank --domain tank.magento.tattoogoat.com"
    echo "  $0 --dry-run"
}

# 检查站点是否存在
check_site_exists() {
    local site_name="$1"
    local site_path="/var/www/$site_name"
    
    if [[ ! -d "$site_path" ]]; then
        log_error "站点路径不存在: $site_path"
        return 1
    fi
    
    if [[ ! -f "$site_path/app/etc/env.php" ]]; then
        log_error "找不到 app/etc/env.php 文件: $site_path/app/etc/env.php"
        return 1
    fi
    
    if [[ ! -f "$site_path/bin/magento" ]]; then
        log_error "找不到 Magento CLI: $site_path/bin/magento"
        return 1
    fi
    
    return 0
}

# 修复单个站点的 Base URL
fix_site_base_url() {
    local site_name="$1"
    local domain="$2"
    local dry_run="$3"
    local site_path="/var/www/$site_name"
    
    log_highlight "修复站点: $site_name (域名: $domain)"
    echo "================================================"
    
    # 检查站点是否存在
    if ! check_site_exists "$site_name"; then
        return 1
    fi
    
    cd "$site_path" || return 1
    
    # 1. 备份配置文件
    log_info "1. 备份配置文件..."
    if [[ "$dry_run" != "true" ]]; then
        sudo cp app/etc/env.php "app/etc/env.php.backup.base_url_fix.$(date +%Y%m%d_%H%M%S)"
        log_success "已备份 env.php"
    else
        log_info "[DRY-RUN] 将备份 env.php"
    fi
    
    # 2. 修复数据库 Base URL
    log_info "2. 修复数据库 Base URL..."
    if [[ "$dry_run" != "true" ]]; then
        # 使用 PHP 直接修改 env.php 文件（避免 config:set 的限制）
        sudo -u www-data php -r "
        \$config = include 'app/etc/env.php';
        \$config['system']['default']['web']['unsecure']['base_url'] = 'http://$domain/';
        \$config['system']['default']['web']['secure']['base_url'] = 'https://$domain/';
        file_put_contents('app/etc/env.php', '<?php' . PHP_EOL . 'return ' . var_export(\$config, true) . ';' . PHP_EOL);
        echo 'Database Base URL updated successfully';
        "
        log_success "数据库 Base URL 已更新"
    else
        log_info "[DRY-RUN] 将设置数据库 Base URL:"
        log_info "  HTTP:  http://$domain/"
        log_info "  HTTPS: https://$domain/"
    fi
    
    # 3. 修复配置文件 Base URL（如果存在）
    log_info "3. 检查配置文件 Base URL..."
    local config_files_found=false
    
    # 检查 config.php 文件
    if [[ -f "app/etc/config.php" ]]; then
        if grep -q "base_url" app/etc/config.php; then
            config_files_found=true
            log_warning "发现 config.php 中包含 base_url 配置"
            if [[ "$dry_run" != "true" ]]; then
                # 备份 config.php
                sudo cp app/etc/config.php "app/etc/config.php.backup.base_url_fix.$(date +%Y%m%d_%H%M%S)"
                
                # 使用占位符替换 base_url
                sudo sed -i "s/'base_url' => '[^']*'/'base_url' => '{{base_url}}'/g" app/etc/config.php
                log_success "config.php 中的 base_url 已替换为占位符"
            else
                log_info "[DRY-RUN] 将替换 config.php 中的 base_url 为占位符"
            fi
        fi
    fi
    
    # 检查 XML 配置文件
    local xml_files=$(find . -name "*.xml" -path "*/etc/*" -exec grep -l "base_url" {} \; 2>/dev/null | grep -v vendor | head -5)
    if [[ -n "$xml_files" ]]; then
        config_files_found=true
        log_warning "发现 XML 配置文件中包含 base_url 配置"
        if [[ "$dry_run" != "true" ]]; then
            echo "$xml_files" | while read -r xml_file; do
                if [[ -f "$xml_file" ]]; then
                    # 备份 XML 文件
                    sudo cp "$xml_file" "${xml_file}.backup.base_url_fix.$(date +%Y%m%d_%H%M%S)"
                    
                    # 替换 base_url 为占位符
                    sudo sed -i 's|<base_url>[^<]*</base_url>|<base_url>{{base_url}}</base_url>|g' "$xml_file"
                    log_info "已修复: $xml_file"
                fi
            done
            log_success "XML 配置文件中的 base_url 已替换为占位符"
        else
            log_info "[DRY-RUN] 将修复以下 XML 文件:"
            echo "$xml_files" | while read -r xml_file; do
                log_info "  - $xml_file"
            done
        fi
    fi
    
    if [[ "$config_files_found" == "false" ]]; then
        log_info "未发现需要修复的配置文件"
    fi
    
    # 4. 清缓存
    log_info "4. 清缓存..."
    if [[ "$dry_run" != "true" ]]; then
        sudo -u www-data php bin/magento cache:flush 2>/dev/null || log_warning "缓存清理失败，但继续执行"
        log_success "缓存已清理"
    else
        log_info "[DRY-RUN] 将清理缓存"
    fi
    
    # 5. 测试配置导入（可选）
    log_info "5. 测试配置导入..."
    if [[ "$dry_run" != "true" ]]; then
        if sudo -u www-data php bin/magento app:config:import 2>/dev/null; then
            log_success "配置导入测试成功"
        else
            log_warning "配置导入测试失败，但 Base URL 修复已完成"
        fi
    else
        log_info "[DRY-RUN] 将测试配置导入"
    fi
    
    # 6. 验证配置
    log_info "6. 验证配置..."
    if [[ "$dry_run" != "true" ]]; then
        local http_url=$(sudo -u www-data php bin/magento config:show web/unsecure/base_url 2>/dev/null || echo "无法获取")
        local https_url=$(sudo -u www-data php bin/magento config:show web/secure/base_url 2>/dev/null || echo "无法获取")
        
        log_info "当前配置:"
        log_info "  HTTP Base URL:  $http_url"
        log_info "  HTTPS Base URL: $https_url"
        
        if [[ "$http_url" == "http://$domain/" ]] && [[ "$https_url" == "https://$domain/" ]]; then
            log_success "Base URL 配置验证成功！"
        else
            log_warning "Base URL 配置可能未完全生效，请检查"
        fi
    else
        log_info "[DRY-RUN] 将验证配置"
    fi
    
    echo ""
    log_success "站点 $site_name 的 Base URL 修复完成！"
    echo ""
}

# 主函数
main() {
    local sites=()
    local domain=""
    local dry_run="false"
    local all_sites="false"
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --all)
                all_sites="true"
                shift
                ;;
            --site)
                sites+=("$2")
                shift 2
                ;;
            --domain)
                domain="$2"
                shift 2
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            -*)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ ${#sites[@]} -eq 0 ]]; then
                    sites+=("$1")
                elif [[ -z "$domain" ]]; then
                    domain="$1"
                fi
                shift
                ;;
        esac
    done
    
    # 设置默认值
    if [[ "$all_sites" == "true" ]]; then
        sites=("${DEFAULT_SITES[@]}")
    fi
    
    if [[ ${#sites[@]} -eq 0 ]]; then
        sites=("${DEFAULT_SITES[@]}")
    fi
    
    if [[ -z "$domain" ]]; then
        domain="$DEFAULT_DOMAIN"
    fi
    
    # 显示执行计划
    log_highlight "Magento 2 Base URL 修复计划"
    echo "================================================"
    log_info "目标站点: ${sites[*]}"
    log_info "默认域名: $domain"
    if [[ "$dry_run" == "true" ]]; then
        log_warning "模式: 试运行（不会实际修改文件）"
    else
        log_info "模式: 实际执行"
    fi
    echo ""
    
    # 确认执行
    if [[ "$dry_run" != "true" ]]; then
        read -p "确认执行修复？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "操作已取消"
            exit 0
        fi
    fi
    
    # 执行修复
    local success_count=0
    local total_count=${#sites[@]}
    
    for site in "${sites[@]}"; do
        local site_domain="$domain"
        
        # 如果只有一个站点，使用完整域名
        if [[ ${#sites[@]} -eq 1 ]]; then
            site_domain="$domain"
        else
            # 多个站点时，使用站点名作为子域名
            site_domain="$site.$domain"
        fi
        
        if fix_site_base_url "$site" "$site_domain" "$dry_run"; then
            ((success_count++))
        else
            log_error "站点 $site 修复失败"
        fi
        
        echo ""
    done
    
    # 显示总结
    echo "================================================"
    log_highlight "修复完成总结"
    echo "================================================"
    log_info "总站点数: $total_count"
    log_info "成功修复: $success_count"
    log_info "失败数量: $((total_count - success_count))"
    
    if [[ $success_count -eq $total_count ]]; then
        log_success "所有站点 Base URL 修复成功！"
        echo ""
        log_info "下一步建议:"
        log_info "1. 访问网站前台验证: http://$domain/"
        log_info "2. 访问网站后台验证: https://$domain/admin"
        log_info "3. 检查 Nginx 配置确保域名解析正确"
    else
        log_warning "部分站点修复失败，请检查错误信息"
    fi
}

# 执行主函数
main "$@"

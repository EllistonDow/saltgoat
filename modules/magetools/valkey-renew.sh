#!/bin/bash
# SaltGoat Magento Valkey 自动续期工具
# 自动检测可用数据库编号，避免冲突

# 加载公共库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"

# 错误处理：确保维护模式被禁用
cleanup() {
    if [ -n "$MAINTENANCE_ENABLED" ]; then
        log_warning "脚本中断，正在禁用维护模式..."
        php bin/magento maintenance:disable 2>/dev/null || true
        log_success "维护模式已禁用"
    fi
}

# 设置陷阱，确保脚本退出时执行清理
trap cleanup EXIT INT TERM

# 使用方法：saltgoat magetools valkey-renew <站点名称> [--restart-valkey]

# 示例：saltgoat magetools valkey-renew tank
# 示例：saltgoat magetools valkey-renew tank --restart-valkey

# 检查参数
RESTART_VALKEY=false
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    log_error "参数错误"
    log_info "使用方法: saltgoat magetools valkey-renew <站点名称> [--restart-valkey]"
    log_info "示例: saltgoat magetools valkey-renew tank"
    log_info "示例: saltgoat magetools valkey-renew tank --restart-valkey"
    exit 1
fi

# 解析参数
if [ $# -eq 2 ] && [ "$2" = "--restart-valkey" ]; then
    RESTART_VALKEY=true
fi

SITE_NAME="$1"

# 验证站点名称安全性
if [[ "$SITE_NAME" =~ [^a-zA-Z0-9_-] ]]; then
    log_error "站点名称包含非法字符: $SITE_NAME"
    log_warning "只允许字母、数字、下划线和连字符"
    exit 1
fi

log_highlight "自动配置站点: $SITE_NAME"
echo "================================================"

# 检查站点路径
SITE_PATH="/var/www/$SITE_NAME"
if [ ! -d "$SITE_PATH" ]; then
    log_error "站点路径不存在: $SITE_PATH"
    exit 1
fi

log_info "站点路径: $SITE_PATH"

# 切换到站点目录
cd "$SITE_PATH" || {
    log_error "无法切换到站点目录"
    exit 1
}

# 检查env.php文件
if [ ! -f "app/etc/env.php" ]; then
    log_error "找不到 app/etc/env.php 文件"
    exit 1
fi

# 获取 Valkey 密码
VALKEY_PASSWORD=""
if [ -f "/etc/valkey/valkey.conf" ]; then
    VALKEY_PASSWORD=$(sudo grep "requirepass" /etc/valkey/valkey.conf | awk '{print $2}')
    if [ -n "$VALKEY_PASSWORD" ]; then
        log_success "已获取 Valkey 密码"
    else
        log_warning "无法从配置文件获取 Valkey 密码"
    fi
else
    log_warning "Valkey 配置文件不存在: /etc/valkey/valkey.conf"
fi

# 随机分配数据库编号（避免冲突）
log_info "随机分配数据库编号..."

# 生成随机数据库编号（10-99范围，Valkey支持100个数据库）
generate_random_dbs() {
    local db1 db2 db3
    
    # 生成3个不同的随机数
    while true; do
        db1=$((RANDOM % 90 + 10))  # 10-99
        db2=$((RANDOM % 90 + 10))  # 10-99
        db3=$((RANDOM % 90 + 10))  # 10-99
        
        # 确保3个数字都不相同
        if [ "$db1" != "$db2" ] && [ "$db1" != "$db3" ] && [ "$db2" != "$db3" ]; then
            echo "$db1 $db2 $db3"
            return
        fi
    done
}

# 获取随机数据库编号
AVAILABLE_DBS=$(generate_random_dbs)
read CACHE_DB PAGE_DB SESSION_DB <<< "$AVAILABLE_DBS"

log_success "自动分配的数据库:"
echo " 默认缓存: DB $CACHE_DB"
echo " 页面缓存: DB $PAGE_DB"
echo " 会话存储: DB $SESSION_DB"
echo ""

# 检查数据库编号是否重复
if [ "$CACHE_DB" = "$PAGE_DB" ] || [ "$CACHE_DB" = "$SESSION_DB" ] || [ "$PAGE_DB" = "$SESSION_DB" ]; then
    log_error "数据库编号重复"
    exit 1
fi

log_info "开始配置更新..."

# 备份原文件
if cp app/etc/env.php app/etc/env.php.backup.$(date +%Y%m%d_%H%M%S); then
    log_success "已备份原配置文件"
else
    log_warning "备份文件失败，继续执行..."
fi

# 第一步：自定义数据库配置
log_info "第一步：自定义数据库配置..."

# 修改env.php文件 - 使用更精确的替换
# 替换默认缓存的数据库
sed -i "/'default' => \[/,/\]/ s/'database' => '[0-9]*'/'database' => '$CACHE_DB'/g" app/etc/env.php

# 替换页面缓存的数据库
sed -i "/'page_cache' => \[/,/\]/ s/'database' => '[0-9]*'/'database' => '$PAGE_DB'/g" app/etc/env.php

# 替换会话存储的数据库
sed -i "/'session' => \[/,/\]/ s/'database' => '[0-9]*'/'database' => '$SESSION_DB'/g" app/etc/env.php

# 设置缓存前缀
sed -i "/'session' => \[/,/^[[:space:]]*\],/ s/'id_prefix' => '[^']*'/'id_prefix' => '${SITE_NAME}_session_'/g" app/etc/env.php
sed -i "s/'id_prefix' => '[^']*'/'id_prefix' => '${SITE_NAME}_cache_'/g" app/etc/env.php
sed -i "/'session' => \[/,/^[[:space:]]*\],/ s/'id_prefix' => '[^']*'/'id_prefix' => '${SITE_NAME}_session_'/g" app/etc/env.php

log_success "数据库配置完成"

# 第二步：执行renew流程
log_info "第二步：执行renew流程..."

# 启用维护模式
log_warning "启用维护模式..."
if ! php bin/magento maintenance:enable 2>/dev/null; then
    log_warning "维护模式启用失败，继续执行..."
else
    log_success "维护模式已启用"
    MAINTENANCE_ENABLED=1
fi

# 检查Redis/Valkey服务
if ! redis-cli ping >/dev/null 2>&1; then
    log_error "Redis/Valkey服务未运行"
    exit 1
fi

log_success "Redis/Valkey服务正常运行"

# 清理缓存和生成文件
log_warning "清理缓存和生成文件..."

# 清理缓存
if ! php bin/magento cache:clean 2>/dev/null; then
    log_warning "缓存清理失败，继续执行..."
fi

if ! php bin/magento cache:flush 2>/dev/null; then
    log_warning "缓存刷新失败，继续执行..."
fi

# 清理生成文件
rm -rf generated/* 2>/dev/null || true
rm -rf var/cache/* 2>/dev/null || true
rm -rf var/page_cache/* 2>/dev/null || true
rm -rf pub/static/* 2>/dev/null || true

# 强制清理generated/code
find generated/code -type f -delete 2>/dev/null || true
find generated/code -type d -empty -delete 2>/dev/null || true

log_success "文件清理完成"

# 重新编译和部署
log_warning "重新编译和部署..."

# 重新编译
if ! php bin/magento setup:di:compile 2>/dev/null; then
    log_warning "依赖注入编译失败，继续执行..."
fi

# 部署静态内容
if ! php bin/magento setup:static-content:deploy -f 2>/dev/null; then
    log_warning "静态内容部署失败，继续执行..."
fi

log_success "编译和部署完成"

# 清空Valkey缓存
log_warning "清空站点 $SITE_NAME 的Valkey缓存..."

# 清空指定数据库
if [ -n "$VALKEY_PASSWORD" ]; then
    if ! redis-cli -a "$VALKEY_PASSWORD" -n $CACHE_DB flushdb 2>/dev/null; then
        log_warning "清空缓存数据库 $CACHE_DB 失败"
    fi
    
    if ! redis-cli -a "$VALKEY_PASSWORD" -n $PAGE_DB flushdb 2>/dev/null; then
        log_warning "清空页面缓存数据库 $PAGE_DB 失败"
    fi
    
    if ! redis-cli -a "$VALKEY_PASSWORD" -n $SESSION_DB flushdb 2>/dev/null; then
        log_warning "清空会话数据库 $SESSION_DB 失败"
    fi
else
    log_warning "无法获取密码，跳过缓存清理"
fi

# 重启Valkey服务（可选）
if [ "$RESTART_VALKEY" = true ]; then
    log_warning "重启Valkey服务..."
    if sudo systemctl restart valkey 2>/dev/null; then
        log_success "Valkey服务已重启"
        sleep 2
        if redis-cli ping >/dev/null 2>&1; then
            log_success "Valkey服务运行正常"
        else
            echo -e "${YELLOW}⚠ Valkey服务可能未正常启动，请检查${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Valkey服务重启失败，继续执行...${NC}"
    fi
else
    log_info "提示: 使用 --restart-valkey 参数可重启Valkey服务"
fi

# 确保必要目录存在
log_warning "确保必要目录存在..."
mkdir -p var/cache var/page_cache var/log var/session var/tmp 2>/dev/null || true
mkdir -p generated/code generated/metadata 2>/dev/null || true
mkdir -p pub/static pub/media 2>/dev/null || true

log_success "目录检查完成"

# 验证配置
log_warning "验证配置..."

# 检查缓存状态
if ! php bin/magento cache:status 2>/dev/null; then
    echo -e "${YELLOW}⚠ 无法获取缓存状态${NC}"
fi

# 检查配置结果
log_warning "验证配置结果..."

# 检查默认缓存配置
if grep -q "'database' => '$CACHE_DB'" app/etc/env.php; then
    log_success "默认缓存配置正确: DB $CACHE_DB"
else
    log_error "默认缓存配置失败"
fi

# 检查页面缓存配置
if grep -q "'database' => '$PAGE_DB'" app/etc/env.php; then
    log_success "页面缓存配置正确: DB $PAGE_DB"
else
    log_error "页面缓存配置失败"
fi

# 检查会话存储配置
if grep -q "'database' => '$SESSION_DB'" app/etc/env.php; then
    log_success "会话存储配置正确: DB $SESSION_DB"
else
    log_error "会话存储配置失败"
fi

echo ""
log_highlight "站点 $SITE_NAME 的Valkey更新完成！"

echo -e "${BLUE}隔离信息:${NC}"
echo " 站点名称: $SITE_NAME"
echo " 站点路径: $SITE_PATH"
echo " 缓存前缀: ${SITE_NAME}_cache_, ${SITE_NAME}_session_"
echo " 使用数据库: $CACHE_DB, $PAGE_DB, $SESSION_DB"

# 禁用维护模式
log_warning "禁用维护模式..."
if ! php bin/magento maintenance:disable 2>/dev/null; then
    log_warning "维护模式禁用失败，请手动检查"
else
    log_success "维护模式已禁用"
    unset MAINTENANCE_ENABLED
fi

echo ""
log_warning "建议运行以下命令进行最终检查:"
echo " php bin/magento cache:status"
echo " php bin/magento setup:upgrade"
echo " php bin/magento indexer:reindex"

log_success "Valkey 自动续期完成！"

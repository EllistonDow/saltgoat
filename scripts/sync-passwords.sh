#!/bin/bash
# 密码同步脚本 - 确保所有服务使用正确的密码
# scripts/sync-passwords.sh

# 加载公共库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/utils.sh"

check_permissions "$@"

# 从命令行参数或环境变量获取密码
MYSQL_PASSWORD="${1:-$MYSQL_PASSWORD}"
VALKEY_PASSWORD="${2:-$VALKEY_PASSWORD}"
RABBITMQ_PASSWORD="${3:-$RABBITMQ_PASSWORD}"
WEBMIN_PASSWORD="${4:-$WEBMIN_PASSWORD}"
PHPMYADMIN_PASSWORD="${5:-$PHPMYADMIN_PASSWORD}"

# 设置默认值（优先使用现有 Pillar 配置）
MYSQL_PASSWORD="${MYSQL_PASSWORD:-$(get_local_pillar_value mysql_password 'SaltGoat2024!')}"
VALKEY_PASSWORD="${VALKEY_PASSWORD:-$(get_local_pillar_value valkey_password 'SaltGoat2024!')}"
RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-$(get_local_pillar_value rabbitmq_password 'SaltGoat2024!')}"
WEBMIN_PASSWORD="${WEBMIN_PASSWORD:-$(get_local_pillar_value webmin_password 'SaltGoat2024!')}"
PHPMYADMIN_PASSWORD="${PHPMYADMIN_PASSWORD:-$(get_local_pillar_value phpmyadmin_password 'SaltGoat2024!')}"

log_highlight "同步服务密码..."

# 更新 Salt Pillar
log_info "更新 Salt Pillar 配置..."
set_local_pillar_value mysql_password "$MYSQL_PASSWORD"
set_local_pillar_value valkey_password "$VALKEY_PASSWORD"
set_local_pillar_value rabbitmq_password "$RABBITMQ_PASSWORD"
set_local_pillar_value webmin_password "$WEBMIN_PASSWORD"
set_local_pillar_value phpmyadmin_password "$PHPMYADMIN_PASSWORD"

# 重新应用 Salt States 以更新服务密码
log_info "重新应用 Salt States..."

# MySQL 密码更新
if mysql -u root -p"$MYSQL_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1; then
    log_info "MySQL 密码已正确"
else
    log_info "更新 MySQL 密码..."
    sudo salt-call --local state.apply core.mysql pillar='{"mysql_password":"'"$MYSQL_PASSWORD"'"}'
fi

# Valkey 密码更新
log_info "更新 Valkey 密码..."
sudo salt-call --local state.apply optional.valkey pillar='{"valkey_password":"'"$VALKEY_PASSWORD"'"}'

# RabbitMQ 密码更新
log_info "更新 RabbitMQ 密码..."
sudo salt-call --local state.apply optional.rabbitmq pillar='{"rabbitmq_password":"'"$RABBITMQ_PASSWORD"'"}'

# Webmin 密码更新
log_info "更新 Webmin 密码..."
sudo salt-call --local state.apply optional.webmin pillar='{"webmin_password":"'"$WEBMIN_PASSWORD"'"}'

log_success "密码同步完成！"
log_info "当前密码："
echo "MySQL: $MYSQL_PASSWORD"
echo "Valkey: $VALKEY_PASSWORD"
echo "RabbitMQ: $RABBITMQ_PASSWORD"
echo "Webmin: $WEBMIN_PASSWORD"
echo "phpMyAdmin: $PHPMYADMIN_PASSWORD"

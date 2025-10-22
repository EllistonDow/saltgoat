#!/bin/bash
# Webmin 修复脚本
# scripts/fix-webmin.sh

# 加载公共库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"

WEBMIN_PASSWORD="${1:-Webmin123!}"

log_highlight "修复 Webmin 认证问题..."

# 1. 设置系统用户 root 密码
log_info "设置系统用户 root 密码..."
echo "root:${WEBMIN_PASSWORD}" | sudo chpasswd

# 2. 修复 Webmin 配置
log_info "修复 Webmin 配置..."
sudo tee /etc/webmin/miniserv.conf > /dev/null << 'EOF'
# Webmin 基本配置
port=10000
root=/usr/share/webmin
mimetypes=/usr/share/webmin/mime.types
addtype_cgi=internal/cgi
realm=Webmin Server
logfile=/var/webmin/miniserv.log
errorlog=/var/webmin/miniserv.error
pidfile=/var/webmin/miniserv.pid
logtime=168
ssl=0
env_WEBMIN_CONFIG=/etc/webmin
env_WEBMIN_VAR=/var/webmin
atboot=1
userfile=/etc/webmin/miniserv.users
EOF

# 3. 创建 Webmin 用户文件
log_info "创建 Webmin 用户文件..."
sudo htpasswd -c /etc/webmin/miniserv.users root << EOF
${WEBMIN_PASSWORD}
${WEBMIN_PASSWORD}
EOF

# 4. 设置正确的权限
log_info "设置文件权限..."
sudo chown root:root /etc/webmin/miniserv.users
sudo chmod 600 /etc/webmin/miniserv.users
sudo chown root:root /etc/webmin/miniserv.conf
sudo chmod 600 /etc/webmin/miniserv.conf

# 5. 重启 Webmin 服务
log_info "重启 Webmin 服务..."
sudo systemctl restart webmin

# 6. 等待服务启动
sleep 3

# 7. 测试连接
log_info "测试 Webmin 连接..."
if curl -u root:${WEBMIN_PASSWORD} http://localhost:10000 2>/dev/null | grep -q "401"; then
    log_error "Webmin 认证仍然失败"
    log_info "检查 Webmin 日志："
    sudo tail -10 /var/webmin/miniserv.log
    exit 1
else
    log_success "Webmin 认证成功！"
fi

log_success "Webmin 修复完成！"
log_info "访问地址: http://your-server-ip:10000"
log_info "用户名: root"
log_info "密码: ${WEBMIN_PASSWORD}"

#!/bin/bash
# 测试 Nginx 配置一致性脚本
# 验证 git clone 安装后 nginx -t 命令是否正常工作

echo "=========================================="
echo "    Nginx 配置一致性测试"
echo "=========================================="

# 检查符号链接是否存在
echo "[INFO] 检查 Nginx 符号链接..."

if [[ -L "/usr/sbin/nginx" ]]; then
    echo "[SUCCESS] /usr/sbin/nginx 符号链接存在"
    echo "[INFO] 指向: $(readlink /usr/sbin/nginx)"
else
    echo "[ERROR] /usr/sbin/nginx 符号链接不存在"
    exit 1
fi

if [[ -L "/etc/nginx/conf/nginx.conf" ]]; then
    echo "[SUCCESS] /etc/nginx/conf/nginx.conf 符号链接存在"
    echo "[INFO] 指向: $(readlink /etc/nginx/conf/nginx.conf)"
else
    echo "[ERROR] /etc/nginx/conf/nginx.conf 符号链接不存在"
    exit 1
fi

# 测试 nginx -t 命令
echo ""
echo "[INFO] 测试 nginx -t 命令..."
if sudo nginx -t >/dev/null 2>&1; then
    echo "[SUCCESS] nginx -t 命令正常工作"
else
    echo "[ERROR] nginx -t 命令失败"
    sudo nginx -t
    exit 1
fi

# 测试 nginx -v 命令
echo ""
echo "[INFO] 测试 nginx -v 命令..."
nginx_version=$(nginx -v 2>&1)
echo "[SUCCESS] Nginx 版本: $nginx_version"

# 测试 systemd 服务状态
echo ""
echo "[INFO] 检查 Nginx 服务状态..."
if systemctl is-active --quiet nginx; then
    echo "[SUCCESS] Nginx 服务正在运行"
else
    echo "[WARNING] Nginx 服务未运行"
fi

# 检查配置文件内容
echo ""
echo "[INFO] 检查配置文件内容..."
if [[ -f "/etc/nginx/nginx.conf" ]]; then
    echo "[SUCCESS] 主配置文件存在: /etc/nginx/nginx.conf"
    
    # 检查是否包含 ModSecurity 配置
    if grep -q "modsecurity" /etc/nginx/nginx.conf; then
        echo "[SUCCESS] ModSecurity 配置已包含"
    else
        echo "[WARNING] ModSecurity 配置未找到"
    fi
    
    # 检查是否包含 sites-enabled
    if grep -q "sites-enabled" /etc/nginx/nginx.conf; then
        echo "[SUCCESS] sites-enabled 配置已包含"
    else
        echo "[WARNING] sites-enabled 配置未找到"
    fi
else
    echo "[ERROR] 主配置文件不存在"
    exit 1
fi

echo ""
echo "[SUCCESS] Nginx 配置一致性测试通过！"
echo "[INFO] git clone 安装后所有功能正常"

#!/bin/bash
# 测试 Nginx 配置一致性脚本
# 验证 git clone 安装后 nginx -t 命令是否正常工作

echo "=========================================="
echo "    Nginx 配置一致性测试"
echo "=========================================="

# 检查符号链接是否存在
echo "[INFO] 检查 Nginx 符号链接..."

if [[ -x "/usr/sbin/nginx" ]]; then
    if [[ -L "/usr/sbin/nginx" ]]; then
        echo "[SUCCESS] /usr/sbin/nginx 符号链接存在"
        echo "[INFO] 指向: $(readlink /usr/sbin/nginx)"
    else
        echo "[SUCCESS] /usr/sbin/nginx 可执行文件存在"
    fi
else
    echo "[ERROR] 未找到 /usr/sbin/nginx 可执行文件"
    exit 1
fi

if [[ -e "/etc/nginx/nginx.conf" ]]; then
    if [[ -L "/etc/nginx/nginx.conf" ]]; then
        echo "[SUCCESS] /etc/nginx/nginx.conf 符号链接存在"
        echo "[INFO] 指向: $(readlink /etc/nginx/nginx.conf)"
    else
        echo "[SUCCESS] /etc/nginx/nginx.conf 文件存在"
    fi
else
    echo "[ERROR] /etc/nginx/nginx.conf 文件不存在"
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

# 检查 ModSecurity 与 CSP 配置文件
echo ""
echo "[INFO] 检查安全附加配置..."

if [[ -f "/etc/nginx/conf.d/modsecurity.conf" ]]; then
    echo "[SUCCESS] /etc/nginx/conf.d/modsecurity.conf 存在"
else
    echo "[INFO] 未启用 ModSecurity（未找到 conf.d/modsecurity.conf）"
fi

if [[ -f "/etc/nginx/conf.d/csp.conf" ]]; then
    echo "[SUCCESS] /etc/nginx/conf.d/csp.conf 存在"
else
    echo "[INFO] 未启用 CSP（未找到 conf.d/csp.conf）"
fi

echo ""
echo "[SUCCESS] Nginx 配置一致性测试通过！"
echo "[INFO] git clone 安装后所有功能正常"

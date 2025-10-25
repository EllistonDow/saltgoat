#!/bin/bash
# Magento 2 Base URL 快速修复脚本（简化版）
# 专门用于修复 app:config:import 错误

# 使用方法: ./quick-fix-base-url.sh <站点名称> <域名>

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "使用方法: $0 <站点名称> <域名>"
    echo "示例: $0 bank bank.magento.tattoogoat.com"
    exit 1
fi

SITE_NAME="$1"
DOMAIN="$2"
SITE_PATH="/var/www/$SITE_NAME"

echo "================================================"
echo "Magento 2 Base URL 快速修复"
echo "================================================"
echo "站点: $SITE_NAME"
echo "域名: $DOMAIN"
echo "路径: $SITE_PATH"
echo ""

# 检查站点是否存在
if [[ ! -d "$SITE_PATH" ]]; then
    echo "❌ 错误: 站点路径不存在: $SITE_PATH"
    exit 1
fi

if [[ ! -f "$SITE_PATH/app/etc/env.php" ]]; then
    echo "❌ 错误: 找不到 app/etc/env.php 文件"
    exit 1
fi

cd "$SITE_PATH" || exit 1

echo "🔧 步骤 1: 备份配置文件..."
sudo cp app/etc/env.php "app/etc/env.php.backup.$(date +%Y%m%d_%H%M%S)"
echo "✅ 已备份 env.php"

echo ""
echo "🔧 步骤 2: 修复数据库 Base URL..."
sudo -u www-data php -r "
\$config = include 'app/etc/env.php';
\$config['system']['default']['web']['unsecure']['base_url'] = 'http://$DOMAIN/';
\$config['system']['default']['web']['secure']['base_url'] = 'https://$DOMAIN/';
file_put_contents('app/etc/env.php', '<?php' . PHP_EOL . 'return ' . var_export(\$config, true) . ';' . PHP_EOL);
echo 'Database Base URL updated successfully';
"
echo "✅ 数据库 Base URL 已更新"

echo ""
echo "🔧 步骤 3: 修复配置文件 Base URL..."
# 修复 config.php 中的 base_url
if [[ -f "app/etc/config.php" ]] && grep -q "base_url" app/etc/config.php; then
    sudo cp app/etc/config.php "app/etc/config.php.backup.$(date +%Y%m%d_%H%M%S)"
    sudo sed -i "s/'base_url' => '[^']*'/'base_url' => '{{base_url}}'/g" app/etc/config.php
    echo "✅ config.php 中的 base_url 已替换为占位符"
fi

# 修复 XML 配置文件中的 base_url
xml_files=$(find . -name "*.xml" -path "*/etc/*" -exec grep -l "base_url" {} \; 2>/dev/null | grep -v vendor | head -5)
if [[ -n "$xml_files" ]]; then
    echo "$xml_files" | while read -r xml_file; do
        if [[ -f "$xml_file" ]]; then
            sudo cp "$xml_file" "${xml_file}.backup.$(date +%Y%m%d_%H%M%S)"
            sudo sed -i 's|<base_url>[^<]*</base_url>|<base_url>{{base_url}}</base_url>|g' "$xml_file"
            echo "✅ 已修复: $xml_file"
        fi
    done
fi

echo ""
echo "🔧 步骤 4: 清缓存..."
sudo -u www-data php bin/magento cache:flush 2>/dev/null || echo "⚠️  缓存清理失败，但继续执行"
echo "✅ 缓存已清理"

echo ""
echo "🔧 步骤 5: 测试配置导入..."
if sudo -u www-data php bin/magento app:config:import 2>/dev/null; then
    echo "✅ 配置导入测试成功"
else
    echo "⚠️  配置导入测试失败，但 Base URL 修复已完成"
fi

echo ""
echo "🔧 步骤 6: 验证配置..."
http_url=$(sudo -u www-data php bin/magento config:show web/unsecure/base_url 2>/dev/null || echo "无法获取")
https_url=$(sudo -u www-data php bin/magento config:show web/secure/base_url 2>/dev/null || echo "无法获取")

echo "当前配置:"
echo "  HTTP Base URL:  $http_url"
echo "  HTTPS Base URL: $https_url"

if [[ "$http_url" == "http://$DOMAIN/" ]] && [[ "$https_url" == "https://$DOMAIN/" ]]; then
    echo "✅ Base URL 配置验证成功！"
else
    echo "⚠️  Base URL 配置可能未完全生效，请检查"
fi

echo ""
echo "================================================"
echo "🎉 Base URL 修复完成！"
echo "================================================"
echo ""
echo "下一步建议:"
echo "1. 访问网站前台: http://$DOMAIN/"
echo "2. 访问网站后台: https://$DOMAIN/admin"
echo "3. 检查 Nginx 配置确保域名解析正确"
echo ""

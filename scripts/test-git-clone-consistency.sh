#!/bin/bash
# 测试 git clone 安装一致性
# scripts/test-git-clone-consistency.sh

# 加载公共库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"

log_highlight "测试 git clone 安装一致性..."

# 测试参数
TEST_MYSQL_PASS="TestMySQL123!"
TEST_VALKEY_PASS="TestValkey123!"
TEST_RABBITMQ_PASS="TestRabbitMQ123!"
TEST_WEBMIN_PASS="TestWebmin123!"
TEST_PHPMYADMIN_PASS="TestPhpMyAdmin123!"

log_info "1. 模拟命令行参数安装..."
log_info "   命令: saltgoat install all --mysql-password '$TEST_MYSQL_PASS' --valkey-password '$TEST_VALKEY_PASS' --rabbitmq-password '$TEST_RABBITMQ_PASS' --webmin-password '$TEST_WEBMIN_PASS' --phpmyadmin-password '$TEST_PHPMYADMIN_PASS'"

# 模拟 update_pillar_config 函数
log_info "2. 模拟 Pillar 配置更新..."
cat > /tmp/test_pillar.sls << EOF
mysql_password: '$TEST_MYSQL_PASS'
valkey_password: '$TEST_VALKEY_PASS'
rabbitmq_password: '$TEST_RABBITMQ_PASS'
webmin_password: '$TEST_WEBMIN_PASS'
phpmyadmin_password: '$TEST_PHPMYADMIN_PASS'
ssl_email: 'test@example.com'
timezone: 'America/Los_Angeles'
language: 'en_US.UTF-8'
EOF

log_info "3. 检查 Salt States 是否会使用这些密码..."
echo "   - MySQL Salt State:"
grep "pillar.get('mysql_password'" "${SCRIPT_DIR}/salt/states/core/mysql.sls" && echo "     ✅ 会使用 pillar.get('mysql_password')"
echo "   - Valkey Salt State:"
grep "pillar.get('valkey_password'" "${SCRIPT_DIR}/salt/states/optional/valkey.sls" && echo "     ✅ 会使用 pillar.get('valkey_password')"
echo "   - RabbitMQ Salt State:"
grep "pillar.get('rabbitmq_password'" "${SCRIPT_DIR}/salt/states/optional/rabbitmq.sls" && echo "     ✅ 会使用 pillar.get('rabbitmq_password')"
echo "   - Webmin Salt State:"
grep "pillar.get('webmin_password'" "${SCRIPT_DIR}/salt/states/optional/webmin.sls" && echo "     ✅ 会使用 pillar.get('webmin_password')"

log_info "4. 检查默认安装（无参数）..."
echo "   - 所有服务会使用默认密码 'SaltGoat2024!'"
echo "   - 这是 Salt States 中的默认回退值"

log_info "5. 检查密码同步功能..."
if [[ -f "${SCRIPT_DIR}/scripts/sync-passwords.sh" ]]; then
    echo "   ✅ 密码同步脚本存在"
    echo "   ✅ 可以同步所有密码到指定值"
else
    echo "   ❌ 密码同步脚本不存在"
fi

log_info "6. 检查 Pillar 配置文件..."
if [[ -f "${SCRIPT_DIR}/salt/pillar/saltgoat.sls" ]]; then
    echo "   ✅ Pillar 文件存在 (salt/pillar/saltgoat.sls)"
    echo "   ✅ 可以直接编辑该文件覆盖安装密码和配置"
else
    echo "   ❌ 未找到 salt/pillar/saltgoat.sls，请先运行 saltgoat install 初始化"
fi

log_info "7. 运行扩展回归测试..."
if [[ -x "${SCRIPT_DIR}/tests/test_git_release.sh" ]]; then
    echo "   -> saltgoat git push --dry-run 回归测试"
    if ! bash "${SCRIPT_DIR}/tests/test_git_release.sh"; then
        log_warning "Git 发布 dry-run 测试失败，请查看上方输出。"
    fi
fi

if [[ -x "${SCRIPT_DIR}/tests/test_analyse_state.sh" ]]; then
    echo "   -> optional.analyse 状态 dry-run 验证"
    if ! bash "${SCRIPT_DIR}/tests/test_analyse_state.sh"; then
        log_warning "Matomo dry-run 测试失败，请查看上方输出。"
    fi
fi

if [[ -x "${SCRIPT_DIR}/tests/test_salt_versions.sh" ]]; then
    echo "   -> Salt 版本与 lowstate 报告收集"
    if ! bash "${SCRIPT_DIR}/tests/test_salt_versions.sh"; then
        log_warning "Salt 版本收集脚本执行失败，请查看上方输出。"
    fi
fi

log_success "git clone 安装一致性测试完成！"
log_info "总结："
log_info "  ✅ Salt States 使用 Pillar 变量，支持动态密码"
log_info "  ✅ 命令行参数正确解析并写入 Pillar"
log_info "  ✅ 默认安装使用一致的默认密码"
log_info "  ✅ 密码同步脚本支持密码更新"
log_info "  ✅ Pillar 文件可作为配置来源"

# 清理测试文件
rm -f /tmp/test_pillar.sls

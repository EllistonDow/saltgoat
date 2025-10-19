#!/bin/bash

# SaltGoat 系统安装脚本
# 将 SaltGoat 安装到系统路径，无需 ./ 和 sudo

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否以 root 运行
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "请不要以 root 用户运行此脚本"
        log_info "请使用普通用户运行，脚本会自动处理权限"
        exit 1
    fi
}

# 获取 SaltGoat 安装路径
get_saltgoat_path() {
    SALTGOAT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    log_info "SaltGoat 路径: $SALTGOAT_PATH"
}

# 安装 SaltGoat 到系统路径
install_saltgoat() {
    log_info "正在安装 SaltGoat 到系统路径..."
    
    # 创建符号链接到 /usr/local/bin
    sudo ln -sf "$SALTGOAT_PATH/saltgoat" /usr/local/bin/saltgoat
    log_success "已创建符号链接: /usr/local/bin/saltgoat"
    
    # 创建管理脚本的符号链接
    sudo ln -sf "$SALTGOAT_PATH/manage-mysql.sh" /usr/local/bin/manage-mysql
    sudo ln -sf "$SALTGOAT_PATH/manage-nginx.sh" /usr/local/bin/manage-nginx
    sudo ln -sf "$SALTGOAT_PATH/manage-rabbitmq.sh" /usr/local/bin/manage-rabbitmq
    sudo ln -sf "$SALTGOAT_PATH/manage-schedules.sh" /usr/local/bin/manage-schedules
    
    log_success "已创建管理脚本符号链接"
}

# 配置 sudo 权限
configure_sudo() {
    log_info "正在配置 sudo 权限..."
    
    # 检查是否已存在配置
    if sudo grep -q "saltgoat" /etc/sudoers.d/saltgoat 2>/dev/null; then
        log_warning "sudo 配置已存在，跳过"
        return
    fi
    
    # 创建 sudoers.d 文件
    sudo tee /etc/sudoers.d/saltgoat > /dev/null << EOF
# SaltGoat 权限配置
# 允许当前用户无密码运行 SaltGoat 相关命令
$USER ALL=(ALL) NOPASSWD: /usr/local/bin/saltgoat
$USER ALL=(ALL) NOPASSWD: /usr/local/bin/manage-mysql
$USER ALL=(ALL) NOPASSWD: /usr/local/bin/manage-nginx
$USER ALL=(ALL) NOPASSWD: /usr/local/bin/manage-rabbitmq
$USER ALL=(ALL) NOPASSWD: /usr/local/bin/manage-schedules
EOF
    
    log_success "已配置 sudo 权限"
}

# 创建用户别名
create_aliases() {
    log_info "正在创建用户别名..."
    
    # 检查是否已存在别名
    if grep -q "saltgoat" ~/.bashrc 2>/dev/null; then
        log_warning "别名已存在，跳过"
        return
    fi
    
    # 添加别名到 ~/.bashrc
    cat >> ~/.bashrc << EOF

# SaltGoat 别名
alias saltgoat='sudo /usr/local/bin/saltgoat'
alias manage-mysql='sudo /usr/local/bin/manage-mysql'
alias manage-nginx='sudo /usr/local/bin/manage-nginx'
alias manage-rabbitmq='sudo /usr/local/bin/manage-rabbitmq'
alias manage-schedules='sudo /usr/local/bin/manage-schedules'
EOF
    
    log_success "已创建用户别名"
}

# 测试安装
test_installation() {
    log_info "正在测试安装..."
    
    # 测试 saltgoat 命令
    if command -v saltgoat >/dev/null 2>&1; then
        log_success "saltgoat 命令可用"
    else
        log_error "saltgoat 命令不可用"
        return 1
    fi
    
    # 测试 sudo 权限
    if sudo -n saltgoat --help >/dev/null 2>&1; then
        log_success "sudo 权限配置正确"
    else
        log_warning "sudo 权限配置可能有问题，请手动检查"
    fi
}

# 显示使用说明
show_usage() {
    echo
    log_success "SaltGoat 安装完成！"
    echo
    echo "现在你可以直接使用以下命令："
    echo "  saltgoat install all"
    echo "  saltgoat status"
    echo "  saltgoat versions"
    echo "  saltgoat passwords"
    echo "  saltgoat optimize magento"
    echo
echo "管理脚本："
echo "  manage-mysql create mysite mypassword"
echo "  manage-nginx create mysite example.com"
echo "  manage-rabbitmq create mysite mypassword"
echo "  manage-schedules enable    # 启用定时任务"
echo "  manage-schedules status    # 查看任务状态"
    echo
    echo "注意：首次使用需要重新加载 shell 环境："
    echo "  source ~/.bashrc"
    echo "  或者重新打开终端"
    echo
}

# 主函数
main() {
    echo "SaltGoat 系统安装脚本"
    echo "======================"
    echo
    
    check_root
    get_saltgoat_path
    install_saltgoat
    configure_sudo
    create_aliases
    test_installation
    show_usage
}

# 运行主函数
main "$@"

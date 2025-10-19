#!/bin/bash

# SaltGoat 系统卸载脚本
# 移除系统路径中的 SaltGoat 安装

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

# 移除符号链接
remove_symlinks() {
    log_info "正在移除符号链接..."
    
    # 移除 saltgoat 符号链接
    if [[ -L /usr/local/bin/saltgoat ]]; then
        sudo rm -f /usr/local/bin/saltgoat
        log_success "已移除 /usr/local/bin/saltgoat"
    else
        log_warning "/usr/local/bin/saltgoat 不存在或不是符号链接"
    fi
    
    # 移除管理脚本符号链接
    for script in manage-mysql manage-nginx manage-rabbitmq; do
        if [[ -L /usr/local/bin/$script ]]; then
            sudo rm -f /usr/local/bin/$script
            log_success "已移除 /usr/local/bin/$script"
        else
            log_warning "/usr/local/bin/$script 不存在或不是符号链接"
        fi
    done
}

# 移除 sudo 配置
remove_sudo_config() {
    log_info "正在移除 sudo 配置..."
    
    if [[ -f /etc/sudoers.d/saltgoat ]]; then
        sudo rm -f /etc/sudoers.d/saltgoat
        log_success "已移除 sudo 配置文件"
    else
        log_warning "sudo 配置文件不存在"
    fi
}

# 移除用户别名
remove_aliases() {
    log_info "正在移除用户别名..."
    
    # 备份原始文件
    cp ~/.bashrc ~/.bashrc.backup.$(date +%Y%m%d_%H%M%S)
    
    # 移除 SaltGoat 相关别名
    sed -i '/# SaltGoat 别名/,/^$/d' ~/.bashrc
    
    log_success "已移除用户别名"
}

# 显示卸载完成信息
show_completion() {
    echo
    log_success "SaltGoat 卸载完成！"
    echo
    echo "已移除的内容："
    echo "  - 系统符号链接"
    echo "  - sudo 权限配置"
    echo "  - 用户别名"
    echo
    echo "注意："
    echo "  - 原始 SaltGoat 文件仍然保留在 $PWD"
    echo "  - 如需完全移除，请手动删除整个目录"
    echo "  - 建议重新加载 shell 环境：source ~/.bashrc"
    echo
}

# 主函数
main() {
    echo "SaltGoat 系统卸载脚本"
    echo "======================"
    echo
    
    check_root
    remove_symlinks
    remove_sudo_config
    remove_aliases
    show_completion
}

# 运行主函数
main "$@"

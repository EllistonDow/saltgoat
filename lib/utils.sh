#!/bin/bash
# SaltGoat 工具函数库
# lib/utils.sh

# 检查权限（系统安装后无需 sudo）
check_permissions() {
    # 调试信息
    # echo "DEBUG: check_permissions called with args: $*" >&2
    # echo "DEBUG: First arg: '$1', Second arg: '$2'" >&2
    # echo "DEBUG: Files exist: /usr/local/bin/saltgoat=$([[ -f /usr/local/bin/saltgoat ]] && echo yes || echo no)" >&2
    # echo "DEBUG: Files exist: /etc/sudoers.d/saltgoat=$([[ -f /etc/sudoers.d/saltgoat ]] && echo yes || echo no)" >&2
    
    # 如果是 system install/uninstall/ssh-port 命令，跳过权限检查
    if [[ "$1" == "system" && ("$2" == "install" || "$2" == "uninstall" || "$2" == "ssh-port") ]]; then
        return 0
    fi
    
    # 如果是 help 命令，跳过权限检查
    if [[ "$1" == "help" || "$1" == "--help" || "$1" == "-h" || -z "$1" ]]; then
        return 0
    fi
    
    # 如果是系统安装的 saltgoat，且配置了 sudoers，则不需要检查 root
    if [[ -f "/usr/local/bin/saltgoat" ]] && sudo test -f "/etc/sudoers.d/saltgoat" 2>/dev/null; then
        # 检查当前用户是否在 sudoers 配置中（使用 sudo 读取）
        if sudo grep -q "^$(whoami) " /etc/sudoers.d/saltgoat 2>/dev/null; then
            return 0
        fi
    fi
    
    # 检查是否为 root 用户
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        log_info "请使用: sudo $0 $*"
        exit 1
    fi
}

# 设置 Pillar 值
set_pillar() {
    local key="$1"
    local value="$2"
    
    salt-call --local pillar.set "lemp:$key" "$value"
}

# 获取脚本目录
get_script_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查文件是否存在
file_exists() {
    [[ -f "$1" ]]
}

# 检查目录是否存在
dir_exists() {
    [[ -d "$1" ]]
}

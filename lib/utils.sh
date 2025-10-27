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
        if command -v sudo >/dev/null 2>&1; then
            if [[ -z "${SALTGOAT_AUTO_REEXEC:-}" ]]; then
                export SALTGOAT_AUTO_REEXEC=1
                log_warning "检测到需要提升权限，正在自动使用 sudo 重新执行..."
                sudo -E "$0" "$@"
                local status=$?
                if [[ $status -ne 0 ]]; then
                    log_error "自动使用 sudo 执行失败，退出码: $status"
                    log_info "请检查 sudo 配置或直接以 root 身份运行: sudo $0 $*"
                fi
                exit $status
            fi
        fi
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
    local dir
    dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    printf '%s\n' "$dir"
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

# 获取 saltgoat 核心 pillar 文件路径
get_local_pillar_file() {
    local base_dir="${SCRIPT_DIR:-$(pwd)}"
    echo "${base_dir}/salt/pillar/saltgoat.sls"
}

# 从本地 pillar 文件读取配置值（若不存在返回空字符串或默认值）
get_local_pillar_value() {
    local key="$1"
    local default_value="${2:-}"
    local pillar_file
    pillar_file="$(get_local_pillar_file)"

    if sudo test -f "$pillar_file" 2>/dev/null; then
        local value
        value=$(sudo python3 - "$pillar_file" "$key" <<'PY'
import sys, yaml, pathlib
file = pathlib.Path(sys.argv[1])
lookup = sys.argv[2].split(".")
try:
    data = yaml.safe_load(file.read_text()) or {}
except Exception:
    data = {}
cur = data
for part in lookup:
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        cur = ""
        break
if isinstance(cur, (dict, list)):
    cur = ""
print("" if cur is None else cur)
PY
        )
        if [[ -n "$value" ]]; then
            echo "$value"
            return 0
        fi
    fi

    if [[ -n "$default_value" ]]; then
        echo "$default_value"
    fi
    return 1
}

# 将值写入本地 pillar 文件（简单 key:value）
set_local_pillar_value() {
    local key="$1"
    local value="$2"
    local pillar_file
    pillar_file="$(get_local_pillar_file)"

    sudo mkdir -p "$(dirname "$pillar_file")"

    local escaped
    escaped="${value//\'/\'\'}"

    if sudo test -f "$pillar_file" && sudo grep -q "^${key}:" "$pillar_file"; then
        sudo sed -i "s|^${key}:.*|${key}: '${escaped}'|" "$pillar_file"
    else
        if ! sudo test -f "$pillar_file"; then
            sudo touch "$pillar_file"
            sudo chmod 600 "$pillar_file"
        fi
        printf "%s\n" "${key}: '${escaped}'" | sudo tee -a "$pillar_file" >/dev/null
    fi
}

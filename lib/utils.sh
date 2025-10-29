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

# 获取 secrets Pillar 目录
get_secret_pillar_dir() {
    local base_dir="${SCRIPT_DIR:-$(pwd)}"
    echo "${base_dir}/salt/pillar/secret"
}

get_secret_auto_file() {
    local dir
    dir="$(get_secret_pillar_dir)"
    echo "${dir}/auto.sls"
}

# 读取 secret Pillar 的值（支持使用点分路径）
get_local_secret_value() {
    local key="$1"
    local secret_dir
    secret_dir="$(get_secret_pillar_dir)"

    if ! sudo test -d "$secret_dir" 2>/dev/null; then
        return 1
    fi

    local value
    value=$(sudo python3 - "$secret_dir" "$key" <<'PY'
import sys, yaml, pathlib

secret_dir = pathlib.Path(sys.argv[1])
lookup = ['secrets'] + sys.argv[2].split('.')

def deep_merge(base, new):
    for key, val in new.items():
        if isinstance(val, dict) and isinstance(base.get(key), dict):
            deep_merge(base[key], val)
        else:
            base[key] = val
    return base

data = {}
for sls_file in sorted(secret_dir.glob('*.sls')):
    try:
        chunk = yaml.safe_load(sls_file.read_text()) or {}
    except Exception:
        continue
    if isinstance(chunk, dict):
        deep_merge(data, chunk)

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

    return 1
}

# 从本地 pillar/secret 读取配置值（若不存在则回退到公共 Pillar 文件）
get_local_pillar_value() {
    local key="$1"
    local default_value="${2:-}"

    local secret_value
    if secret_value=$(get_local_secret_value "$key" 2>/dev/null); then
        echo "$secret_value"
        return 0
    fi

    local pillar_file
    pillar_file="$(get_local_pillar_file)"

    if sudo test -f "$pillar_file" 2>/dev/null; then
        local value
        value=$(sudo python3 - "$pillar_file" "$key" <<'PY'
import sys, yaml, pathlib
file = pathlib.Path(sys.argv[1])
lookup = sys.argv[2].split('.')
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
        if [[ -n "$value" && "$value" != "{{"* ]]; then
            echo "$value"
            return 0
        fi
    fi

    if [[ -n "$default_value" ]]; then
        echo "$default_value"
    fi
    return 1
}

# 将值写入 secret Pillar（敏感字段）
set_local_pillar_value() {
    local key="$1"
    local value="$2"
    local secret_file
    secret_file="$(get_secret_auto_file)"

    sudo mkdir -p "$(dirname "$secret_file")"

    sudo python3 - "$secret_file" "$key" "$value" <<'PY'
import sys, yaml, pathlib

path = pathlib.Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]
parts = ['secrets'] + key.split('.')

if path.exists():
    try:
        data = yaml.safe_load(path.read_text()) or {}
    except Exception:
        data = {}
else:
    data = {}

cur = data
for part in parts[:-1]:
    cur = cur.setdefault(part, {})
cur[parts[-1]] = value

with path.open('w') as fh:
    yaml.dump(data, fh, allow_unicode=True, sort_keys=False)
PY

    sudo chmod 600 "$secret_file" >/dev/null 2>&1 || true
}

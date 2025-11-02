#!/bin/bash
# Restic 备份助手

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../lib/logger.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"
# shellcheck source=../../lib/utils.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/utils.sh"

RESTIC_BASE_DIR="/etc/restic"
RESTIC_ENV="${RESTIC_BASE_DIR}/restic.env"
RESTIC_INCLUDE_FILE="${RESTIC_BASE_DIR}/include.txt"
RESTIC_EXCLUDE_FILE="${RESTIC_BASE_DIR}/exclude.txt"
RESTIC_SERVICE="saltgoat-restic-backup.service"
RESTIC_TIMER="saltgoat-restic-backup.timer"
RESTIC_LOG_DIR="/var/log/restic"
RESTIC_CACHE_DIR="/var/cache/restic"
HOST_ID="$(hostname -f 2>/dev/null || hostname)"
SITE_NAME=""
SITE_TOKEN=""
SITE_SECRET_REPO=""
SITE_SECRET_SERVICE_USER=""
SITE_SECRET_REPO_OWNER=""
SITE_SECRET_PATHS=()
SITE_SECRET_TAGS=()

declare -a RUN_PATHS=()
declare -A RUN_PATHS_SEEN=()
declare -a RUN_TAGS=()
RUN_SITE=""
RUN_REPO=""
RUN_PASSWORD=""
RUN_PASSWORD_FILE=""
RUN_RESTIC_BIN=""
RESTIC_PASSWORD=""

declare -a INSTALL_PATHS=()
declare -a INSTALL_TAGS=()
INSTALL_SITE=""
INSTALL_REPO=""
INSTALL_TIMER="daily"
INSTALL_RANDOM_DELAY="15m"
INSTALL_SERVICE_USER=""
INSTALL_REPO_OWNER=""
SITE_METADATA_DIR="/etc/restic/sites.d"

sanitize_site_token() {
    local raw="$1"
    echo "$raw" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

select_site() {
    local site="$1"
    if [[ -z "$site" ]]; then
        log_error "请使用 --site 指定站点"
        exit 1
    fi
    SITE_NAME="$site"
    SITE_TOKEN="$(sanitize_site_token "$site")"
    if [[ -z "$SITE_TOKEN" ]]; then
        log_error "站点名称无效: $site"
        exit 1
    fi
    RESTIC_ENV="${RESTIC_BASE_DIR}/${SITE_TOKEN}.env"
    RESTIC_INCLUDE_FILE="${RESTIC_BASE_DIR}/${SITE_TOKEN}.include"
    RESTIC_EXCLUDE_FILE="${RESTIC_BASE_DIR}/${SITE_TOKEN}.exclude"
    RESTIC_SERVICE="saltgoat-restic-${SITE_TOKEN}.service"
    RESTIC_TIMER="saltgoat-restic-${SITE_TOKEN}.timer"
    RESTIC_LOG_DIR="/var/log/restic/${SITE_TOKEN}"
    RESTIC_CACHE_DIR="/var/cache/restic/${SITE_TOKEN}"
    load_site_defaults
}

load_site_defaults() {
    SITE_SECRET_REPO=""
    SITE_SECRET_SERVICE_USER=""
    SITE_SECRET_REPO_OWNER=""
    SITE_SECRET_PATHS=()
    SITE_SECRET_TAGS=()

    local secret_dir
    secret_dir="$(get_secret_pillar_dir)"
    if ! sudo test -d "$secret_dir" 2>/dev/null; then
        return
    fi

    local output
    output="$(sudo python3 - "$secret_dir" "$SITE_TOKEN" <<'PY'
import sys, yaml, pathlib, json, base64

secret_dir = pathlib.Path(sys.argv[1])
site = sys.argv[2]

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

site_cfg = (
    data.get('secrets', {})
        .get('restic_sites', {})
        .get(site)
)

if not isinstance(site_cfg, dict):
    raise SystemExit(0)

for key, value in site_cfg.items():
    if isinstance(value, (list, dict)):
        encoded = base64.b64encode(json.dumps(value).encode()).decode()
        print(f"{key}__b64={encoded}")
    else:
        print(f"{key}={value}")
PY
)" || return

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        case "$line" in
            repo=*)
                SITE_SECRET_REPO="${line#repo=}"
                ;;
            service_user=*)
                SITE_SECRET_SERVICE_USER="${line#service_user=}"
                ;;
            repo_owner=*)
                SITE_SECRET_REPO_OWNER="${line#repo_owner=}"
                ;;
            paths__b64=*)
                local encoded="${line#paths__b64=}"
                mapfile -t SITE_SECRET_PATHS < <(python3 - "$encoded" <<'PY'
import sys, json, base64
encoded = sys.argv[1]
if not encoded:
    raise SystemExit(0)
try:
    data = json.loads(base64.b64decode(encoded).decode())
except Exception:
    raise SystemExit(0)
if isinstance(data, (list, tuple)):
    for item in data:
        print(item)
elif isinstance(data, str):
    print(data)
PY
)
                ;;
            tags__b64=*)
                local encoded="${line#tags__b64=}"
                mapfile -t SITE_SECRET_TAGS < <(python3 - "$encoded" <<'PY'
import sys, json, base64
encoded = sys.argv[1]
if not encoded:
    raise SystemExit(0)
try:
    data = json.loads(base64.b64decode(encoded).decode())
except Exception:
    raise SystemExit(0)
if isinstance(data, (list, tuple)):
    for item in data:
        print(item)
elif isinstance(data, str):
    print(data)
PY
)
                ;;
        esac
    done <<<"$output"
}

emit_salt_event() {
    local tag="$1"
    shift || true

    if ! command -v python3 >/dev/null 2>&1; then
        return 0
    fi

    python3 - "$tag" "$@" <<'PY'
import sys
try:
    from salt.client import Caller
except Exception:
    sys.exit(0)

tag = sys.argv[1]
data = {}
for arg in sys.argv[2:]:
    if '=' not in arg:
        continue
    key, value = arg.split('=', 1)
    data[key] = value

try:
    caller = Caller()
except Exception:
    sys.exit(0)

try:
    caller.cmd('event.send', tag, data)
except Exception:
    pass
PY
}

send_direct_notification() {
    local status="$1"
    local repo="$2"
    local site="$3"
    local log_file="$4"
    local paths="$5"
    local tags="$6"
    local rc="$7"
    local origin="$8"
    local host="$9"
    local config="/etc/saltgoat/telegram.json"
    local logger="/opt/saltgoat-reactor/logger.py"
    local helpers="/opt/saltgoat-reactor/reactor_common.py"
    local log_path="/var/log/saltgoat/alerts.log"

    [[ -f "$config" ]] || return 0
    [[ -f "$logger" ]] || return 0
    [[ -f "$helpers" ]] || helpers=""

    python3 - "$status" "$repo" "$site" "$log_file" "$paths" "$tags" "$rc" "$origin" "$host" "$config" "$logger" "$log_path" <<'PY'
import json
import pathlib
import subprocess
import sys
from typing import Dict, Any

status, repo, site, log_file, paths, tags, rc, origin, host_hint, config_path, logger_path, log_path = sys.argv[1:]

rc = int(rc or 0)
paths_list = [item for item in (paths or "").split(",") if item]
tags_list = [item for item in (tags or "").split(",") if item]

helpers = pathlib.Path("/opt/saltgoat-reactor/reactor_common.py")
if not helpers.exists():
    sys.exit(0)

sys.path.insert(0, str(helpers.parent))
import reactor_common  # pylint: disable=import-error

payload: Dict[str, Any] = {
    "host": host_hint or "",
    "repo": repo or "n/a",
    "site": site or "",
    "log_file": log_file or "n/a",
    "paths": ", ".join(paths_list),
    "tags": ", ".join(tags_list),
    "return_code": rc,
    "origin": origin or "manual",
}

payload["telegram_thread"] = 5

if not site:
    payload.pop("site")
if not payload["paths"]:
    payload.pop("paths")
if not payload["tags"]:
    payload.pop("tags")

level = "INFO" if status == "success" else "ERROR"
lines = [
    f"[{level}] Restic Backup",
    f"[host]: {payload.get('host') or 'ns510140'}",
    f"[status]: {status.upper()}",
    f"[repo]: {repo or 'n/a'}",
    f"[return_code]: {rc}",
]
if site:
    lines.append(f"[site]: {site}")
if log_file:
    lines.append(f"[log]: {log_file}")
if payload.get("paths"):
    lines.append(f"[paths]: {payload['paths']}")
if payload.get("tags"):
    lines.append(f"[tags]: {payload['tags']}")
message = "\n".join(lines)

tag_base = f"saltgoat/backup/restic/{status}"
payload["tag"] = tag_base

def log(label, data):
    subprocess.run(
        [
            "python3",
            logger_path,
            "TELEGRAM",
            log_path,
            f"{tag_base} {label}",
            json.dumps(data, ensure_ascii=False),
        ],
        check=False,
        timeout=5,
    )

profiles = reactor_common.load_telegram_profiles(config_path, log)
if not profiles:
    log("skip", {"reason": "no_profiles"})
    sys.exit(0)

try:
    log("profile_summary", {"count": len(profiles)})
    reactor_common.broadcast_telegram(message, profiles, log, tag=tag_base, thread_id=payload.get("telegram_thread"))
except Exception as exc:  # pylint: disable=broad-except
    log("error", {"message": str(exc)})
    sys.exit(1)
PY
}

usage() {
    cat <<EOF
用法:
  saltgoat magetools backup restic install --site <name> [选项]   # 为单个站点创建 Restic 定时任务
  saltgoat magetools backup restic run [--site <name>] [选项]      # 立即执行一次备份
  saltgoat magetools backup restic status [--site <name>]         # 查看站点或全部的备份状态
  saltgoat magetools backup restic logs --site <name> [--lines N] # 查看指定站点的 systemd 日志
  saltgoat magetools backup restic snapshots --site <name>        # 列出站点快照
  saltgoat magetools backup restic check --site <name>            # restic check（指定站点）
  saltgoat magetools backup restic forget --site <name> [args]    # 针对站点执行 restic forget
  saltgoat magetools backup restic exec --site <name> <cmd...>    # 直接调用 restic 子命令
  saltgoat magetools backup restic summary                        # 查看当前所有站点的概览

install 选项:
  --site <name>              站点名称（必填）
  --repo <path>              Restic 仓库目录，默认 ~/Dropbox/<site>/restic-backups 或 /var/backups/restic/<site>
  --paths "p1,p2"            追加备份路径，可多次传入（默认 /var/www/<site>）
  --tag <name>               附加 tag，可多次指定（默认包含 <site> 与 magento）
  --service-user <user>      执行备份的系统用户（默认 root）
  --repo-owner <user>        备份完成后为仓库赋权的用户（默认自动推断）
  --timer <cron>             systemd OnCalendar 表达式（默认 daily）
  --random-delay <dur>       systemd RandomizedDelaySec（默认 15m）

run 额外选项（覆盖配置文件，执行一次手动备份）:
  --site <name>              使用对应站点的配置；若未安装，可配合 --repo/--paths 使用
  --site-path <path>         追加站点目录，可多次传入
  --paths "p1,p2"            指定任意路径集合，逗号或空格分隔
  --backup-dir <repo>        临时指定 Restic 仓库
  --repo <repo>              同 --backup-dir
  --tag <name>               为本次快照追加 tag，可多次传入
  --password <value>         临时提供仓库密码
  --password-file <path>     使用密码文件（优先于 --password）
  --restic-bin <path|name>   指定 Restic 可执行文件
EOF
}

require_env() {
    if sudo test -f "$RESTIC_ENV"; then
        return
    fi
    if [[ -f "$RESTIC_ENV" ]]; then
        return
    fi
    log_error "未找到 Restic 环境文件: $RESTIC_ENV"
    log_info "请先运行 'saltgoat magetools backup restic install' 并在 Pillar 中配置 backup.restic"
    exit 1
}

run_restic_cli() {
    require_env
    local cmd="$1"
    shift || true
    sudo /bin/bash -c '
        set -euo pipefail
        ENV_FILE="$1"
        shift
        set -a
        # shellcheck disable=SC1090
        source "$ENV_FILE"
        set +a
        RESTIC_BIN="${RESTIC_BIN:-/usr/bin/restic}"
        exec "$RESTIC_BIN" "$@"
    ' bash "$RESTIC_ENV" "$cmd" "$@"
}

quote_for_env() {
    local value="$1"
    local escaped="${value//\\/\\\\}"
    escaped="${escaped//"/\\"}"
    printf '%s' "$escaped"
}

add_run_path() {
    local path="$1"
    [[ -z "$path" ]] && return
    if [[ -z "${RUN_PATHS_SEEN[$path]+x}" ]]; then
        RUN_PATHS+=("$path")
        RUN_PATHS_SEEN["$path"]=1
    fi
}

generate_random_secret() {
    python3 - <<'PY'
import secrets, string
alphabet = string.ascii_letters + string.digits + "!@#$%^&*()-_=+"
print(''.join(secrets.choice(alphabet) for _ in range(24)))
PY
}

normalize_path() {
    local raw="$1"
    if [[ -z "$raw" ]]; then
        echo ""
        return
    fi
    python3 - <<'PY' "$raw"
import os, sys
print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
}

add_install_path() {
    local path="$1"
    [[ -z "$path" ]] && return
    for existing in "${INSTALL_PATHS[@]}"; do
        [[ "$existing" == "$path" ]] && return
    done
    INSTALL_PATHS+=("$path")
}

add_install_tag() {
    local tag="$1"
    [[ -z "$tag" ]] && return
    INSTALL_TAGS+=("$tag")
}

parse_run_overrides() {
    local arg
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --site)
                RUN_SITE="${2:-}"
                [[ -z "$RUN_SITE" ]] && { log_error "--site 需要一个站点名称"; exit 1; }
                shift 2 ;;
            --site-path)
                arg="${2:-}"
                [[ -z "$arg" ]] && { log_error "--site-path 需要一个路径"; exit 1; }
                add_run_path "$arg"
                shift 2 ;;
            --paths)
                arg="${2:-}"
                [[ -z "$arg" ]] && { log_error "--paths 需要一个列表"; exit 1; }
                arg="${arg//,/ }"
                read -ra _paths <<< "$arg"
                for p in "${_paths[@]}"; do
                    [[ -z "$p" ]] && continue
                    add_run_path "$p"
                done
                shift 2 ;;
            --path)
                arg="${2:-}"
                [[ -z "$arg" ]] && { log_error "--path 需要一个值"; exit 1; }
                add_run_path "$arg"
                shift 2 ;;
            --backup-dir|--repo)
                RUN_REPO="${2:-}"
                [[ -z "$RUN_REPO" ]] && { log_error "--backup-dir 需要一个路径"; exit 1; }
                shift 2 ;;
            --tag)
                arg="${2:-}"
                [[ -z "$arg" ]] && { log_error "--tag 需要一个值"; exit 1; }
                RUN_TAGS+=("$arg")
                shift 2 ;;
            --password)
                RUN_PASSWORD="${2:-}"
                [[ -z "$RUN_PASSWORD" ]] && { log_error "--password 需要一个值"; exit 1; }
                shift 2 ;;
            --password-file)
                arg="${2:-}"
                [[ -z "$arg" ]] && { log_error "--password-file 需要一个路径"; exit 1; }
                if [[ ! -f "$arg" ]]; then
                    log_error "密码文件不存在: $arg"
                    exit 1
                fi
                RUN_PASSWORD_FILE="$(readlink -f "$arg" 2>/dev/null || echo "$arg")"
                shift 2 ;;
            --restic-bin)
                RUN_RESTIC_BIN="${2:-}"
                [[ -z "$RUN_RESTIC_BIN" ]] && { log_error "--restic-bin 需要一个值"; exit 1; }
                shift 2 ;;
            --help|-h)
                usage; exit 0 ;;
            --)
                shift; break ;;
            *)
                log_error "未知参数: $1"
                usage
                exit 1 ;;
        esac
    done
}

parse_install_args() {
    local arg
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --site)
                INSTALL_SITE="${2:-}"
                [[ -z "$INSTALL_SITE" ]] && { log_error "--site 需要一个站点名称"; exit 1; }
                shift 2 ;;
            --repo|--backup-dir)
                INSTALL_REPO="${2:-}"
                [[ -z "$INSTALL_REPO" ]] && { log_error "--repo 需要一个值"; exit 1; }
                shift 2 ;;
            --paths)
                arg="${2:-}"
                [[ -z "$arg" ]] && { log_error "--paths 需要一个列表"; exit 1; }
                arg="${arg//,/ }"
                read -ra _install_paths <<< "$arg"
                for p in "${_install_paths[@]}"; do
                    [[ -z "$p" ]] && continue
                    add_install_path "$(normalize_path "$p")"
                done
                shift 2 ;;
            --path)
                arg="${2:-}"
                [[ -z "$arg" ]] && { log_error "--path 需要一个值"; exit 1; }
                add_install_path "$(normalize_path "$arg")"
                shift 2 ;;
        --tag)
            arg="${2:-}"
            [[ -z "$arg" ]] && { log_error "--tag 需要一个值"; exit 1; }
            add_install_tag "$arg"
            shift 2 ;;
        --repo-owner)
            INSTALL_REPO_OWNER="${2:-}"
            [[ -z "$INSTALL_REPO_OWNER" ]] && { log_error "--repo-owner 需要一个用户名"; exit 1; }
            shift 2 ;;
        --service-user)
            INSTALL_SERVICE_USER="${2:-}"
            [[ -z "$INSTALL_SERVICE_USER" ]] && { log_error "--service-user 需要一个用户名"; exit 1; }
            shift 2 ;;
            --timer)
                INSTALL_TIMER="${2:-daily}"
                shift 2 ;;
            --random-delay)
                INSTALL_RANDOM_DELAY="${2:-15m}"
                shift 2 ;;
            --help|-h)
                usage; exit 0 ;;
            --)
                shift; break ;;
            *)
                log_error "未知参数: $1"
                usage
                exit 1 ;;
        esac
    done
}

ensure_install_defaults() {
    if (( ${#INSTALL_PATHS[@]} == 0 )); then
        if (( ${#SITE_SECRET_PATHS[@]} )); then
            for path in "${SITE_SECRET_PATHS[@]}"; do
                [[ -z "$path" ]] && continue
                add_install_path "$(normalize_path "$path")"
            done
        else
            add_install_path "/var/www/${INSTALL_SITE}"
        fi
    fi
    if [[ -z "$INSTALL_REPO" ]]; then
        if [[ -n "$SITE_SECRET_REPO" ]]; then
            INSTALL_REPO="$SITE_SECRET_REPO"
        elif [[ -d "$HOME/Dropbox" ]]; then
            INSTALL_REPO="$HOME/Dropbox/${INSTALL_SITE}/restic-backups"
        else
            INSTALL_REPO="/var/backups/restic/${INSTALL_SITE}"
        fi
    fi
    INSTALL_REPO="$(normalize_path "$INSTALL_REPO")"
    if [[ -z "$INSTALL_SERVICE_USER" ]]; then
        if [[ -n "$SITE_SECRET_SERVICE_USER" ]]; then
            INSTALL_SERVICE_USER="$SITE_SECRET_SERVICE_USER"
        else
            INSTALL_SERVICE_USER="root"
        fi
    fi
    if [[ -z "$INSTALL_REPO_OWNER" ]]; then
        if [[ -n "$SITE_SECRET_REPO_OWNER" ]]; then
            INSTALL_REPO_OWNER="$SITE_SECRET_REPO_OWNER"
        elif [[ "$INSTALL_REPO" =~ ^/home/([^/]+)/ ]]; then
            INSTALL_REPO_OWNER="${BASH_REMATCH[1]}"
        else
            INSTALL_REPO_OWNER="$INSTALL_SERVICE_USER"
        fi
    fi
    if (( ${#INSTALL_TAGS[@]} == 0 )); then
        if (( ${#SITE_SECRET_TAGS[@]} )); then
            for tag in "${SITE_SECRET_TAGS[@]}"; do
                add_install_tag "$tag"
            done
        else
            [[ -n "$INSTALL_SITE" ]] && add_install_tag "$INSTALL_SITE"
            add_install_tag "magento"
        fi
    fi
}

ensure_site_password() {
    local key="secrets.restic_sites.${SITE_TOKEN}.password"
    local password
    password="$(get_local_pillar_value "$key" "" 2>/dev/null || true)"
    if [[ -z "$password" ]]; then
        password="$(generate_random_secret)"
        set_local_pillar_value "$key" "$password"
        log_info "已为站点 ${SITE_NAME} 写入 Restic 密码 (secrets.restic_sites.${SITE_TOKEN}.password)"
    fi
    RESTIC_PASSWORD="$password"
}

ensure_restic_package_installed() {
    if ! dpkg -s restic >/dev/null 2>&1; then
        log_info "安装 restic 软件包 ..."
        if ! sudo apt-get install -y restic >/dev/null 2>&1; then
            sudo apt-get update
            sudo apt-get install -y restic
        fi
    fi
}

ensure_dir_ownerships() {
    local owner="$1"
    shift
    [[ -z "$owner" ]] && return
    for dir in "$@"; do
        [[ -d "$dir" ]] || continue
        sudo chown -R "$owner":"$owner" "$dir"
    done
}

create_include_file() {
    sudo mkdir -p "$RESTIC_BASE_DIR"
    sudo bash -c "printf '' > '$RESTIC_INCLUDE_FILE'"
    for path in "${INSTALL_PATHS[@]}"; do
        sudo bash -c "printf '%s\\n' '$path' >> '$RESTIC_INCLUDE_FILE'"
    done
    sudo chown "$INSTALL_SERVICE_USER":"$INSTALL_SERVICE_USER" "$RESTIC_INCLUDE_FILE"
    sudo chmod 600 "$RESTIC_INCLUDE_FILE"
}

create_exclude_file() {
    sudo mkdir -p "$RESTIC_BASE_DIR"
    sudo bash -c "printf '*.log\\nvar/cache\\nvar/page_cache\\ngenerated/code\\ngenerated/metadata\\n' > '$RESTIC_EXCLUDE_FILE'"
    sudo chown "$INSTALL_SERVICE_USER":"$INSTALL_SERVICE_USER" "$RESTIC_EXCLUDE_FILE"
    sudo chmod 600 "$RESTIC_EXCLUDE_FILE"
}

create_env_file() {
    sudo mkdir -p "$RESTIC_BASE_DIR"
    sudo mkdir -p "$RESTIC_LOG_DIR" "$RESTIC_CACHE_DIR"
    sudo chown "$INSTALL_SERVICE_USER":"$INSTALL_SERVICE_USER" "$RESTIC_LOG_DIR" "$RESTIC_CACHE_DIR"
    sudo chmod 750 "$RESTIC_LOG_DIR" "$RESTIC_CACHE_DIR"
    local tags_csv
    tags_csv="$(IFS=','; echo "${INSTALL_TAGS[*]}")"
    sudo bash -c "cat > '$RESTIC_ENV' <<EOF
RESTIC_REPOSITORY='$(quote_for_env "$INSTALL_REPO")'
RESTIC_PASSWORD='$(quote_for_env "$RESTIC_PASSWORD")'
RESTIC_CACHE_DIR='$RESTIC_CACHE_DIR'
RESTIC_LOG_DIR='$RESTIC_LOG_DIR'
RESTIC_INCLUDE_FILE='$RESTIC_INCLUDE_FILE'
RESTIC_EXCLUDE_FILE='$RESTIC_EXCLUDE_FILE'
RESTIC_TAGS='$tags_csv'
RESTIC_BACKUP_ARGS='--one-file-system'
RESTIC_CHECK_AFTER_BACKUP='1'
RESTIC_FORGET_ARGS='--keep-last 7 --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune'
RESTIC_REPO_OWNER='$(quote_for_env "$INSTALL_REPO_OWNER")'
RESTIC_SITE='$(quote_for_env "$SITE_NAME")'
EOF"
    sudo chown "$INSTALL_SERVICE_USER":"$INSTALL_SERVICE_USER" "$RESTIC_ENV"
    sudo chmod 600 "$RESTIC_ENV"
}

ensure_repo_initialized() {
    local restic_bin
    restic_bin="$(command -v restic || echo "/usr/bin/restic")"
    if [[ ! -x "$restic_bin" ]]; then
        log_error "未找到 restic 可执行文件，无法初始化仓库。"
        return 1
    fi

    if sudo -u "$INSTALL_SERVICE_USER" RESTIC_ENV_FILE="$RESTIC_ENV" RESTIC_BIN_PATH="$restic_bin" /bin/bash <<'EOF'
set -euo pipefail
set -a
source "$RESTIC_ENV_FILE"
set +a
if [[ -z "${RESTIC_REPOSITORY:-}" ]]; then
    exit 0
fi
if "$RESTIC_BIN_PATH" cat config >/dev/null 2>&1; then
    exit 0
fi
exit 1
EOF
    then
        return 0
    fi

    log_info "初始化 Restic 仓库: ${INSTALL_REPO}"
    sudo -u "$INSTALL_SERVICE_USER" RESTIC_ENV_FILE="$RESTIC_ENV" RESTIC_BIN_PATH="$restic_bin" /bin/bash <<'EOF'
set -euo pipefail
set -a
source "$RESTIC_ENV_FILE"
set +a
"$RESTIC_BIN_PATH" init
EOF
    log_success "Restic 仓库已初始化: ${INSTALL_REPO}"
}

create_systemd_units() {
    local readwrite_paths=("$RESTIC_LOG_DIR" "$RESTIC_CACHE_DIR")
    if [[ "$INSTALL_REPO" == /* ]]; then
        readwrite_paths+=("$INSTALL_REPO")
    fi
    readwrite_paths+=("$RESTIC_BASE_DIR")
    local protect_home="read-only"
    if [[ "$INSTALL_REPO" == /home/* ]]; then
        protect_home="no"
    fi
    local rw_line=""
    if (( ${#readwrite_paths[@]} )); then
        local joined_paths
        joined_paths="$(printf '%s ' "${readwrite_paths[@]}")"
        joined_paths="${joined_paths% }"
        rw_line="ReadWritePaths=${joined_paths}"
    fi
    sudo bash -c "cat > '/etc/systemd/system/$RESTIC_SERVICE' <<EOF
[Unit]
Description=SaltGoat Restic Backup (${SITE_NAME})
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=RESTIC_ENV_FILE=$RESTIC_ENV
User=$INSTALL_SERVICE_USER
Group=$INSTALL_SERVICE_USER
ExecStart=/usr/local/bin/saltgoat-restic-backup
Nice=10
IOSchedulingClass=2
IOSchedulingPriority=7
ProtectSystem=full
ProtectHome=$protect_home
$rw_line
EOF"
    sudo bash -c "cat > '/etc/systemd/system/$RESTIC_TIMER' <<EOF
[Unit]
Description=SaltGoat Restic Backup Timer (${SITE_NAME})

[Timer]
OnCalendar=$INSTALL_TIMER
RandomizedDelaySec=$INSTALL_RANDOM_DELAY
Persistent=true

[Install]
WantedBy=timers.target
EOF"
    sudo systemctl daemon-reload
    sudo systemctl enable "$RESTIC_TIMER" >/dev/null 2>&1
}

write_site_metadata() {
    local site="$SITE_NAME"
    sudo mkdir -p "$SITE_METADATA_DIR"
    local meta_file="$SITE_METADATA_DIR/${SITE_TOKEN}.env"
    local paths_csv tags_csv
    paths_csv="$(IFS=','; echo "${INSTALL_PATHS[*]}")"
    tags_csv="$(IFS=','; echo "${INSTALL_TAGS[*]}")"
    sudo bash -c "cat > '$meta_file' <<EOF
SITE=$site
TOKEN=$SITE_TOKEN
REPO=$INSTALL_REPO
ENV_FILE=$RESTIC_ENV
INCLUDE_FILE=$RESTIC_INCLUDE_FILE
EXCLUDE_FILE=$RESTIC_EXCLUDE_FILE
LOG_DIR=$RESTIC_LOG_DIR
CACHE_DIR=$RESTIC_CACHE_DIR
SERVICE_USER=$INSTALL_SERVICE_USER
REPO_OWNER=$INSTALL_REPO_OWNER
SERVICE_NAME=$RESTIC_SERVICE
TIMER_NAME=$RESTIC_TIMER
TAGS=$tags_csv
PATHS=$paths_csv
UPDATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF"
    sudo chmod 0640 "$meta_file"
}

summarize_sites() {
    if ! sudo test -d "$SITE_METADATA_DIR" >/dev/null 2>&1; then
        log_warning "未找到任何站点记录，可通过 'saltgoat magetools backup restic install --site <name>' 初始化"
        return
    fi
    sudo python3 - <<'PY'
import json, subprocess, datetime
from pathlib import Path

SITE_DIR = Path('/etc/restic/sites.d')
files = sorted(SITE_DIR.glob('*.env'))
if not files:
    print("暂无 Restic 站点记录")
    raise SystemExit(0)

def run_cmd(cmd: str):
    return subprocess.run(["bash", "-lc", cmd], capture_output=True, text=True)

rows = []
for file in files:
    data = {}
    for line in file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        k, v = line.split('=', 1)
        data[k.strip()] = v.strip()

    site = data.get('SITE') or file.stem
    repo = data.get('REPO')
    env_file = data.get('ENV_FILE', '/etc/restic/restic.env')
    service = data.get('SERVICE_NAME', 'saltgoat-restic-backup.service')

    latest_time = 'n/a'
    snapshot_count = '0'
    size_display = 'n/a'
    svc_state = 'unknown'
    svc_status = ''
    last_run = 'n/a'

    if repo:
        snap_cmd = (
            f"set -a; source '{env_file}' >/dev/null 2>&1; set +a; "
            f"export RESTIC_REPOSITORY='{repo}'; "
            f"/usr/bin/restic --json snapshots"
        )
        snap_proc = run_cmd(snap_cmd)
        if snap_proc.returncode == 0 and snap_proc.stdout.strip():
            try:
                snapshots = json.loads(snap_proc.stdout)
                if snapshots:
                    snapshots.sort(key=lambda x: x.get('time', ''))
                    snapshot_count = str(len(snapshots))
                    latest = snapshots[-1].get('time')
                    if latest:
                        try:
                            dt = datetime.datetime.fromisoformat(latest.replace('Z', '+00:00'))
                            latest_time = dt.strftime('%Y-%m-%d %H:%M')
                        except Exception:
                            latest_time = latest
            except json.JSONDecodeError:
                latest_time = '解析失败'
        else:
            latest_time = f"错误({snap_proc.returncode})"

        stats_cmd = (
            f"set -a; source '{env_file}' >/dev/null 2>&1; set +a; "
            f"export RESTIC_REPOSITORY='{repo}'; "
            f"/usr/bin/restic stats --json latest"
        )
        stats_proc = run_cmd(stats_cmd)
        if stats_proc.returncode == 0 and stats_proc.stdout.strip():
            try:
                stats = json.loads(stats_proc.stdout)
                size_bytes = stats.get('total_size', 0)
                if size_bytes >= 1024**3:
                    size_display = f"{size_bytes / (1024**3):.1f}G"
                else:
                    size_display = f"{size_bytes / (1024**2):.1f}M"
            except json.JSONDecodeError:
                size_display = '解析失败'
        elif stats_proc.returncode == 3:
            size_display = '无快照'

    svc_proc = subprocess.run(
        ["systemctl", "show", service, "--property=ActiveState,SubState,ExecMainStatus"],
        capture_output=True, text=True
    )
    if svc_proc.returncode == 0:
        props = {}
        for line in svc_proc.stdout.splitlines():
            if '=' in line:
                k, v = line.split('=', 1)
                props[k] = v
        svc_state = f"{props.get('ActiveState', '?')}/{props.get('SubState', '?')}"
        svc_status = props.get('ExecMainStatus', '')

    journal_proc = subprocess.run(
        ["journalctl", "-u", service, "-n", "1", "--no-pager", "--output=json"],
        capture_output=True, text=True
    )
    if journal_proc.returncode == 0 and journal_proc.stdout.strip():
        try:
            entry = json.loads(journal_proc.stdout.splitlines()[-1])
            ts = int(entry.get('__REALTIME_TIMESTAMP', '0'))
            if ts:
                dt = datetime.datetime.fromtimestamp(ts / 1_000_000)
                last_run = dt.strftime('%Y-%m-%d %H:%M:%S')
        except Exception:
            pass

    rows.append({
        'site': site,
        'repo': repo or 'n/a',
        'snapshots': snapshot_count,
        'latest': latest_time,
        'size': size_display,
        'svc_state': svc_state,
        'svc_status': svc_status,
        'last_run': last_run,
    })

header = f"{'站点':<12} {'快照数':<6} {'最后备份':<17} {'容量':<8} {'服务状态':<20} {'最后执行':<19}"
print(header)
print('-' * len(header))
for row in sorted(rows, key=lambda r: r['site']):
    status = row['svc_state']
    if row['svc_status']:
        status = f"{status}({row['svc_status']})"
    print(f"{row['site']:<12} {row['snapshots']:<6} {row['latest']:<17} {row['size']:<8} {status:<20} {row['last_run']:<19}")
PY
}

run_manual_backup() {
    local tmp_env tmp_include cleanup=()
    local env_exists=0
    local effective_repo="$RUN_REPO"
    if sudo test -f "$RESTIC_ENV"; then
        tmp_env="$(mktemp)"
        cleanup+=("$tmp_env")
        if ! sudo cat "$RESTIC_ENV" | tee "$tmp_env" >/dev/null; then
            log_error "无法读取 Restic 环境文件: $RESTIC_ENV"
            return 1
        fi
        chmod 600 "$tmp_env"
        env_exists=1
    else
        tmp_env="$(mktemp)"
        cleanup+=("$tmp_env")
        env_exists=0
        if [[ -z "$RUN_REPO" ]]; then
            log_error "未找到 Restic 环境文件: $RESTIC_ENV"
            log_error "请提供 --backup-dir/--repo 并配合 --password 或 --password-file，或先运行 'saltgoat magetools backup restic install'"
            return 1
        fi
        local restic_bin="${RUN_RESTIC_BIN:-/usr/bin/restic}"
        if [[ -n "$RUN_PASSWORD_FILE" ]]; then
            if [[ ! -f "$RUN_PASSWORD_FILE" ]]; then
                log_error "密码文件不存在: $RUN_PASSWORD_FILE"
                return 1
            fi
            cat <<EOF >"$tmp_env"
RESTIC_REPOSITORY="$(quote_for_env "$RUN_REPO")"
RESTIC_PASSWORD_FILE="$(quote_for_env "$RUN_PASSWORD_FILE")"
EOF
        elif [[ -n "$RUN_PASSWORD" ]]; then
            cat <<EOF >"$tmp_env"
RESTIC_REPOSITORY="$(quote_for_env "$RUN_REPO")"
RESTIC_PASSWORD="$(quote_for_env "$RUN_PASSWORD")"
EOF
        else
            log_error "未找到 Restic 环境文件，请通过 --password 或 --password-file 提供仓库密码。"
            return 1
        fi
        cat <<EOF >>"$tmp_env"
RESTIC_BIN="$(quote_for_env "$restic_bin")"
RESTIC_CACHE_DIR="/var/cache/restic"
RESTIC_LOG_DIR="/var/log/restic"
EOF
        log_warning "未检测到持久化 Restic 配置，已使用临时参数执行本次备份。"
        RUN_RESTIC_BIN="$restic_bin"
    fi

    if [[ -n "$RUN_REPO" && "$RUN_REPO" == /* ]]; then
        sudo mkdir -p "$RUN_REPO"
    fi

    if [[ -n "$RUN_REPO" && env_exists -eq 1 ]]; then
        printf 'RESTIC_REPOSITORY="%s"\n' "$(quote_for_env "$RUN_REPO")" >> "$tmp_env"
    fi
    if [[ -n "$RUN_PASSWORD_FILE" ]]; then
        printf 'RESTIC_PASSWORD_FILE="%s"\n' "$(quote_for_env "$RUN_PASSWORD_FILE")" >> "$tmp_env"
    elif [[ -n "$RUN_PASSWORD" ]]; then
        printf 'RESTIC_PASSWORD="%s"\n' "$(quote_for_env "$RUN_PASSWORD")" >> "$tmp_env"
    fi
    if [[ -n "$RUN_RESTIC_BIN" ]]; then
        printf 'RESTIC_BIN="%s"\n' "$(quote_for_env "$RUN_RESTIC_BIN")" >> "$tmp_env"
    fi

    if (( ${#RUN_PATHS[@]} )); then
        tmp_include="$(mktemp)"
        cleanup+=("$tmp_include")
        : > "$tmp_include"
        for path in "${RUN_PATHS[@]}"; do
            if [[ ! -e "$path" ]]; then
                log_warning "路径不存在: $path"
            fi
            printf '%s\n' "$path" >> "$tmp_include"
        done
        printf 'RESTIC_INCLUDE_FILE="%s"\n' "$(quote_for_env "$tmp_include")" >> "$tmp_env"
    elif [[ $env_exists -eq 0 ]]; then
        log_error "未检测到备份路径，请至少提供 --site 或 --paths。"
        rm -f "$tmp_env"
        return 1
    fi

    if (( ${#RUN_TAGS[@]} )); then
        local joined
        joined="$(IFS=','; echo "${RUN_TAGS[*]}")"
        printf 'RESTIC_TAGS="%s"\n' "$(quote_for_env "$joined")" >> "$tmp_env"
    fi

    sudo /bin/bash -c '
        set -euo pipefail
        ENV_FILE="$1"
        shift || true
        set -a
        # shellcheck disable=SC1090
        source "$ENV_FILE"
        set +a

        RESTIC_BIN="${RESTIC_BIN:-/usr/bin/restic}"
        if [[ -x "$RESTIC_BIN" ]]; then
            :
        elif command -v "$RESTIC_BIN" >/dev/null 2>&1; then
            RESTIC_BIN="$(command -v "$RESTIC_BIN")"
        elif command -v restic >/dev/null 2>&1; then
            RESTIC_BIN="$(command -v restic)"
        else
            echo "[restic] 未找到 Restic 可执行文件 ($RESTIC_BIN)，请先安装：sudo apt install restic" >&2
            exit 1
        fi

        INCLUDE_FILE="${RESTIC_INCLUDE_FILE:-}"
        EXCLUDE_FILE="${RESTIC_EXCLUDE_FILE:-}"
        LOG_DIR="${RESTIC_LOG_DIR:-/var/log/restic}"
        mkdir -p "$LOG_DIR"
        if [[ -n "${RESTIC_CACHE_DIR:-}" ]]; then
            mkdir -p "$RESTIC_CACHE_DIR"
        fi
        TS="$(date +%Y%m%d_%H%M%S)"
        LOG_FILE="$LOG_DIR/manual-$TS.log"
        exec >> >(tee -a "$LOG_FILE") 2>&1
        echo "[restic] manual backup started at $TS"

        ARGS=(backup)
        if [[ -n "$INCLUDE_FILE" && -s "$INCLUDE_FILE" ]]; then
            ARGS+=(--files-from "$INCLUDE_FILE")
        fi
        if [[ -n "$EXCLUDE_FILE" && -s "$EXCLUDE_FILE" ]]; then
            ARGS+=(--exclude-file "$EXCLUDE_FILE")
        fi
        if [[ -n "${RESTIC_TAGS:-}" ]]; then
            IFS=',' read -ra TAG_ARR <<< "${RESTIC_TAGS}"
            for tag in "${TAG_ARR[@]}"; do
                [[ -z "$tag" ]] && continue
                ARGS+=(--tag "$tag")
            done
        fi
        if [[ -n "${RESTIC_BACKUP_ARGS:-}" ]]; then
            # shellcheck disable=SC2086
            ARGS+=(${RESTIC_BACKUP_ARGS})
        fi

        if [[ ${#ARGS[@]} -eq 1 ]]; then
            echo "[restic] 未指定备份路径，请提供 --site 或 --paths。" >&2
            exit 1
        fi

        "$RESTIC_BIN" "${ARGS[@]}"

        if [[ -n "${RESTIC_FORGET_ARGS:-}" ]]; then
            echo "[restic] applying retention policy: ${RESTIC_FORGET_ARGS}"
            # shellcheck disable=SC2086
            "$RESTIC_BIN" forget ${RESTIC_FORGET_ARGS}
        fi

        if [[ "${RESTIC_CHECK_AFTER_BACKUP:-0}" == "1" ]]; then
            echo "[restic] running restic check ..."
            "$RESTIC_BIN" check --read-data-subset=1/5
        fi

        echo "[restic] manual backup completed at $(date +%Y%m%d_%H%M%S)"
    ' bash "$tmp_env"
    local rc=$?
    if [[ -z "$effective_repo" && -f "$tmp_env" ]]; then
        local repo_line
        repo_line="$(grep -E '^RESTIC_REPOSITORY=' "$tmp_env" | tail -n1 || true)"
        if [[ -n "$repo_line" ]]; then
            effective_repo="${repo_line#*=}"
            effective_repo="${effective_repo%\"}"
            effective_repo="${effective_repo#\"}"
        fi
    fi
    local joined_paths=""
    if (( ${#RUN_PATHS[@]} )); then
        joined_paths="$(IFS=','; echo "${RUN_PATHS[*]}")"
    fi
    local joined_tags=""
    if (( ${#RUN_TAGS[@]} )); then
        joined_tags="$(IFS=','; echo "${RUN_TAGS[*]}")"
    fi
    local event_suffix
    if [[ $rc -eq 0 ]]; then
        event_suffix="success"
    else
        event_suffix="failure"
    fi
    emit_salt_event "saltgoat/backup/restic/${event_suffix}" \
        "id=$HOST_ID" \
        "host=$HOST_ID" \
        "origin=manual" \
        "repo=${effective_repo:-unknown}" \
        "site=${RUN_SITE:-}" \
        "paths=$joined_paths" \
        "tags=$joined_tags" \
        "return_code=$rc"
    send_direct_notification \
        "$event_suffix" \
        "${effective_repo:-unknown}" \
        "${RUN_SITE:-}" \
        "" \
        "$joined_paths" \
        "$joined_tags" \
        "$rc" \
        "manual" \
        "$HOST_ID"
    for f in "${cleanup[@]}"; do
        [[ -n "$f" ]] && rm -f "$f"
    done
    return $rc
}

ACTION="${1:-}"
case "$ACTION" in
    install|apply)
        shift || true
        parse_install_args "$@"
        if [[ -z "$INSTALL_SITE" ]]; then
            log_error "请使用 --site 指定站点"
            exit 1
        fi
        select_site "$INSTALL_SITE"
        ensure_install_defaults
        ensure_restic_package_installed
        ensure_site_password
        if [[ "$INSTALL_REPO" == /* ]]; then
            sudo mkdir -p "$INSTALL_REPO"
            if [[ -n "$INSTALL_REPO_OWNER" ]]; then
                sudo chown -R "$INSTALL_REPO_OWNER":"$INSTALL_REPO_OWNER" "$INSTALL_REPO"
            fi
        fi
        create_include_file
        create_exclude_file
        create_env_file
        ensure_repo_initialized
        create_systemd_units
        write_site_metadata
        sudo systemctl restart "$RESTIC_TIMER" >/dev/null 2>&1 || true
        if sudo systemctl start "$RESTIC_SERVICE" >/dev/null 2>&1; then
            log_success "已触发站点 ${SITE_NAME} 的首次 Restic 备份"
        else
            log_warning "首次备份触发失败，请使用 'saltgoat magetools backup restic run --site ${SITE_NAME}' 检查原因"
        fi
        if [[ "$INSTALL_REPO" == /* && -n "$INSTALL_REPO_OWNER" ]]; then
            sudo chown -R "$INSTALL_REPO_OWNER":"$INSTALL_REPO_OWNER" "$INSTALL_REPO"
        fi
        ;;
    run)
        shift || true
        parse_run_overrides "$@"
        if [[ -n "$RUN_SITE" ]]; then
            select_site "$RUN_SITE"
        fi
        if [[ -n "$RUN_REPO" || -n "$RUN_SITE" || ${#RUN_PATHS[@]} -gt 0 || ${#RUN_TAGS[@]} -gt 0 ]]; then
            log_info "执行一次手动 Restic 备份 ..."
            run_manual_backup
        else
            if [[ -z "$RUN_SITE" ]]; then
                log_error "请使用 --site 指定要触发的站点，或提供 --paths/--repo 进行临时备份"
                exit 1
            fi
            log_info "触发 Restic 备份服务 (${RUN_SITE})..."
            sudo systemctl start "$RESTIC_SERVICE"
        fi
        ;;
    summary|status-all|overview)
        summarize_sites
        ;;
    status)
        shift || true
        SITE_ARG=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --site)
                    SITE_ARG="${2:-}"
                    shift 2 ;;
                --)
                    shift; break ;;
                *)
                    log_error "未知参数: $1"
                    usage
                    exit 1 ;;
            esac
        done
        if [[ -z "$SITE_ARG" ]]; then
            summarize_sites
        else
            select_site "$SITE_ARG"
            sudo systemctl status "$RESTIC_SERVICE" "$RESTIC_TIMER"
        fi
        ;;
    logs)
        shift || true
        SITE_ARG=""
        LINES=100
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --site)
                    SITE_ARG="${2:-}"
                    shift 2 ;;
                --lines)
                    LINES="${2:-100}"
                    shift 2 ;;
                --)
                    shift; break ;;
                *)
                    LINES="$1"
                    shift ;;
            esac
        done
        if [[ -z "$SITE_ARG" ]]; then
            log_error "请使用 --site 指定站点"
            exit 1
        fi
        select_site "$SITE_ARG"
        sudo journalctl -u "$RESTIC_SERVICE" -u "$RESTIC_TIMER" -n "$LINES" --no-pager
        ;;
    snapshots)
        shift || true
        SITE_ARG=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --site)
                    SITE_ARG="${2:-}"
                    shift 2 ;;
                --)
                    shift; break ;;
                *)
                    break ;;
            esac
        done
        if [[ -n "$SITE_ARG" ]]; then
            select_site "$SITE_ARG"
        fi
        run_restic_cli snapshots "$@"
        ;;
    check)
        shift || true
        SITE_ARG=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --site)
                    SITE_ARG="${2:-}"
                    shift 2 ;;
                --)
                    shift; break ;;
                *)
                    break ;;
            esac
        done
        if [[ -n "$SITE_ARG" ]]; then
            select_site "$SITE_ARG"
        fi
        run_restic_cli check "$@"
        ;;
    forget)
        shift || true
        SITE_ARG=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --site)
                    SITE_ARG="${2:-}"
                    shift 2 ;;
                --)
                    shift; break ;;
                *)
                    break ;;
            esac
        done
        if [[ -n "$SITE_ARG" ]]; then
            select_site "$SITE_ARG"
        fi
        if [[ $# -eq 0 ]]; then
            log_info "未传入额外参数，将使用 Pillar 中的保留策略 (--keep-*)"
        fi
        run_restic_cli forget "$@" --prune
        ;;
    exec|run-restic|restic)
        shift || true
        SITE_ARG=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --site)
                    SITE_ARG="${2:-}"
                    shift 2 ;;
                --)
                    shift; break ;;
                *)
                    break ;;
            esac
        done
        if [[ -n "$SITE_ARG" ]]; then
            select_site "$SITE_ARG"
        fi
        if [[ $# -eq 0 ]]; then
            log_error "请在 exec 之后指定 Restic 子命令，例如 'restore latest --target /tmp/restore'"
            exit 1
        fi
        run_restic_cli "$@"
        ;;
    *)
        usage
        exit 1
        ;;
esac

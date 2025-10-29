#!/bin/bash
# Restic 备份助手

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../lib/logger.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"

RESTIC_ENV="/etc/restic/restic.env"
RESTIC_SERVICE="saltgoat-restic-backup.service"
RESTIC_TIMER="saltgoat-restic-backup.timer"
BACKUP_SCRIPT="/usr/local/bin/saltgoat-restic-backup"
HOST_ID="$(hostname -f 2>/dev/null || hostname)"

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
INSTALL_PATHS_DEFAULTED=0
INSTALL_SERVICE_USER=""
INSTALL_REPO_OWNER=""
SITE_METADATA_DIR="/etc/restic/sites.d"

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

usage() {
    cat <<EOF
用法:
  saltgoat magetools backup restic install              # 根据 Pillar 应用 optional.backup-restic
  saltgoat magetools backup restic run [选项]           # 立即执行一次备份（可限制到单站点）
  saltgoat magetools backup restic status               # 查看 systemd service/timer 状态
  saltgoat magetools backup restic logs [lines]         # 查看最近日志 (journalctl)
  saltgoat magetools backup restic snapshots            # 列出 Restic 快照
  saltgoat magetools backup restic check                # restic check
  saltgoat magetools backup restic forget [args]        # 手工执行 restic forget ...
  saltgoat magetools backup restic exec <cmd...>        # 直接调用 restic（如 restore/mount）

run 可选参数（任一出现即不再调用 systemd service，而是执行一次手动备份）:
  --site <name>              仅备份 /var/www/<name>
  --site-path <path>         指定自定义站点路径，可多次传入
  --paths "p1,p2"            追加多个路径，逗号或空格分隔
  --backup-dir <repo>        覆盖 Restic 仓库（如 /home/Dropbox/site1/snapshots）
  --repo <repo>              同 --backup-dir
  --tag <name>               为本次快照追加 tag，可重复
  --password <value>         临时提供 Restic 仓库密码（仅本次使用）
  --password-file <path>     使用密码文件（优先于 --password）
  --restic-bin <path|name>   指定 Restic 可执行文件（默认 /usr/bin/restic 或 PATH 中的 restic）

install 额外选项:
  --site <name>              自动将 /var/www/<name> 作为主要备份路径
  --repo <path>              覆盖 Restic 仓库目录，默认 /var/backups/restic/<site|default>；若检测到 ~/Dropbox 会优先使用
  --paths "p1,p2"            追加任意目录，可多次传入
  --tag <name>               自定义 tag，可多次指定（默认包含站点名和 magento）
  --service-user <user>      运行 restic 的系统用户（默认 root）
  --repo-owner <user>        备份完成后仓库赋权的用户（默认自动推断）
  --timer <cron>             systemd timer 日程（默认 daily，可使用 hourly/weekly 等）
  --random-delay <dur>       systemd RandomizedDelaySec（默认 15m）
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
                add_run_path "/var/www/${RUN_SITE}"
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

detect_default_site() {
    [[ -n "$INSTALL_SITE" ]] && return
    local candidates=()
    if [[ -d /var/www ]]; then
        while IFS= read -r -d '' dir; do
            candidates+=("$(basename "$dir")")
        done < <(find /var/www -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    fi
    if (( ${#candidates[@]} == 1 )); then
        INSTALL_SITE="${candidates[0]}"
    fi
}

ensure_install_defaults() {
    detect_default_site
    if (( ${#INSTALL_PATHS[@]} == 0 )); then
        INSTALL_PATHS_DEFAULTED=1
        if [[ -n "$INSTALL_SITE" ]]; then
            add_install_path "/var/www/${INSTALL_SITE}"
        else
            add_install_path "/var/www"
        fi
    fi
    if [[ -z "$INSTALL_REPO" ]]; then
        if [[ -n "$INSTALL_SITE" && -d "$HOME/Dropbox" ]]; then
            INSTALL_REPO="$HOME/Dropbox/${INSTALL_SITE}/snapshots"
        else
            local suffix="${INSTALL_SITE:-default}"
            INSTALL_REPO="/var/backups/restic/${suffix}"
        fi
    fi
    INSTALL_REPO="$(normalize_path "$INSTALL_REPO")"
    if [[ -z "$INSTALL_SERVICE_USER" ]]; then
        INSTALL_SERVICE_USER="root"
    fi
    if [[ -z "$INSTALL_REPO_OWNER" ]]; then
        if [[ "$INSTALL_REPO" =~ ^/home/([^/]+)/ ]]; then
            INSTALL_REPO_OWNER="${BASH_REMATCH[1]}"
        else
            INSTALL_REPO_OWNER="$INSTALL_SERVICE_USER"
        fi
    fi
    if (( ${#INSTALL_TAGS[@]} == 0 )); then
        [[ -n "$INSTALL_SITE" ]] && add_install_tag "$INSTALL_SITE"
        add_install_tag "magento"
    fi
}

ensure_pillar_top_entry() {
    local top_file="${SCRIPT_DIR}/salt/pillar/top.sls"
    if ! grep -q 'backup-restic' "$top_file" 2>/dev/null; then
        log_info "在 pillar/top.sls 中加入 backup-restic"
        local tmp
        tmp="$(mktemp)"
        awk '
            { print $0 }
            /- salt-beacons/ && !added { print "    - backup-restic"; added=1 }
            END { if (!added) print "    - backup-restic" }
        ' "$top_file" > "$tmp"
        mv "$tmp" "$top_file"
    fi
}

ensure_restic_password_entry() {
    local pillar_file="${SCRIPT_DIR}/salt/pillar/saltgoat.sls"
    RESTIC_PASSWORD="$(python3 - "$pillar_file" <<'PY'
import sys, pathlib, yaml, secrets, string
path = pathlib.Path(sys.argv[1])
if path.exists():
    try:
        data = yaml.safe_load(path.read_text()) or {}
    except Exception:
        data = {}
else:
    data = {}
password = data.get("restic_password")
if not password:
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*()-_=+"
    password = "".join(secrets.choice(alphabet) for _ in range(24))
    data["restic_password"] = password
    path.write_text(yaml.safe_dump(data, sort_keys=False, allow_unicode=True))
print(password)
PY
)"
}

serialize_list() {
    local -n ref=$1
    local result=""
    for item in "${ref[@]}"; do
        [[ -z "$item" ]] && continue
        if [[ -z "$result" ]]; then
            result="$item"
        else
            result+=";$item"
        fi
    done
    echo "$result"
}

write_restic_pillar_file() {
    local pillar_file="${SCRIPT_DIR}/salt/pillar/backup-restic.sls"
    local paths_serial tags_serial
    paths_serial=$(serialize_list INSTALL_PATHS)
    tags_serial=$(serialize_list INSTALL_TAGS)
    INSTALL_PATHS_SERIAL="$paths_serial" \
    INSTALL_TAGS_SERIAL="$tags_serial" \
    INSTALL_REPO_VALUE="$INSTALL_REPO" \
    INSTALL_TIMER_VALUE="$INSTALL_TIMER" \
    INSTALL_RANDOM_DELAY_VALUE="$INSTALL_RANDOM_DELAY" \
    INSTALL_SERVICE_USER_VALUE="$INSTALL_SERVICE_USER" \
    INSTALL_REPO_OWNER_VALUE="$INSTALL_REPO_OWNER" \
    RESTIC_PASSWORD_VALUE="$RESTIC_PASSWORD" \
    python3 - "$pillar_file" <<'PY'
import os, yaml, pathlib, sys
file = pathlib.Path(sys.argv[1])
paths = [p for p in os.environ.get("INSTALL_PATHS_SERIAL","").split(";") if p]
tags = [t for t in os.environ.get("INSTALL_TAGS_SERIAL","").split(";") if t]
config = {
    "enabled": True,
    "repo": os.environ["INSTALL_REPO_VALUE"],
    "password": os.environ["RESTIC_PASSWORD_VALUE"],
    "paths": paths or ["/var/www"],
    "excludes": ["*.log", "var/cache", "var/page_cache", "generated/code", "generated/metadata"],
    "tags": tags,
    "extra_backup_args": "--one-file-system",
    "check_after_backup": True,
    "timer": os.environ["INSTALL_TIMER_VALUE"],
    "randomized_delay": os.environ["INSTALL_RANDOM_DELAY_VALUE"],
    "service_user": os.environ["INSTALL_SERVICE_USER_VALUE"],
    "repo_owner": os.environ["INSTALL_REPO_OWNER_VALUE"],
    "retention": {
        "keep_last": 7,
        "keep_daily": 7,
        "keep_weekly": 4,
        "keep_monthly": 6,
        "prune": True,
    },
}
data = {"backup": {"restic": config}}
file.write_text(yaml.safe_dump(data, sort_keys=False, allow_unicode=True))
PY
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

write_site_metadata() {
    local site="${INSTALL_SITE:-default}"
    sudo mkdir -p "$SITE_METADATA_DIR"
    local meta_file="$SITE_METADATA_DIR/${site}.env"
    sudo bash -c "cat > '$meta_file' <<'EOF'
SITE=$site
REPO=$INSTALL_REPO
ENV_FILE=/etc/restic/restic.env
SERVICE_USER=$INSTALL_SERVICE_USER
REPO_OWNER=$INSTALL_REPO_OWNER
SERVICE_NAME=saltgoat-restic-backup.service
TIMER_NAME=saltgoat-restic-backup.timer
UPDATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
"
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
        if ! sudo cat "$RESTIC_ENV" >"$tmp_env"; then
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
        ensure_install_defaults
        ensure_pillar_top_entry
        ensure_restic_password_entry
        write_restic_pillar_file
        ensure_restic_package_installed
        if [[ -n "$INSTALL_REPO" ]]; then
            sudo mkdir -p "$INSTALL_REPO"
            if [[ -n "$INSTALL_REPO_OWNER" ]]; then
                sudo chown -R "$INSTALL_REPO_OWNER":"$INSTALL_REPO_OWNER" "$INSTALL_REPO"
            fi
        fi
        ensure_dir_ownerships "$INSTALL_SERVICE_USER" /etc/restic /var/cache/restic /var/log/restic
        log_info "刷新 Pillar ..."
        sudo "${SCRIPT_DIR}/saltgoat" pillar refresh >/dev/null 2>&1 || true
        log_info "应用 optional.backup-restic 状态 ..."
        sudo salt-call --local --retcode-passthrough state.apply optional.backup-restic
        log_info "检查 Restic 仓库状态 ..."
        if run_restic_cli snapshots >/dev/null 2>&1; then
            log_info "Restic 仓库已存在，跳过 init"
        else
            log_info "初始化 Restic 仓库（若尚未创建）..."
            if run_restic_cli init >/dev/null 2>&1; then
                log_success "Restic 仓库初始化完成"
            else
                log_warning "自动执行 restic init 失败，请手动运行 'saltgoat magetools backup restic exec init'"
            fi
        fi
        if [[ -x "$BACKUP_SCRIPT" ]]; then
            log_info "执行首次备份 ..."
            if [[ "$INSTALL_SERVICE_USER" == "root" ]]; then
                if sudo "$BACKUP_SCRIPT" >/dev/null 2>&1; then
                    log_success "首次备份完成"
                else
                    log_warning "首次备份执行失败，请手动运行 'saltgoat magetools backup restic run'"
                fi
            else
                if sudo -u "$INSTALL_SERVICE_USER" "$BACKUP_SCRIPT" >/dev/null 2>&1; then
                    log_success "首次备份完成"
                else
                    log_warning "首次备份执行失败，请使用 'sudo -u $INSTALL_SERVICE_USER $BACKUP_SCRIPT' 检查原因"
                fi
            fi
            if [[ -n "$INSTALL_REPO_OWNER" ]]; then
                sudo chown -R "$INSTALL_REPO_OWNER":"$INSTALL_REPO_OWNER" "$INSTALL_REPO"
            fi
        fi
        write_site_metadata
        ;;
    run)
        shift || true
        parse_run_overrides "$@"
        if [[ -n "$RUN_REPO" || -n "$RUN_SITE" || ${#RUN_PATHS[@]} -gt 0 || ${#RUN_TAGS[@]} -gt 0 ]]; then
            log_info "执行一次手动 Restic 备份 ..."
            run_manual_backup
        else
            log_info "触发 Restic 备份服务 ..."
            sudo systemctl start "$RESTIC_SERVICE"
        fi
        ;;
    summary|status-all|overview)
        summarize_sites
        ;;
    status)
        sudo systemctl status "$RESTIC_SERVICE" "$RESTIC_TIMER"
        ;;
    logs)
        shift || true
        LINES="${1:-100}"
        sudo journalctl -u "$RESTIC_SERVICE" -u "$RESTIC_TIMER" -n "$LINES" --no-pager
        ;;
    snapshots)
        shift || true
        run_restic_cli snapshots "$@"
        ;;
    check)
        shift || true
        run_restic_cli check "$@"
        ;;
    forget)
        shift || true
        if [[ $# -eq 0 ]]; then
            log_info "未传入额外参数，将使用 Pillar 中的保留策略 (--keep-*)"
        fi
        run_restic_cli forget "$@" --prune
        ;;
    exec|run-restic|restic)
        shift || true
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

#!/bin/bash
# Percona XtraBackup automation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../lib/logger.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"

MYSQL_ENV="/etc/mysql/mysql-backup.env"
METADATA_DIR="/etc/mysql/backup.d"
SERVICE_NAME="saltgoat-mysql-backup.service"
TIMER_NAME="saltgoat-mysql-backup.timer"
DUMP_DEFAULT_DIR="/var/backups/mysql/dumps"

usage() {
    cat <<'EOF'
用法:
  saltgoat magetools xtrabackup mysql install     # 根据 Pillar 应用 optional.mysql-backup
  saltgoat magetools xtrabackup mysql run         # 立即触发一次数据库备份
  saltgoat magetools xtrabackup mysql status      # 查看 systemd service/timer 状态
  saltgoat magetools xtrabackup mysql logs [N]    # 查看备份日志（默认最近 100 行）
  saltgoat magetools xtrabackup mysql summary     # 汇总备份目录、容量与最近运行状态
  saltgoat magetools xtrabackup mysql dump [参数] # 导出单个数据库的逻辑备份

兼容命令:
  saltgoat magetools backup mysql <subcommand>    # 老版入口，调用时会收到迁移提示
EOF
}

ensure_env_exists() {
    if [[ ! -f "$MYSQL_ENV" ]]; then
        log_error "未找到配置文件: $MYSQL_ENV"
        log_info "请先运行 'saltgoat magetools xtrabackup mysql install'"
        exit 1
    fi
}

summary() {
    if [[ ! -d "$METADATA_DIR" ]]; then
        log_warning "未找到任何站点记录，可通过 'saltgoat magetools xtrabackup mysql install' 初始化"
        return
    fi

    sudo python3 - <<'PY'
import json, subprocess, os
from pathlib import Path
import datetime

META_DIR = Path("/etc/mysql/backup.d")
files = sorted(META_DIR.glob("*.env"))
if not files:
    print("暂无数据库备份记录")
    raise SystemExit

def run(cmd):
    return subprocess.run(["bash", "-lc", cmd], capture_output=True, text=True)

print(f"{'标识':<12} {'目录':<32} {'最近备份':<20} {'容量':<10} {'服务状态':<18} {'最近执行':<19}")
print("-" * 116)

for file in files:
    env = {}
    for line in file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip()

    name = env.get("SITE", file.stem)
    backup_dir = env.get("BACKUP_DIR", "/var/backups/mysql/xtrabackup")
    service = env.get("SERVICE_NAME", "saltgoat-mysql-backup.service")
    env_file = env.get("ENV_FILE", "/etc/mysql/mysql-backup.env")

    latest = "n/a"
    size = "n/a"
    if os.path.isdir(backup_dir):
        entries = sorted(
            [p for p in Path(backup_dir).iterdir() if p.is_dir()],
            key=lambda p: p.name
        )
        if entries:
            latest = entries[-1].name
        du = run(f"sudo du -sh '{backup_dir}' 2>/dev/null | cut -f1")
        if du.returncode == 0 and du.stdout.strip():
            size = du.stdout.strip()

    svc = run(f"systemctl show {service} --property=ActiveState,SubState,ExecMainStatus --no-pager")
    state = "unknown"
    status_code = ""
    if svc.returncode == 0:
        props = dict(line.split("=", 1) for line in svc.stdout.splitlines() if "=" in line)
        state = f"{props.get('ActiveState', '?')}/{props.get('SubState', '?')}"
        status_code = props.get("ExecMainStatus", "")

    journal = run(f"journalctl -u {service} -n 1 --no-pager --output=json")
    last_run = "n/a"
    if journal.returncode == 0 and journal.stdout.strip():
        try:
            entry = json.loads(journal.stdout.splitlines()[-1])
            ts = int(entry.get("__REALTIME_TIMESTAMP", "0"))
            if ts:
                dt = datetime.datetime.fromtimestamp(ts / 1_000_000)
                last_run = dt.strftime("%Y-%m-%d %H:%M:%S")
        except Exception:
            pass

    state_display = state
    if status_code:
        state_display = f"{state}({status_code})"

    print(f"{name:<12} {backup_dir:<32} {latest:<20} {size:<10} {state_display:<18} {last_run:<19}")
PY
}

resolve_path() {
    python3 - "$1" <<'PY'
import os, sys
path = sys.argv[1]
print(os.path.abspath(os.path.expanduser(path)))
PY
}

dump_database() {
    ensure_env_exists

    local database=""
    local backup_dir=""
    local repo_owner=""
    local compress=1
    local opt

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --database|-d)
                database="${2:-}"
                if [[ -z "$database" ]]; then
                    log_error "--database 需要一个数据库名称"
                    exit 1
                fi
                shift 2
                ;;
            --backup-dir|-b)
                backup_dir="${2:-}"
                if [[ -z "$backup_dir" ]]; then
                    log_error "--backup-dir 需要一个路径"
                    exit 1
                fi
                shift 2
                ;;
            --repo-owner|-o)
                repo_owner="${2:-}"
                if [[ -z "$repo_owner" ]]; then
                    log_error "--repo-owner 需要一个用户名"
                    exit 1
                fi
                shift 2
                ;;
            --no-compress)
                compress=0
                shift
                ;;
            --help|-h)
                cat <<'EOF'
用法:
  saltgoat magetools xtrabackup mysql dump \
      --database <name> \
      [--backup-dir <path>] \
      [--repo-owner <user>] \
      [--no-compress]

说明:
  --database     必填，指定要导出的数据库名称
  --backup-dir   备份输出目录（默认 /var/backups/mysql/dumps）
  --repo-owner   备份文件最终属主（默认读取 mysql-backup.env 内的 MYSQL_BACKUP_REPO_OWNER）
  --no-compress  关闭 gzip 压缩，输出 .sql 文件
EOF
                return 0
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done

    if [[ -z "$database" ]]; then
        log_error "请通过 --database 指定要备份的数据库名称"
        exit 1
    fi

    # 载入环境
    # shellcheck disable=SC1091
    source "$MYSQL_ENV"

    local mysql_user="${MYSQL_BACKUP_USER:-backup}"
    local mysql_password="${MYSQL_BACKUP_PASSWORD:-}"
    local mysql_host="${MYSQL_BACKUP_HOST:-localhost}"
    local mysql_port="${MYSQL_BACKUP_PORT:-3306}"
    local mysql_socket="${MYSQL_BACKUP_SOCKET:-}"
    local default_repo_owner="${MYSQL_BACKUP_REPO_OWNER:-${MYSQL_BACKUP_SERVICE_USER:-root}}"

    if [[ -z "$backup_dir" ]]; then
        backup_dir="$DUMP_DEFAULT_DIR"
    fi
    backup_dir="$(resolve_path "$backup_dir")"

    if [[ -z "$repo_owner" ]]; then
        repo_owner="$default_repo_owner"
    fi

    if ! command -v mysqldump >/dev/null 2>&1; then
        log_error "未找到 mysqldump，请先安装 mysql-client 或 percona 客户端工具"
        exit 1
    fi

    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local filename_base="${database}_${timestamp}.sql"
    local output_path
    if [[ $compress -eq 1 ]]; then
        output_path="${backup_dir}/${filename_base}.gz"
    else
        output_path="${backup_dir}/${filename_base}"
    fi

    log_info "准备导出数据库: $database"
    log_info "输出文件: $output_path"

    sudo mkdir -p "$backup_dir"

    local connect_args=()
    if [[ -n "$mysql_socket" && -S "$mysql_socket" ]]; then
        connect_args=(--socket="$mysql_socket")
    else
        connect_args=(--host="$mysql_host" --port="$mysql_port")
    fi

    local mysqldump_args=(
        --single-transaction
        --routines
        --events
        --set-gtid-purged=OFF
        --databases "$database"
    )

    if [[ -z "$mysql_password" ]]; then
        log_error "无法从 $MYSQL_ENV 读取 MYSQL_BACKUP_PASSWORD，无法继续"
        exit 1
    fi

    local tmp_output
    tmp_output="$(mktemp "${TMPDIR:-/tmp}/saltgoat-dump.XXXXXX")"
    if [[ $compress -eq 1 ]]; then
        if ! (set -o pipefail; MYSQL_PWD="$mysql_password" mysqldump --user="$mysql_user" "${connect_args[@]}" "${mysqldump_args[@]}" | gzip -c >"$tmp_output"); then
            rm -f "$tmp_output"
            log_error "mysqldump 失败，请检查数据库名称或备份账号权限"
            exit 1
        fi
    else
        if ! MYSQL_PWD="$mysql_password" mysqldump --user="$mysql_user" "${connect_args[@]}" "${mysqldump_args[@]}" >"$tmp_output"; then
            rm -f "$tmp_output"
            log_error "mysqldump 失败，请检查数据库名称或备份账号权限"
            exit 1
        fi
    fi

    sudo mv "$tmp_output" "$output_path"

    sudo chmod 640 "$output_path"
    if [[ -n "$repo_owner" ]]; then
        local repo_group
        repo_group=$(id -gn "$repo_owner" 2>/dev/null || echo "$repo_owner")
        sudo chown "$repo_owner":"$repo_group" "$output_path" 2>/dev/null || sudo chown "$repo_owner" "$output_path" || true
    fi

    log_success "数据库 $database 备份完成: $output_path"
}

ACTION="${1:-}"
case "$ACTION" in
    install|apply)
        shift || true
        log_info "应用 optional.mysql-backup 状态 ..."
        sudo salt-call --local --retcode-passthrough state.apply optional.mysql-backup "$@"
        ;;
    run)
        ensure_env_exists
        log_info "触发 MySQL 备份 ..."
        sudo systemctl start "$SERVICE_NAME"
        ;;
    status)
        sudo systemctl status "$SERVICE_NAME" "$TIMER_NAME"
        ;;
    logs)
        shift || true
        LINES="${1:-100}"
        sudo journalctl -u "$SERVICE_NAME" -u "$TIMER_NAME" -n "$LINES" --no-pager
        ;;
    summary|status-all|overview)
        summary
        ;;
    dump)
        shift || true
        dump_database "$@"
        ;;
    ""|-h|--help|help)
        usage
        ;;
    *)
        if [[ "$ACTION" == "restic" ]]; then
            # 兼容旧调用方式
            shift
            "${SCRIPT_DIR}/modules/magetools/backup-restic.sh" "$@"
        else
            usage
            exit 1
        fi
        ;;
esac

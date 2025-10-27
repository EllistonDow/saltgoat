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

usage() {
    cat <<'EOF'
用法:
  saltgoat magetools xtrabackup mysql install     # 根据 Pillar 应用 optional.mysql-backup
  saltgoat magetools xtrabackup mysql run         # 立即触发一次数据库备份
  saltgoat magetools xtrabackup mysql status      # 查看 systemd service/timer 状态
  saltgoat magetools xtrabackup mysql logs [N]    # 查看备份日志（默认最近 100 行）
  saltgoat magetools xtrabackup mysql summary     # 汇总备份目录、容量与最近运行状态

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

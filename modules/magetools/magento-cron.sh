#!/bin/bash
# Magento 2 Salt Schedule 任务管理
# modules/magetools/magento-cron.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"

# 配置参数
SITE_NAME="${1:-tank}"
ACTION="${2:-status}"

sync_salt_modules() {
    if command -v salt-call >/dev/null 2>&1; then
        sudo salt-call --local saltutil.sync_modules >/dev/null 2>&1 || true
    fi
}

# 显示帮助信息
show_help() {
    echo "Magento 2 定时维护任务管理"
    echo ""
    echo "用法: $0 <site_name> <action>"
    echo ""
    echo "参数:"
    echo "  site_name    站点名称 (默认: tank)"
    echo "  action       操作类型"
    echo ""
    echo "操作类型:"
    echo "  status        - 查看当前定时任务状态"
    echo "  install       - 安装定时维护任务"
    echo "  uninstall     - 卸载定时维护任务"
    echo "  test          - 测试定时任务"
    echo "  logs          - 查看定时任务日志"
    echo ""
    echo "示例:"
    echo "  $0 tank status"
    echo "  $0 tank install"
    echo "  $0 tank test"
}

# 检查参数
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
    exit 0
fi

if [[ ! -d "/var/www/$SITE_NAME" ]]; then
    log_error "站点目录不存在: /var/www/$SITE_NAME"
    exit 1
fi

log_highlight "Magento 2 定时维护任务管理: $SITE_NAME"
log_info "操作: $ACTION"
echo ""

# 检查当前定时任务状态
check_cron_status() {
    log_info "检查当前定时任务状态..."
    echo ""
    
    local schedule_output
    schedule_output="$(PYTHONWARNINGS=ignore sudo salt-call --local schedule.list --out=json 2>/dev/null || true)"

    log_info "Salt Schedule 任务:"
    if echo "$schedule_output" | grep -q "magento-"; then
        log_success "[SUCCESS] 已检测到 Magento 相关任务"
        SCHEDULE_PAYLOAD="$schedule_output" python3 - <<'PY'
import json
import os

try:
    from yaml import safe_load as yaml_safe_load  # type: ignore
except Exception:
    yaml_safe_load = None

import sys

payload_raw = os.environ.get("SCHEDULE_PAYLOAD", "")
try:
    outer = json.loads(payload_raw)
    schedule_blob = outer.get("local", "")
except Exception:
    schedule_blob = ""

if not schedule_blob:
    sys.exit(0)

def describe_cron(expr: str) -> str:
    parts = expr.split()
    if len(parts) != 5:
        return f"计划: {expr}"
    minute, hour, dom, month, dow = parts

    if minute.startswith("*/") and all(field == "*" for field in (hour, dom, month, dow)):
        return f"每 {minute[2:]} 分钟"

    if minute == "0" and hour == "*" and dom == "*" and month == "*" and dow == "*":
        return "每小时整点"

    if minute == "0" and hour != "*" and dom == "*" and month == "*" and dow == "*":
        return f"每天 {hour.zfill(2)}:{minute.zfill(2)}"

    if minute == "0" and hour != "*" and dom.isdigit() and month == "*" and dow == "*":
        return f"每月 {dom} 日 {hour.zfill(2)}:{minute.zfill(2)}"

    day_map = {
        "0": "周日",
        "1": "周一",
        "2": "周二",
        "3": "周三",
        "4": "周四",
        "5": "周五",
        "6": "周六",
    }

    if minute == "0" and hour != "*" and dom == "*" and month == "*" and dow in day_map:
        return f"每{day_map[dow]} {hour.zfill(2)}:{minute.zfill(2)}"

    return f"计划: {expr}"

parsed = None
if yaml_safe_load is not None:
    try:
        parsed = yaml_safe_load(schedule_blob)
    except Exception:
        parsed = None

if isinstance(parsed, dict):
    for entry_name, entry_data in (parsed.get("schedule") or {}).items():
        if not isinstance(entry_data, dict):
            continue
        cron = entry_data.get("cron", "n/a")
        args = entry_data.get("args") or []
        command = args[0] if args else ""
        description = describe_cron(str(cron))
        print(f"  - {entry_name}: {cron} -> {command}  # {description}")
else:
    print(schedule_blob)
PY
    else
        log_warning "[WARNING] 未发现 Magento 计划任务"
        log_info "使用 'saltgoat magetools cron $SITE_NAME install' 安装 Salt Schedule 任务"
    fi
    
    echo ""
    log_info "salt-minion 服务状态:"
    if systemctl is-active --quiet salt-minion; then
        log_success "[SUCCESS] salt-minion 正在运行"
    else
        log_error "[ERROR] salt-minion 未运行，Salt Schedule 将无法执行"
    fi
}

# 安装定时维护任务
install_cron_tasks() {
    log_info "通过 Salt Schedule 安装定时维护任务..."
    
    sync_salt_modules
    local install_output
    install_output=$(sudo salt-call --local saltgoat.magento_schedule_install site="$SITE_NAME" 2>&1)
    echo "$install_output"

    if echo "$install_output" | grep -q "Salt Schedule not available"; then
        log_error "[ERROR] 无法写入 Salt Schedule，请确认 salt-minion 已安装并在本机运行。"
        exit 1
    fi

    log_success "[SUCCESS] Salt Schedule 已配置 Magento 维护任务"

    log_info "使用 'saltgoat magetools cron $SITE_NAME status' 查看详情"
}

# 卸载定时维护任务
uninstall_cron_tasks() {
    log_info "移除 SaltGoat 定时维护计划..."

    sync_salt_modules
    local uninstall_output
    uninstall_output=$(sudo salt-call --local saltgoat.magento_schedule_uninstall site="$SITE_NAME" 2>&1)
    echo "$uninstall_output"

    if echo "$uninstall_output" | grep -q "cron_removed': True"; then
        log_info "[INFO] 已删除系统 Cron 计划: /etc/cron.d/magento-maintenance"
    fi

    log_success "[SUCCESS] 定时维护计划已移除"
}

# 测试定时任务
test_cron_tasks() {
    log_info "测试定时任务..."
    echo ""
    
    sync_salt_modules
    local test_jobs=("magento-cron" "magento-daily-maintenance")
    for job in "${test_jobs[@]}"; do
        log_info "触发 Salt Schedule 任务: $job"
        if salt-call --local schedule.run_job "$job" >/dev/null 2>&1; then
            log_success "[SUCCESS] 任务 $job 触发成功"
        else
            log_error "[ERROR] 任务 $job 触发失败"
        fi
        echo ""
    done
    
    log_info "触发健康检查任务:"
    if salt-call --local schedule.run_job magento-health-check >/dev/null 2>&1; then
        log_success "[SUCCESS] 健康检查任务触发成功"
    else
        log_error "[ERROR] 健康检查任务触发失败"
    fi
}

# 查看定时任务日志
view_cron_logs() {
    log_info "查看定时任务日志..."
    echo ""
    
    # 查看维护日志
    log_info "1. 维护任务日志:"
    if [[ -f "/var/log/magento-maintenance.log" ]]; then
        log_info "最近10行维护日志:"
        tail -10 /var/log/magento-maintenance.log
    else
        log_warning "[WARNING] 维护日志文件不存在"
    fi
    echo ""
    
    # 查看健康检查日志
    log_info "2. 健康检查日志:"
    if [[ -f "/var/log/magento-health.log" ]]; then
        log_info "最近10行健康检查日志:"
        tail -10 /var/log/magento-health.log
    else
        log_warning "[WARNING] 健康检查日志文件不存在"
    fi
    echo ""
}

# 主程序
case "$ACTION" in
    "status")
        check_cron_status
        ;;
    "install")
        install_cron_tasks
        ;;
    "uninstall")
        uninstall_cron_tasks
        ;;
    "test")
        test_cron_tasks
        ;;
    "logs")
        view_cron_logs
        ;;
    *)
        log_error "未知的操作: $ACTION"
        echo ""
        show_help
        exit 1
        ;;
esac

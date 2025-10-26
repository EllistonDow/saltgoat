#!/bin/bash
# SaltGoat 自动化任务管理（Salt Execution Module 封装）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"

SALT_CALL=(sudo salt-call --local --out=json)
SYNC_DONE=0

AUTOMATION_BASE_DIR=""
AUTOMATION_SCRIPTS_DIR=""
AUTOMATION_JOBS_DIR=""
AUTOMATION_LOGS_DIR=""

ensure_salt_available() {
    if ! command -v salt-call >/dev/null 2>&1; then
        log_error "未找到 salt-call，请先安装 SaltStack。"
        exit 1
    fi
}

sync_salt_modules() {
    if [[ "$SYNC_DONE" -eq 1 ]]; then
        return 0
    fi
    if command -v salt-call >/dev/null 2>&1; then
        sudo salt-call --local saltutil.sync_modules >/dev/null 2>&1 || true
        sudo salt-call --local saltutil.sync_runners >/dev/null 2>&1 || true
    fi
    SYNC_DONE=1
}

salt_exec_json() {
    local func="$1"
    shift
    "${SALT_CALL[@]}" "$func" "$@"
}

render_basic_result() {
    local json="$1"
    JSON_PAYLOAD="$json" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["JSON_PAYLOAD"])
result = next(iter(payload.values()))
ok = bool(result.get("result", True))
comment = result.get("comment") or ("操作完成" if ok else "操作失败")
comment = comment.replace("\n", " ")
if ok:
    print(comment)
else:
    print(comment, file=sys.stderr)
    sys.exit(1)
PY
}

extract_field() {
    local key="$1"
    local json="$2"
    JSON_PAYLOAD="$json" KEY_NAME="$key" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["JSON_PAYLOAD"])
result = next(iter(payload.values()))
value = result.get(os.environ["KEY_NAME"])
if value is None:
    sys.exit(1)
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

load_automation_paths() {
    if [[ -n "$AUTOMATION_BASE_DIR" ]]; then
        return 0
    fi

    local json
    if ! json=$(salt_exec_json saltgoat.automation_init); then
        log_error "无法初始化 SaltGoat 自动化目录。"
        exit 1
    fi

    local parsed
    if ! parsed=$(JSON_PAYLOAD="$json" python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["JSON_PAYLOAD"])
result = next(iter(payload.values()))
paths = result.get("paths") or {}
print(paths.get("base_dir", ""))
print(paths.get("scripts_dir", ""))
print(paths.get("jobs_dir", ""))
print(paths.get("logs_dir", ""))
PY
    ); then
        log_error "解析自动化目录信息失败。"
        exit 1
    fi

    local lines=()
    while IFS= read -r line; do
        lines+=("$line")
    done <<<"$parsed"

    local base="${lines[0]:-/srv/saltgoat/automation}"
    local scripts="${lines[1]:-$base/scripts}"
    local jobs="${lines[2]:-$base/jobs}"
    local logs="${lines[3]:-$base/logs}"

    AUTOMATION_BASE_DIR="$base"
    AUTOMATION_SCRIPTS_DIR="$scripts"
    AUTOMATION_JOBS_DIR="$jobs"
    AUTOMATION_LOGS_DIR="$logs"
}

handle_script_create() {
    local name="$1"
    if [[ -z "$name" ]]; then
        log_error "请输入脚本名称。"
        exit 1
    fi

    local json
    if ! json=$(salt_exec_json saltgoat.automation_script_create "name=$name"); then
        log_error "Salt 执行失败，无法创建脚本。"
        exit 1
    fi

    if output=$(render_basic_result "$json" 2>&1); then
        log_success "$output"
        if path=$(extract_field "path" "$json" 2>/dev/null); then
            log_info "脚本路径: $path"
        fi
    else
        log_error "$output"
        exit 1
    fi
}

handle_script_list() {
    local json
    if ! json=$(salt_exec_json saltgoat.automation_script_list); then
        log_error "无法获取脚本列表。"
        exit 1
    fi

    log_highlight "自动化脚本列表"
    JSON_PAYLOAD="$json" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["JSON_PAYLOAD"])
result = next(iter(payload.values()))
scripts = result.get("scripts") or []

if not scripts:
    print("暂无脚本，可使用 'saltgoat automation script create <name>' 创建。")
else:
    for item in scripts:
        print(f"- {item.get('name')}")
        print(f"  路径: {item.get('path')}")
        print(f"  修改时间: {item.get('modified')}")
        print(f"  大小: {item.get('size')} 字节")
PY
}

handle_script_edit() {
    local name="$1"
    if [[ -z "$name" ]]; then
        log_error "请输入脚本名称。"
        exit 1
    fi
    load_automation_paths
    local script_path="${AUTOMATION_SCRIPTS_DIR}/${name}.sh"
    if [[ -f "$script_path" ]]; then
        log_highlight "脚本路径: $script_path"
        log_info "请使用您喜欢的编辑器进行修改。"
    else
        log_error "脚本不存在: $script_path"
        exit 1
    fi
}

handle_script_run() {
    local name="$1"
    if [[ -z "$name" ]]; then
        log_error "请输入脚本名称。"
        exit 1
    fi

    local json
    if ! json=$(salt_exec_json saltgoat.automation_script_run "name=$name"); then
        log_error "脚本执行失败。"
        exit 1
    fi

    if output=$(render_basic_result "$json" 2>&1); then
        log_success "$output"
        if stdout=$(extract_field "stdout" "$json" 2>/dev/null); then
            if [[ -n "$stdout" ]]; then
                log_info "脚本输出:"
                printf '%s\n' "$stdout"
            fi
        fi
        if stderr=$(extract_field "stderr" "$json" 2>/dev/null); then
            if [[ -n "$stderr" ]]; then
                log_warning "标准错误:"
                printf '%s\n' "$stderr"
            fi
        fi
    else
        log_error "$output"
        if stderr=$(extract_field "stderr" "$json" 2>/dev/null); then
            printf '%s\n' "$stderr" >&2
        fi
        exit 1
    fi
}

handle_script_delete() {
    local name="$1"
    if [[ -z "$name" ]]; then
        log_error "请输入脚本名称。"
        exit 1
    fi

    local json
    if ! json=$(salt_exec_json saltgoat.automation_script_delete "name=$name"); then
        log_error "无法删除脚本。"
        exit 1
    fi

    if output=$(render_basic_result "$json" 2>&1); then
        log_success "$output"
    else
        log_error "$output"
        exit 1
    fi
}

handle_job_create() {
    local name="$1"
    local cron="$2"
    local script_name="${3:-$1}"
    if [[ -z "$name" || -z "$cron" ]]; then
        log_error "用法: saltgoat automation job create <job_name> <cron_schedule> [script_name]"
        exit 1
    fi

    local json
    if ! json=$(salt_exec_json saltgoat.automation_job_create "name=$name" "cron=$cron" "script=$script_name"); then
        log_error "任务创建失败。"
        exit 1
    fi

    if output=$(render_basic_result "$json" 2>&1); then
        log_success "$output"
        if backend=$(extract_field "backend" "$json" 2>/dev/null); then
            log_info "调度方式: $backend"
        fi
        if [[ -n "$AUTOMATION_JOBS_DIR" ]]; then
            log_info "任务配置: ${AUTOMATION_JOBS_DIR}/${name}.json"
        fi
        if script_missing=$(extract_field "script_missing" "$json" 2>/dev/null); then
            if [[ "$script_missing" == "true" ]]; then
                log_warning "脚本暂未创建，执行前请先创建脚本: $script_name"
            fi
        fi
    else
        log_error "$output"
        exit 1
    fi
}

handle_job_enable() {
    local name="$1"
    if [[ -z "$name" ]]; then
        log_error "请输入任务名称。"
        exit 1
    fi
    local json
    if ! json=$(salt_exec_json saltgoat.automation_job_enable "name=$name"); then
        log_error "任务启用失败。"
        exit 1
    fi
    if output=$(render_basic_result "$json" 2>&1); then
        log_success "$output"
        if backend=$(extract_field "backend" "$json" 2>/dev/null); then
            log_info "调度方式: $backend"
        fi
    else
        log_error "$output"
        exit 1
    fi
}

handle_job_disable() {
    local name="$1"
    if [[ -z "$name" ]]; then
        log_error "请输入任务名称。"
        exit 1
    fi
    local json
    if ! json=$(salt_exec_json saltgoat.automation_job_disable "name=$name"); then
        log_error "任务禁用失败。"
        exit 1
    fi
    if output=$(render_basic_result "$json" 2>&1); then
        log_success "$output"
    else
        log_error "$output"
        exit 1
    fi
}

handle_job_delete() {
    local name="$1"
    if [[ -z "$name" ]]; then
        log_error "请输入任务名称。"
        exit 1
    fi
    local json
    if ! json=$(salt_exec_json saltgoat.automation_job_delete "name=$name"); then
        log_error "任务删除失败。"
        exit 1
    fi
    if output=$(render_basic_result "$json" 2>&1); then
        log_success "$output"
    else
        log_error "$output"
        exit 1
    fi
}

handle_job_run() {
    local name="$1"
    if [[ -z "$name" ]]; then
        log_error "请输入任务名称。"
        exit 1
    fi

    local json
    if ! json=$(salt_exec_json saltgoat.automation_job_run "name=$name"); then
        log_error "任务执行失败。"
        exit 1
    fi

    if output=$(render_basic_result "$json" 2>&1); then
        log_success "$output"
        if log_file=$(extract_field "log_file" "$json" 2>/dev/null); then
            log_info "日志文件: $log_file"
        fi
        if duration=$(extract_field "duration" "$json" 2>/dev/null); then
            log_info "执行耗时: ${duration}s"
        fi
        if stdout=$(extract_field "stdout" "$json" 2>/dev/null); then
            if [[ -n "$stdout" ]]; then
                log_info "执行输出:"
                printf '%s\n' "$stdout"
            fi
        fi
        if stderr=$(extract_field "stderr" "$json" 2>/dev/null); then
            if [[ -n "$stderr" ]]; then
                log_warning "标准错误:"
                printf '%s\n' "$stderr"
            fi
        fi
    else
        log_error "$output"
        exit 1
    fi
}

handle_job_list() {
    local json
    if ! json=$(salt_exec_json saltgoat.automation_job_list); then
        log_error "无法获取任务列表。"
        exit 1
    fi

    log_highlight "自动化任务列表"
    JSON_PAYLOAD="$json" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["JSON_PAYLOAD"])
result = next(iter(payload.values()))
jobs = result.get("jobs") or []

if not jobs:
    print("暂无任务，可使用 'saltgoat automation job create ...' 创建。")
else:
    for item in jobs:
        name = item.get("name")
        enabled = "已启用" if item.get("enabled") else "已禁用"
        backend = item.get("backend")
        active = "运行中" if item.get("active") else "未调度"
        warning = " ⚠ 脚本缺失" if item.get("script_missing") else ""
        print(f"- {name} [{enabled}/{backend}] {active}{warning}")
        print(f"  Cron: {item.get('cron')}")
        script_path = item.get("script_path")
        if script_path:
            print(f"  脚本: {script_path}")
        last_run = item.get("last_run")
        if last_run:
            print(f"  最近执行: {last_run} (retcode={item.get('last_retcode')})")
PY
}

handle_logs_list() {
    load_automation_paths
    log_highlight "日志目录: $AUTOMATION_LOGS_DIR"
    if [[ ! -d "$AUTOMATION_LOGS_DIR" ]]; then
        log_info "暂无日志文件。"
        return 0
    fi

    local files
    files=$(find "$AUTOMATION_LOGS_DIR" -maxdepth 1 -type f -name "*.log" -print | sort) || true
    if [[ -z "$files" ]]; then
        log_info "暂无日志文件。"
        return 0
    fi

    while IFS= read -r file; do
        local size
        size=$(stat -c '%s' "$file" 2>/dev/null || echo 0)
        local mtime
        mtime=$(date -d "@$(stat -c '%Y' "$file" 2>/dev/null || echo 0)" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "未知")
        echo "- $(basename "$file")"
        echo "  大小: ${size} 字节"
        echo "  修改时间: $mtime"
    done <<<"$files"
}

handle_logs_view() {
    local name="$1"
    if [[ -z "$name" ]]; then
        log_error "用法: saltgoat automation logs view <log_file>"
        exit 1
    fi
    load_automation_paths
    local log_file="${AUTOMATION_LOGS_DIR}/${name}"
    if [[ -f "$log_file" ]]; then
        log_highlight "查看日志: $log_file"
        cat "$log_file"
    else
        log_error "日志不存在: $log_file"
        exit 1
    fi
}

handle_logs_tail() {
    local name="$1"
    if [[ -z "$name" ]]; then
        log_error "用法: saltgoat automation logs tail <log_file>"
        exit 1
    fi
    load_automation_paths
    local log_file="${AUTOMATION_LOGS_DIR}/${name}"
    if [[ -f "$log_file" ]]; then
        log_highlight "实时查看日志: $log_file (Ctrl+C 退出)"
        tail -f "$log_file"
    else
        log_error "日志不存在: $log_file"
        exit 1
    fi
}

handle_logs_cleanup() {
    local days="${1:-30}"
    load_automation_paths
    if [[ ! -d "$AUTOMATION_LOGS_DIR" ]]; then
        log_info "暂无日志目录。"
        return 0
    fi
    log_highlight "清理 ${days} 天前的日志文件..."
    local removed=0
    while IFS= read -r file; do
        removed=1
        rm -f "$file"
        echo "已删除: $file"
    done < <(find "$AUTOMATION_LOGS_DIR" -type f -name "*.log" -mtime +"$days" -print)

    if [[ $removed -eq 0 ]]; then
        log_info "未发现需要清理的日志。"
    else
        log_success "日志清理完成。"
    fi
}

handle_template() {
    local template="$1"
    case "$template" in
        "system-update")
            log_highlight "创建系统更新自动化模板 (每周日 02:00)..."
            handle_script_create "system-update"
            handle_job_create "system-update" "0 2 * * 0" "system-update"
            ;;
        "backup-cleanup")
            log_highlight "创建备份清理模板 (每周一 03:00)..."
            handle_script_create "backup-cleanup"
            handle_job_create "backup-cleanup" "0 3 * * 1" "backup-cleanup"
            ;;
        "log-rotation")
            log_highlight "创建日志轮转模板 (每日 01:00)..."
            handle_script_create "log-rotation"
            handle_job_create "log-rotation" "0 1 * * *" "log-rotation"
            ;;
        "security-scan")
            log_highlight "创建安全扫描模板 (每周二 04:00)..."
            handle_script_create "security-scan"
            handle_job_create "security-scan" "0 4 * * 2" "security-scan"
            ;;
        *)
            log_error "未知模板: $template"
            log_info "可用模板: system-update, backup-cleanup, log-rotation, security-scan"
            exit 1
            ;;
    esac
}

show_help() {
    cat <<'EOF'
SaltGoat 自动化任务管理

用法:
  saltgoat automation script <create|list|edit|run|delete> ...
  saltgoat automation job    <create|list|enable|disable|run|delete> ...
  saltgoat automation logs   <list|view|tail|cleanup> ...
  saltgoat automation templates <system-update|backup-cleanup|log-rotation|security-scan>

示例:
  saltgoat automation script create health-check
  saltgoat automation job create nightly "0 2 * * *" health-check
  saltgoat automation job enable nightly
  saltgoat automation logs list
EOF
}

_automation_entry() {
    if [[ $# -lt 1 ]]; then
        show_help
        exit 0
    fi

    case "$1" in
        "-h"|"--help")
            show_help
            exit 0
            ;;
    esac

    ensure_salt_available
    sync_salt_modules
    load_automation_paths

    local category="$1"
    shift

    case "$category" in
        "script")
            local action="${1:-}"
            case "$action" in
                "create")
                    handle_script_create "${2:-}"
                    ;;
                "list")
                    handle_script_list
                    ;;
                "edit")
                    handle_script_edit "${2:-}"
                    ;;
                "run")
                    handle_script_run "${2:-}"
                    ;;
                "delete")
                    handle_script_delete "${2:-}"
                    ;;
                *)
                    show_help
                    exit 1
                    ;;
            esac
            ;;
        "job")
            local action="${1:-}"
            case "$action" in
                "create")
                    handle_job_create "${2:-}" "${3:-}" "${4:-}"
                    ;;
                "list")
                    handle_job_list
                    ;;
                "enable")
                    handle_job_enable "${2:-}"
                    ;;
                "disable")
                    handle_job_disable "${2:-}"
                    ;;
                "run")
                    handle_job_run "${2:-}"
                    ;;
                "delete")
                    handle_job_delete "${2:-}"
                    ;;
                *)
                    show_help
                    exit 1
                    ;;
            esac
            ;;
        "logs")
            local action="${1:-}"
            case "$action" in
                "list")
                    handle_logs_list
                    ;;
                "view")
                    handle_logs_view "${2:-}"
                    ;;
                "tail")
                    handle_logs_tail "${2:-}"
                    ;;
                "cleanup")
                    handle_logs_cleanup "${2:-30}"
                    ;;
                *)
                    show_help
                    exit 1
                    ;;
            esac
            ;;
        "templates")
            handle_template "${1:-}"
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
}

automation_handler() {
    _automation_entry "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    _automation_entry "$@"
fi

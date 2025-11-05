#!/bin/bash
# MinIO management helper

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MINIO_HELPER="${SCRIPT_DIR}/modules/lib/minio_helper.py"
MINIO_PILLAR="${SALTGOAT_MINIO_PILLAR:-${SCRIPT_DIR}/salt/pillar/minio.sls}"
MINIO_ENV_FILE="/etc/minio/minio.env"

# shellcheck source=../../lib/logger.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"

minio_apply_states() {
    log_highlight "应用 optional.minio 状态..."
    if sudo salt-call --local state.apply optional.minio; then
        log_success "MinIO 状态已完成套用。"
    else
        log_error "MinIO 状态执行失败，请检查 salt-call 日志。"
        return 1
    fi
}

minio_show_info() {
    if [[ ! -f "$MINIO_PILLAR" ]]; then
        log_warning "未找到 Pillar: ${MINIO_PILLAR}"
    fi
    python3 "$MINIO_HELPER" info --pillar "$MINIO_PILLAR"
}

minio_health_check() {
    local timeout="${MINIO_HEALTH_TIMEOUT:-5}"
    local url
    if ! url="$(python3 "$MINIO_HELPER" health-url --pillar "$MINIO_PILLAR" 2>/dev/null)"; then
        log_error "无法加载健康检查 URL，请确认 pillar 中的 minio 配置。"
        return 2
    fi

    log_info "检测 MinIO 健康端点: ${url} (timeout=${timeout}s)"
    if command -v curl >/dev/null 2>&1; then
        if curl -fsS --max-time "$timeout" "$url" >/dev/null; then
            log_success "[SUCCESS] MinIO 健康检查通过。"
        else
            log_error "MinIO 健康检查失败。"
            return 3
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -qO- --timeout="$timeout" "$url" >/dev/null; then
            log_success "[SUCCESS] MinIO 健康检查通过。"
        else
            log_error "MinIO 健康检查失败。"
            return 3
        fi
    else
        log_error "未找到 curl 或 wget，无法执行健康检查。"
        return 4
    fi
}

minio_service_status() {
    if ! command -v systemctl >/dev/null 2>&1; then
        log_error "systemctl 不可用，无法读取 minio.service 状态。"
        return 1
    fi
    if ! systemctl list-unit-files | grep -q '^minio\\.service'; then
        log_warning "minio.service 尚未注册。"
        return 1
    fi
    systemctl status minio --no-pager
}

minio_show_env() {
    if [[ ! -f "$MINIO_ENV_FILE" ]]; then
        log_warning "未找到 ${MINIO_ENV_FILE}，请先运行 saltgoat minio apply。"
        return 1
    fi
    sudo cat "$MINIO_ENV_FILE"
}

minio_usage() {
    cat <<'EOF'
用法: saltgoat minio <command>

命令:
  apply        - 套用 optional.minio 状态（安装/更新服务）
  health       - 调用 /minio/health/live 检测健康
  status       - 查看 systemd minio.service 状态
  info         - 输出当前 Pillar 配置摘要(JSON)
  env          - 查看 /etc/minio/minio.env
EOF
}

minio_handler() {
    local action="${1:-help}"
    shift || true
    case "$action" in
        apply)
            minio_apply_states "$@"
            ;;
        health)
            minio_health_check "$@"
            ;;
        status)
            minio_service_status "$@"
            ;;
        info)
            minio_show_info "$@"
            ;;
        env)
            minio_show_env "$@"
            ;;
        help|*)
            minio_usage
            ;;
    esac
}

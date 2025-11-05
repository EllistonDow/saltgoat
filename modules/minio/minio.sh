#!/bin/bash
# MinIO management helper

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MINIO_HELPER="${SCRIPT_DIR}/modules/lib/minio_helper.py"
MINIO_PILLAR="${SALTGOAT_MINIO_PILLAR:-${SCRIPT_DIR}/salt/pillar/minio.sls}"
MINIO_ENV_FILE="/etc/minio/minio.env"
MINIO_SAMPLE_PILLAR="${SCRIPT_DIR}/salt/pillar/minio.sls.sample"

# shellcheck source=../../lib/logger.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"

ensure_minio_pillar() {
    if [[ -f "$MINIO_PILLAR" ]]; then
        return
    fi
    if [[ -f "$MINIO_SAMPLE_PILLAR" ]]; then
        log_info "未检测到 minio Pillar，自动复制样例..."
        cp "$MINIO_SAMPLE_PILLAR" "$MINIO_PILLAR"
        log_success "已创建 $MINIO_PILLAR"
    else
        log_warning "缺少 Pillar 样例: $MINIO_SAMPLE_PILLAR"
    fi
}

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

configure_minio_proxy() {
    local domain="$1"
    local console_domain="$2"
    local ssl_email="$3"
    local console_enabled="$4"
    ensure_minio_pillar
    local args=(set-proxy --pillar "$MINIO_PILLAR")
    if [[ -n "$domain" ]]; then
        args+=("--domain" "$domain")
    fi
    if [[ -n "$console_domain" ]]; then
        args+=("--console-domain" "$console_domain")
    fi
    if [[ -n "$ssl_email" ]]; then
        args+=("--ssl-email" "$ssl_email")
    fi
    if [[ "$console_enabled" == "0" ]]; then
        args+=("--disable-console")
    fi
    python3 "$MINIO_HELPER" "${args[@]}"
}

ensure_certbot_state() {
    log_info "确保 Certbot 就绪..."
    if sudo salt-call --local state.apply optional.certbot >/dev/null 2>&1; then
        log_success "Certbot 已可用。"
    else
        log_warning "Certbot 状态执行失败，请检查日志。"
    fi
}

minio_usage() {
    cat <<'EOF'
用法: saltgoat minio <command>

命令:
  apply        - 套用 optional.minio 状态（可传 --domain 自动配置反代）
  health       - 调用 /minio/health/live 检测健康
  status       - 查看 systemd minio.service 状态
  info         - 输出当前 Pillar 配置摘要(JSON)
  env          - 查看 /etc/minio/minio.env

apply 可选参数:
  --domain <域名>            为 API 配置 Nginx 反代与 HTTPS
  --console-domain <域名>     单独指定 Console 域名
  --ssl-email <邮箱>          Certbot 申请证书的邮箱
  --no-console               禁用 Console 反代，仅暴露 API
EOF
}

minio_handler() {
    local action="${1:-help}"
    shift || true
    case "$action" in
        apply)
            local domain=""
            local console_domain=""
            local ssl_email=""
            local console_enabled=1
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --domain)
                        domain="${2:-}"
                        shift 2
                        ;;
                    --console-domain)
                        console_domain="${2:-}"
                        shift 2
                        ;;
                    --ssl-email)
                        ssl_email="${2:-}"
                        shift 2
                        ;;
                    --no-console)
                        console_enabled=0
                        shift
                        ;;
                    --help|-h)
                        minio_usage
                        return 0
                        ;;
                    *)
                        log_warning "忽略未知参数: $1"
                        shift
                        ;;
                esac
            done
            if [[ -n "$domain" ]]; then
                configure_minio_proxy "$domain" "$console_domain" "$ssl_email" "$console_enabled"
                ensure_certbot_state
            fi
            minio_apply_states
            if [[ -n "$domain" ]]; then
                log_success "MinIO 反代已配置: https://$domain"
            fi
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

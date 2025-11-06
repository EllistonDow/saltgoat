#!/bin/bash
# Traefik docker deployment helper

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TRAEFIK_HELPER="${SCRIPT_DIR}/modules/lib/traefik_helper.py"
DOCKER_PILLAR="${SCRIPT_DIR}/salt/pillar/docker.sls"
DOCKER_SAMPLE="${SCRIPT_DIR}/salt/pillar/docker.sls.sample"

# shellcheck source=../../lib/logger.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"

ensure_docker_pillar() {
    if [[ -f "${DOCKER_PILLAR}" ]]; then
        return
    fi
    if [[ -f "${DOCKER_SAMPLE}" ]]; then
        log_info "未检测到 docker Pillar，自动复制样例..."
        cp "${DOCKER_SAMPLE}" "${DOCKER_PILLAR}"
        log_success "已创建 ${DOCKER_PILLAR}"
    else
        log_warning "缺少 Pillar 样例: ${DOCKER_SAMPLE}"
    fi
}

traefik_info_json() {
    ensure_docker_pillar
    python3 "${TRAEFIK_HELPER}" --pillar "${DOCKER_PILLAR}" info
}

traefik_get_field() {
    local field="$1"
    local json
    json="$(traefik_info_json)"
    JSON_PAYLOAD="$json" python3 - "$field" <<'PY'
import json, sys
import os
payload = os.environ.get("JSON_PAYLOAD", "")
if not payload:
    sys.exit(1)
data = json.loads(payload)
parts = sys.argv[1].split(".")
cur = data
for part in parts:
    if isinstance(cur, dict):
        cur = cur.get(part)
    else:
        cur = None
        break
if cur is None:
    sys.exit(1)
print(cur)
PY
}

traefik_base_dir() {
    traefik_get_field "base_dir"
}

traefik_project() {
    traefik_get_field "project"
}

traefik_compose() {
    local base_dir project
    base_dir="$(traefik_base_dir)"
    project="$(traefik_project)"
    if [[ -z "${base_dir}" || -z "${project}" ]]; then
        log_error "无法解析 Traefik base_dir 或 project（请检查 pillar）。"
        exit 1
    fi
    if [[ ! -d "${base_dir}" ]]; then
        log_warning "未发现 ${base_dir}，请先执行 'saltgoat traefik install'。"
    fi
    (cd "${base_dir}" && COMPOSE_PROJECT_NAME="${project}" sudo docker compose "$@")
}

traefik_cleanup_legacy() {
    if [[ -d "/opt/saltgoat/docker/npm" ]]; then
        log_info "检测到旧版 NPM 目录，尝试停止并移除..."
        if sudo docker compose -f /opt/saltgoat/docker/npm/docker-compose.yml down >/dev/null 2>&1; then
            log_success "旧 NPM 容器已停止。"
        fi
        sudo rm -rf /opt/saltgoat/docker/npm
        log_success "已移除 /opt/saltgoat/docker/npm。"
    fi
    shopt -s nullglob
    local legacy_files=(/etc/nginx/conf.d/proxy-*.conf)
    for file in "${legacy_files[@]}"; do
        log_info "移除遗留代理配置: ${file}"
        sudo rm -f "${file}"
    done
    shopt -u nullglob
    if [[ -d "/etc/nginx/conf.d/proxy" ]]; then
        log_info "移除遗留目录: /etc/nginx/conf.d/proxy"
        sudo rm -rf /etc/nginx/conf.d/proxy
    fi
}

traefik_install() {
    log_highlight "部署 Docker Engine 与 Traefik..."
    traefik_cleanup_legacy
    if ! sudo salt-call --local state.apply optional.docker >/dev/null; then
        log_error "optional.docker 执行失败，请检查日志。"
        exit 1
    fi
    if sudo salt-call --local state.apply optional.docker-traefik >/dev/null; then
        log_success "Traefik docker compose 已启动。"
    else
        log_error "optional.docker-traefik 执行失败，请检查日志。"
        exit 1
    fi
}

traefik_status() {
    traefik_compose ps
}

traefik_logs() {
    local lines="${1:-200}"
    traefik_compose logs --tail "${lines}"
}

traefik_restart() {
    log_info "重启 Traefik..."
    traefik_compose up -d --force-recreate
    log_success "Traefik 已重新部署。"
}

traefik_down() {
    log_info "停止 Traefik docker-compose..."
    traefik_compose down
}

traefik_show_config() {
    local config_path
    config_path="$(traefik_base_dir)/config/traefik.yml"
    if [[ -f "${config_path}" ]]; then
        sudo cat "${config_path}"
    else
        log_warning "未找到 ${config_path}"
    fi
}

traefik_usage() {
    cat <<'EOF'
用法: saltgoat traefik <command>

命令:
  install           - 部署 Docker Engine + Traefik docker-compose
  status            - 查看 docker compose ps
  logs [lines]      - 查看 Traefik 日志（默认 200 行）
  restart           - 重新创建并启动容器
  down              - 停止 Traefik 容器
  config            - 输出当前 traefik.yml
  cleanup-legacy    - 清理旧版 NPM/host 透传配置
  help              - 显示此帮助
EOF
}

traefik_handler() {
    local action="${1:-help}"
    shift || true
    case "${action}" in
        install)
            traefik_install
            ;;
        status)
            traefik_status
            ;;
        logs)
            traefik_logs "${1:-200}"
            ;;
        restart)
            traefik_restart
            ;;
        down)
            traefik_down
            ;;
        config)
            traefik_show_config
            ;;
        cleanup-legacy)
            traefik_cleanup_legacy
            ;;
        help|--help|-h)
            traefik_usage
            ;;
        *)
            log_error "未知命令: ${action}"
            traefik_usage
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    traefik_handler "$@"
fi

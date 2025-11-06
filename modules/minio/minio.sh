#!/bin/bash
# MinIO docker-compose management helper

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MINIO_HELPER="${SCRIPT_DIR}/modules/lib/minio_helper.py"
MINIO_PILLAR="${SALTGOAT_MINIO_PILLAR:-${SCRIPT_DIR}/salt/pillar/minio.sls}"
MINIO_SAMPLE_PILLAR="${SCRIPT_DIR}/salt/pillar/minio.sls.sample"

# shellcheck source=../../lib/logger.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"

ensure_minio_pillar() {
    if [[ -f "${MINIO_PILLAR}" ]]; then
        return
    fi
    if [[ -f "${MINIO_SAMPLE_PILLAR}" ]]; then
        log_info "未检测到 minio Pillar，自动复制样例..."
        cp "${MINIO_SAMPLE_PILLAR}" "${MINIO_PILLAR}"
        log_success "已创建 ${MINIO_PILLAR}"
    else
        log_warning "缺少 Pillar 样例: ${MINIO_SAMPLE_PILLAR}"
    fi
}

minio_info_json() {
    ensure_minio_pillar
    python3 "${MINIO_HELPER}" --pillar "${MINIO_PILLAR}" info
}

minio_get_field() {
    local field="$1"
    python3 -c 'import json, sys; data=json.load(sys.stdin); print(data.get(sys.argv[1], ""))' "${field}"
}

minio_base_dir() {
    minio_info_json | minio_get_field base_dir
}

minio_ensure_proxy_sites() {
    local minio_pillar="${SCRIPT_DIR}/salt/pillar/minio.sls"
    local nginx_pillar="${SCRIPT_DIR}/salt/pillar/nginx.sls"
    python3 - "${minio_pillar}" "${nginx_pillar}" <<'PY'
import sys
from pathlib import Path

import yaml

minio_path = Path(sys.argv[1])
nginx_path = Path(sys.argv[2])

if not minio_path.exists():
    sys.exit(0)

cfg = yaml.safe_load(minio_path.read_text(encoding="utf-8")) or {}
service = cfg.get("minio") or {}
if not isinstance(service, dict):
    sys.exit(0)

traefik_cfg = service.get("traefik") or {}

def collect_domains(section: dict, fallbacks: list[str]) -> list[str]:
    domains: list[str] = []
    domain = (section.get("domain") or "").strip()
    if not domain and fallbacks:
        domain = fallbacks[0]
    if domain:
        domains.append(domain)
    aliases = section.get("aliases") or fallbacks[1:]
    for alias in aliases or []:
        alias = (alias or "").strip()
        if alias and alias not in domains:
            domains.append(alias)
    return domains

api_fallbacks = []
primary_domain = (service.get("domain") or "").strip()
if primary_domain:
    api_fallbacks.append(primary_domain)
for alias in service.get("domain_aliases") or []:
    alias = (alias or "").strip()
    if alias:
        api_fallbacks.append(alias)
api_domains = collect_domains(traefik_cfg.get("api") or {}, api_fallbacks)

console_fallbacks = []
console_domain = (service.get("console_domain") or "").strip()
if console_domain:
    console_fallbacks.append(console_domain)
for alias in service.get("console_domain_aliases") or []:
    alias = (alias or "").strip()
    if alias:
        console_fallbacks.append(alias)
console_domains = collect_domains(traefik_cfg.get("console") or {}, console_fallbacks)

if not api_domains and not console_domains:
    sys.exit(0)

nginx = yaml.safe_load(nginx_path.read_text(encoding="utf-8")) if nginx_path.exists() else {}
if not isinstance(nginx, dict):
    nginx = {}
sites = nginx.setdefault("nginx", {}).setdefault("sites", {})

def ensure_site(name: str, domains: list[str]) -> None:
    if not domains:
        return
    entry = sites.get(name)
    if not isinstance(entry, dict):
        entry = {
            "enabled": True,
            "server_name": [],
            "listen": [{"port": 80}],
            "root": f"/var/www/{name}",
            "php": {"enabled": False},
            "headers": {
                "X-Frame-Options": "SAMEORIGIN",
                "X-Content-Type-Options": "nosniff",
            },
        }
        sites[name] = entry
    names = entry.setdefault("server_name", [])
    for domain in domains:
        if domain not in names:
            names.append(domain)
    primary = domains[0]
    cert_path = Path(f"/etc/letsencrypt/live/{primary}/fullchain.pem")
    key_path = Path(f"/etc/letsencrypt/live/{primary}/privkey.pem")
    cert_exists = cert_path.exists() and key_path.exists()
    entry["listen"] = [{"port": 80}]
    if cert_exists:
        entry["listen"].append({"port": 443, "ssl": True})
        entry["ssl"] = {
            "enabled": True,
            "cert": str(cert_path),
            "key": str(key_path),
            "protocols": "TLSv1.2 TLSv1.3",
            "prefer_server_ciphers": False,
            "redirect": True,
        }
    else:
        entry["ssl"] = {"enabled": False}
    entry.setdefault("php", {})["enabled"] = False
    headers = entry.setdefault("headers", {})
    headers.setdefault("X-Frame-Options", "SAMEORIGIN")
    headers.setdefault("X-Content-Type-Options", "nosniff")

ensure_site("minio-api", api_domains)
ensure_site("minio-console", console_domains)

nginx_path.write_text(yaml.safe_dump(nginx, sort_keys=False, default_flow_style=False), encoding="utf-8")
PY
    sudo mkdir -p /var/www/minio-api
    sudo mkdir -p /var/www/minio-console
}

minio_ssl_info() {
    python3 - "${SCRIPT_DIR}/salt/pillar/minio.sls" <<'PY'
from pathlib import Path
import sys
import yaml

pillar_path = Path(sys.argv[1])
if not pillar_path.exists():
    sys.exit(0)
cfg = yaml.safe_load(pillar_path.read_text(encoding="utf-8")) or {}
service = cfg.get("minio") or {}
if not isinstance(service, dict):
    sys.exit(0)

def collect_domains(section, fallbacks):
    domains = []
    domain = (section.get("domain") or "").strip()
    if not domain and fallbacks:
        domain = fallbacks[0]
    if domain:
        domains.append(domain)
    aliases = section.get("aliases") or fallbacks[1:]
    for alias in aliases or []:
        alias = (alias or "").strip()
        if alias and alias not in domains:
            domains.append(alias)
    return domains

traefik_cfg = service.get("traefik") or {}

api_fallbacks = []
primary_domain = (service.get("domain") or "").strip()
if primary_domain:
    api_fallbacks.append(primary_domain)
for alias in service.get("domain_aliases") or []:
    alias = (alias or "").strip()
    if alias:
        api_fallbacks.append(alias)
api_cfg = traefik_cfg.get("api") or {}
api_domains = collect_domains(api_cfg, api_fallbacks)
api_tls = (api_cfg.get("tls") or {}).get("enabled", False)

console_fallbacks = []
console_domain = (service.get("console_domain") or "").strip()
if console_domain:
    console_fallbacks.append(console_domain)
for alias in service.get("console_domain_aliases") or []:
    alias = (alias or "").strip()
    if alias:
        console_fallbacks.append(alias)
console_cfg = traefik_cfg.get("console") or {}
console_domains = collect_domains(console_cfg, console_fallbacks)
console_tls = (console_cfg.get("tls") or {}).get("enabled", False)

if api_domains and not api_tls:
    print(f"API={api_domains[0]}")
if console_domains and not console_tls:
    print(f"CONSOLE={console_domains[0]}")
PY
}

minio_issue_ssl() {
    local info
    info="$(minio_ssl_info)"
    [[ -z "${info}" ]] && return
    local site domain
    while IFS='=' read -r key value; do
        [[ -z "${key}" || -z "${value}" ]] && continue
        case "${key}" in
            API) site="minio-api" ;;
            CONSOLE) site="minio-console" ;;
            *) continue ;;
        esac
        domain="${value}"
        if [[ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
            log_info "检测到 ${domain} 已存在证书，跳过自动申请。"
            continue
        fi
        log_info "自动申请 Let's Encrypt 证书: ${domain}"
        if "${SCRIPT_DIR}/saltgoat" nginx add-ssl "${site}" "${domain}"; then
            log_success "证书申请完成 (${domain})。"
        else
            log_warning "证书申请失败 (${domain})，请手动执行 'saltgoat nginx add-ssl ${site} ${domain}'。"
        fi
    done <<< "${info}"
}

minio_apply() {
    log_highlight "应用 optional.minio 状态..."
    minio_ensure_proxy_sites
    if sudo salt-call --local state.apply optional.minio >/dev/null; then
        log_success "MinIO compose 部署完成。"
        minio_issue_ssl
    else
        log_error "MinIO 状态执行失败，请检查 salt-call 日志。"
        exit 1
    fi
}

minio_compose() {
    local base_dir
    base_dir="$(minio_base_dir)"
    if [[ -z "${base_dir}" ]]; then
        log_error "无法解析 base_dir（请检查 pillar）。"
        exit 1
    fi
    (cd "${base_dir}" && sudo docker compose "$@")
}

minio_status() {
    minio_compose ps
}

minio_logs() {
    local lines="${1:-100}"
    minio_compose logs --tail "${lines}"
}

minio_restart() {
    log_info "重新创建 MinIO 容器..."
    minio_compose up -d --force-recreate
    log_success "MinIO 已重新启动。"
}

minio_health() {
    local timeout="${MINIO_HEALTH_TIMEOUT:-5}"
    local url
    url="$(python3 "${MINIO_HELPER}" --pillar "${MINIO_PILLAR}" health-url)"
    if [[ -z "${url}" ]]; then
        log_error "无法解析健康检查 URL，请检查 pillar。"
        exit 1
    fi
    log_info "检测健康端点: ${url} (timeout=${timeout}s)"
    if command -v curl >/dev/null 2>&1; then
        if curl -fsS --max-time "${timeout}" "${url}" >/dev/null; then
            log_success "MinIO 健康检查通过。"
        else
            log_error "MinIO 健康检查失败。"
            exit 1
        fi
    else
        log_error "未找到 curl，无法执行健康检查。"
        exit 1
    fi
}

minio_show_info() {
    local json
    json="$(minio_info_json)"
    JSON_PAYLOAD="$json" python3 - <<'PY'
import json, sys
import os
payload = os.environ.get("JSON_PAYLOAD", "")
if not payload:
    sys.exit(1)
print(json.dumps(json.loads(payload), ensure_ascii=False, indent=2))
PY
}

minio_usage() {
    cat <<'EOF'
用法: saltgoat minio <command>

命令:
  apply         - 套用 optional.minio docker compose 部署
  status        - 查看 docker compose ps
  logs [lines]  - 查看容器日志（默认 100 行）
  restart       - 重新创建并启动容器
  info          - 输出 Pillar 摘要(JSON)
  health        - 调用 /minio/health/live 检测健康
  help          - 显示此帮助
EOF
}

minio_handler() {
    local action="${1:-help}"
    shift || true
    case "${action}" in
        apply)
            ensure_minio_pillar
            minio_apply
            ;;
        status)
            minio_status
            ;;
        logs)
            minio_logs "${1:-100}"
            ;;
        restart)
            minio_restart
            ;;
        info)
            minio_show_info
            ;;
        health)
            minio_health
            ;;
        help|--help|-h)
            minio_usage
            ;;
        *)
            log_error "未知命令: ${action}"
            minio_usage
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    minio_handler "$@"
fi

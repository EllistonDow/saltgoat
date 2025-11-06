#!/bin/bash
# Uptime Kuma docker-compose management helper

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT_DIR="${SCRIPT_DIR}"
LOGGER="${SCRIPT_DIR}/lib/logger.sh"
HELPER="${SCRIPT_DIR}/modules/lib/uptime_kuma_helper.py"
PILLAR_FILE="${SCRIPT_DIR}/salt/pillar/uptime_kuma.sls"
PILLAR_SAMPLE="${SCRIPT_DIR}/salt/pillar/uptime_kuma.sls.sample"

# shellcheck source=../../lib/logger.sh
# shellcheck disable=SC1091
source "${LOGGER}"

ensure_pillar() {
    if [[ -f "${PILLAR_FILE}" ]]; then
        return
    fi
    if [[ -f "${PILLAR_SAMPLE}" ]]; then
        log_info "未检测到 uptime_kuma Pillar，自动复制样例..."
        cp "${PILLAR_SAMPLE}" "${PILLAR_FILE}"
        log_success "已创建 ${PILLAR_FILE}"
    else
        log_warning "缺少 Pillar 样例: ${PILLAR_SAMPLE}"
    fi
}

kuma_info() {
    ensure_pillar
    python3 "${HELPER}" --pillar "${PILLAR_FILE}" info
}

kuma_get_field() {
    local field="$1"
    kuma_info | python3 - "$field" <<'PY'
import json, sys
data = json.load(sys.stdin)
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

kuma_base_dir() {
    kuma_get_field "base_dir"
}

ensure_proxy_site() {
    local site="$1"
    local pillar_path="${SCRIPT_DIR}/salt/pillar/nginx.sls"
    local uptime_pillar="${SCRIPT_DIR}/salt/pillar/uptime_kuma.sls"
    local docker_pillar="${SCRIPT_DIR}/salt/pillar/docker.sls"
    python3 - "${uptime_pillar}" "${pillar_path}" "${site}" "${docker_pillar}" <<'PY'
import sys
from pathlib import Path

import yaml

uptime_path = Path(sys.argv[1])
nginx_path = Path(sys.argv[2])
site = sys.argv[3]
docker_path = Path(sys.argv[4])

if not uptime_path.exists():
    sys.exit(0)

cfg = yaml.safe_load(uptime_path.read_text(encoding="utf-8")) or {}
service = cfg.get("uptime_kuma") or {}
if not isinstance(service, dict):
    sys.exit(0)
traefik = service.get("traefik") or {}
domains = []
primary = (traefik.get("domain") or service.get("domain") or "").strip()
if primary:
    domains.append(primary)
for alias in traefik.get("aliases") or service.get("domain_aliases") or []:
    alias = (alias or "").strip()
    if alias and alias not in domains:
        domains.append(alias)

if not domains:
    sys.exit(0)

nginx = yaml.safe_load(nginx_path.read_text(encoding="utf-8")) if nginx_path.exists() else {}
if not isinstance(nginx, dict):
    nginx = {}
nginx_cfg = nginx.setdefault("nginx", {})
sites = nginx_cfg.setdefault("sites", {})
entry = sites.get(site)
if not isinstance(entry, dict):
    entry = {
        "enabled": True,
        "server_name": [],
        "listen": [{"port": 80}],
        "root": f"/var/www/{site}",
        "php": {"enabled": False},
        "headers": {
            "X-Frame-Options": "SAMEORIGIN",
            "X-Content-Type-Options": "nosniff",
        },
    }
    sites[site] = entry

names = entry.setdefault("server_name", [])
for domain in domains:
    if domain not in names:
        names.append(domain)

from pathlib import Path as _Path
primary = domains[0]
cert_path = _Path(f"/etc/letsencrypt/live/{primary}/fullchain.pem")
key_path = _Path(f"/etc/letsencrypt/live/{primary}/privkey.pem")
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

php_cfg = entry.setdefault("php", {})
php_cfg["enabled"] = False
headers = entry.setdefault("headers", {})
headers.setdefault("X-Frame-Options", "SAMEORIGIN")
headers.setdefault("X-Content-Type-Options", "nosniff")

webroot = entry.get("root", f"/var/www/{site}")
locations = entry.setdefault("locations", {})
proxy_block = locations.setdefault("/", {})
proxy_directives = [
    f"proxy_pass http://127.0.0.1:{{port}}",
    "proxy_set_header Host $host",
    "proxy_set_header X-Real-IP $remote_addr",
    "proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for",
    "proxy_set_header X-Forwarded-Proto $scheme",
]

traefik_port = 18080
if docker_path.exists():
    try:
        docker_cfg = yaml.safe_load(docker_path.read_text(encoding="utf-8")) or {}
    except Exception:
        docker_cfg = {}
    if isinstance(docker_cfg, dict):
        docker_node = docker_cfg.get("docker") or {}
        if isinstance(docker_node, dict):
            traefik_cfg = docker_node.get("traefik") or {}
            if isinstance(traefik_cfg, dict):
                traefik_port = traefik_cfg.get("http_port", traefik_port)

proxy_block["directives"] = [d.format(port=traefik_port) for d in proxy_directives]

challenge_block = locations.setdefault("/.well-known/acme-challenge/", {})
challenge_block["directives"] = [
    f"alias {webroot}/.well-known/acme-challenge/",
    "try_files $uri =404",
]

nginx_path.write_text(yaml.safe_dump(nginx, sort_keys=False, default_flow_style=False), encoding="utf-8")
PY
    sudo mkdir -p "/var/www/${site}"
}

kuma_ssl_domain() {
    python3 - "${PILLAR_FILE}" <<'PY'
from pathlib import Path
import sys
import yaml

pillar_path = Path(sys.argv[1])
if not pillar_path.exists():
    sys.exit(0)
cfg = yaml.safe_load(pillar_path.read_text(encoding="utf-8")) or {}
service = cfg.get("uptime_kuma") or {}
if not isinstance(service, dict):
    sys.exit(0)
traefik = service.get("traefik") or {}
tls_enabled = (traefik.get("tls") or {}).get("enabled", False)
if tls_enabled:
    sys.exit(0)
domains = []
primary = (traefik.get("domain") or service.get("domain") or "").strip()
if primary:
    domains.append(primary)
for alias in (traefik.get("aliases") or service.get("domain_aliases") or []):
    alias = (alias or "").strip()
    if alias and alias not in domains:
        domains.append(alias)
if domains:
    print(domains[0])
PY
}

kuma_issue_ssl() {
    local domain
    domain="$(kuma_ssl_domain)"
    if [[ -z "${domain}" ]]; then
        return
    fi
    if [[ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
        log_info "检测到 ${domain} 已存在证书，跳过自动申请。"
        return
    fi
    log_info "ACME dry-run: uptime-kuma ${domain}"
    if ! "${SCRIPT_DIR}/saltgoat" nginx add-ssl uptime-kuma "${domain}" -dry-on; then
        log_warning "证书 dry-run 失败 (${domain})，跳过自动申请，请手动执行 'saltgoat nginx add-ssl uptime-kuma ${domain}'。"
        return
    fi
    log_info "自动申请 Let's Encrypt 证书: ${domain}"
    if "${SCRIPT_DIR}/saltgoat" nginx add-ssl uptime-kuma "${domain}"; then
        log_success "证书申请完成 (${domain})。"
    else
        log_warning "证书申请失败 (${domain})，请手动执行 'saltgoat nginx add-ssl uptime-kuma ${domain}'。"
    fi
}

kuma_compose_cmd() {
    local base_dir project
    base_dir="$(kuma_base_dir)"
    project="uptime-kuma"
    if [[ ! -d "${base_dir}" ]]; then
        log_warning "未发现 ${base_dir}，请先执行 'saltgoat uptime-kuma install'。"
    fi
    (cd "${base_dir}" && COMPOSE_PROJECT_NAME="${project}" sudo docker compose "$@")
}

kuma_cleanup_legacy() {
    log_info "清理旧版 Uptime Kuma (systemd) 部署..."
    if systemctl list-unit-files | grep -q '^uptime-kuma\.service'; then
        sudo systemctl stop uptime-kuma || true
        sudo systemctl disable uptime-kuma || true
        sudo rm -f /etc/systemd/system/uptime-kuma.service
        sudo systemctl daemon-reload
        log_success "旧 systemd 服务已移除。"
    fi
    if [[ -d /opt/uptime-kuma ]]; then
        sudo rm -rf /opt/uptime-kuma
        log_success "旧目录 /opt/uptime-kuma 已清理。"
    fi
}

kuma_install() {
    log_highlight "部署 Uptime Kuma (docker compose)..."
    kuma_cleanup_legacy
    ensure_pillar
    ensure_proxy_site "uptime-kuma"
    if sudo salt-call --local state.apply optional.uptime-kuma >/dev/null; then
        log_success "Uptime Kuma docker-compose 已启动。"
        kuma_issue_ssl
    else
        log_error "optional.uptime-kuma 执行失败，请检查 salt-call 日志。"
        exit 1
    fi
}

kuma_status() {
    kuma_compose_cmd ps
}

kuma_logs() {
    local lines="${1:-200}"
    kuma_compose_cmd logs --tail "${lines}"
}

kuma_restart() {
    kuma_compose_cmd up -d --force-recreate
    log_success "Uptime Kuma 已重新部署。"
}

kuma_down() {
    kuma_compose_cmd down
    log_success "Uptime Kuma 容器已停止。"
}

kuma_pull() {
    kuma_compose_cmd pull
    log_success "镜像已更新，请运行 'saltgoat uptime-kuma restart' 重新部署。"
}

kuma_show_config() {
    kuma_info
}

kuma_usage() {
    cat <<'EOF'
用法: saltgoat uptime-kuma <command>

命令:
  install         - 套用 optional.uptime-kuma docker compose 部署
  status          - 查看 docker compose ps
  logs [lines]    - 查看容器日志（默认 200 行）
  restart         - 重新创建并启动容器
  down            - 停止 Uptime Kuma 容器
  pull            - 拉取最新镜像
  config          - 输出合并后的 Pillar 配置
  cleanup-legacy  - 清除旧版 systemd/手工安装残留
  help            - 显示此帮助
EOF
}

kuma_handler() {
    local action="${1:-help}"
    shift || true
    case "${action}" in
        install)
            kuma_install
            ;;
        status)
            kuma_status
            ;;
        logs)
            kuma_logs "${1:-200}"
            ;;
        restart)
            kuma_restart
            ;;
        down)
            kuma_down
            ;;
        pull|upgrade|update)
            kuma_pull
            ;;
        config)
            kuma_show_config
            ;;
        cleanup-legacy)
            kuma_cleanup_legacy
            ;;
        help|--help|-h)
            kuma_usage
            ;;
        *)
            log_error "未知命令: ${action}"
            kuma_usage
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    kuma_handler "$@"
fi

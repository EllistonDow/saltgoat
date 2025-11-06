#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/logger.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"

DEFAULT_BASE_DIR="/opt/saltgoat/docker/mattermost"
NGINX_PILLAR="${SCRIPT_DIR}/salt/pillar/nginx.sls"
MATTERMOST_PILLAR="${SCRIPT_DIR}/salt/pillar/mattermost.sls"

pillar_get_value() {
    local key="$1"
    local default="${2:-}"
    local result
    result=$(sudo salt-call --local --out=json pillar.get "$key" 2>/dev/null | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("local",""))' 2>/dev/null || true)
    if [[ -n "$result" && "$result" != "None" ]]; then
        echo "$result"
    else
        echo "$default"
    fi
}

mattermost_base_dir() {
    pillar_get_value "mattermost:base_dir" "$DEFAULT_BASE_DIR"
}

mattermost_ensure_site() {
    local site="mattermost"
    local docker_pillar="${SCRIPT_DIR}/salt/pillar/docker.sls"
    python3 - "${MATTERMOST_PILLAR}" "${NGINX_PILLAR}" "${docker_pillar}" <<'PY'
from pathlib import Path
import sys

import yaml

mm_path = Path(sys.argv[1])
nginx_path = Path(sys.argv[2])
docker_path = Path(sys.argv[3])

if not mm_path.exists():
    sys.exit(0)

cfg = yaml.safe_load(mm_path.read_text(encoding="utf-8")) or {}
mm = cfg.get("mattermost") or {}
if not isinstance(mm, dict):
    sys.exit(0)

domain = (mm.get("domain") or "").strip()
traefik = mm.get("traefik") or {}
aliases = traefik.get("aliases", []) if isinstance(traefik, dict) else []
if isinstance(aliases, str):
    aliases = [aliases]
domains = []
if domain:
    domains.append(domain)
for alias in aliases:
    alias = (alias or "").strip()
    if alias and alias not in domains:
        domains.append(alias)

if not domains:
    sys.exit(0)

nginx_data = yaml.safe_load(nginx_path.read_text(encoding="utf-8")) if nginx_path.exists() else {}
if not isinstance(nginx_data, dict):
    nginx_data = {}
nginx_cfg = nginx_data.setdefault("nginx", {})
sites = nginx_cfg.setdefault("sites", {})
entry = sites.get("mattermost")
if not isinstance(entry, dict):
    entry = {
        "enabled": True,
        "server_name": [],
        "listen": [{"port": 80}],
        "root": "/var/www/mattermost",
        "php": {"enabled": False},
        "headers": {
            "X-Frame-Options": "SAMEORIGIN",
            "X-Content-Type-Options": "nosniff",
        },
    }
    sites["mattermost"] = entry

names = entry.setdefault("server_name", [])
for host in domains:
    if host not in names:
        names.append(host)

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

php_cfg = entry.setdefault("php", {})
php_cfg["enabled"] = False
headers = entry.setdefault("headers", {})
headers.setdefault("X-Frame-Options", "SAMEORIGIN")
headers.setdefault("X-Content-Type-Options", "nosniff")

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

webroot = entry.get("root", "/var/www/mattermost")
locations = entry.setdefault("locations", {})
proxy_block = locations.setdefault("/", {})
proxy_block["directives"] = [
    f"proxy_pass http://127.0.0.1:{traefik_port}",
    "proxy_set_header Host $host",
    "proxy_set_header X-Real-IP $remote_addr",
    "proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for",
    "proxy_set_header X-Forwarded-Proto $scheme",
]
challenge_block = locations.setdefault("/.well-known/acme-challenge/", {})
challenge_block["directives"] = [
    f"alias {webroot}/.well-known/acme-challenge/",
    "try_files $uri =404",
]

nginx_path.write_text(yaml.safe_dump(nginx_data, sort_keys=False, default_flow_style=False), encoding="utf-8")
PY
    sudo mkdir -p /var/www/mattermost
}

mattermost_ssl_domain() {
    python3 - "${MATTERMOST_PILLAR}" <<'PY'
from pathlib import Path
import sys
import yaml

pillar_path = Path(sys.argv[1])
if not pillar_path.exists():
    sys.exit(0)
cfg = yaml.safe_load(pillar_path.read_text(encoding="utf-8")) or {}
mm = cfg.get("mattermost") or {}
if not isinstance(mm, dict):
    sys.exit(0)
traefik = mm.get("traefik") or {}
tls_enabled = (traefik.get("tls") or {}).get("enabled", False)
if tls_enabled:
    sys.exit(0)
domain = (mm.get("domain") or "").strip()
if domain:
    print(domain)
PY
}

mattermost_issue_ssl() {
    local domain
    domain="$(mattermost_ssl_domain)"
    if [[ -z "${domain}" ]]; then
        return
    fi
    if [[ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
        log_info "检测到 ${domain} 已有证书，跳过自动申请。"
        return
    fi
    log_info "ACME dry-run: mattermost ${domain}"
    if ! "${SCRIPT_DIR}/saltgoat" nginx add-ssl mattermost "${domain}" -dry-on; then
        log_warning "证书 dry-run 失败 (${domain})，跳过自动申请，请手动执行 'saltgoat nginx add-ssl mattermost ${domain}'。"
        return
    fi
    log_info "自动申请 Let's Encrypt 证书: ${domain}"
    if "${SCRIPT_DIR}/saltgoat" nginx add-ssl mattermost "${domain}"; then
        log_success "证书申请完成 (${domain})。"
    else
        log_warning "证书申请失败 (${domain})，请手动执行 'saltgoat nginx add-ssl mattermost ${domain}'。"
    fi
}

mattermost_compose_dir() {
    local dir
    dir="$(mattermost_base_dir)"
    if [[ ! -d "$dir" ]]; then
        sudo mkdir -p "$dir"
    fi
    echo "$dir"
}

mattermost_usage() {
    cat <<'EOF'
用法: saltgoat mattermost <command>

命令:
  install            安装/更新 Mattermost (docker compose)
  status             查看容器状态
  logs [lines]       查看应用日志（默认 200 行）
  restart            重启容器
  upgrade            拉取最新镜像并重启
EOF
}

mattermost_install() {
    log_highlight "部署 Mattermost (docker compose)..."
    mattermost_ensure_site
    if sudo salt-call --local state.apply optional.mattermost >/dev/null; then
        log_success "Mattermost docker-compose 已启动。"
        mattermost_issue_ssl
    else
        log_error "optional.mattermost 执行失败，请检查 salt-call 日志。"
        exit 1
    fi
}

mattermost_status() {
    local dir
    dir="$(mattermost_compose_dir)"
    (cd "$dir" && sudo docker compose ps)
}

mattermost_logs() {
    local dir
    dir="$(mattermost_compose_dir)"
    local lines="${1:-200}"
    (cd "$dir" && sudo docker compose logs --tail "$lines" app)
}

mattermost_restart() {
    local dir
    dir="$(mattermost_compose_dir)"
    (cd "$dir" && sudo docker compose restart)
}

mattermost_upgrade() {
    local dir
    dir="$(mattermost_compose_dir)"
    (cd "$dir" && sudo docker compose pull && sudo docker compose up -d)
}

mattermost_main() {
    local action="${1:-help}"
    shift || true
    case "$action" in
        install)
            mattermost_install
            ;;
        status)
            mattermost_status
            ;;
        logs)
            mattermost_logs "${1:-200}"
            ;;
        restart)
            mattermost_restart
            ;;
        upgrade|update)
            mattermost_upgrade
            ;;
        help|*)
            mattermost_usage
            ;;
    esac
}

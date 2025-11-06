#!/bin/bash
# Mastodon multi-instance management helper

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PILLAR_FILE="${SCRIPT_DIR}/salt/pillar/mastodon.sls"
PILLAR_SAMPLE="${SCRIPT_DIR}/salt/pillar/mastodon.sls.sample"

# Ensure repo modules can be imported by python helpers
export PYTHONPATH="${SCRIPT_DIR}:${PYTHONPATH:-}"

# shellcheck source=../lib/logger.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"

ensure_pillar() {
    if [[ -f "${PILLAR_FILE}" ]]; then
        return
    fi
    if [[ -f "${PILLAR_SAMPLE}" ]]; then
        log_info "未检测到 mastodon Pillar，自动复制样例..."
        cp "${PILLAR_SAMPLE}" "${PILLAR_FILE}"
        log_success "已创建 ${PILLAR_FILE}"
    else
        log_warning "缺少 Pillar 样例: ${PILLAR_SAMPLE}"
    fi
}

mastodon_list_sites() {
    python3 - "$PILLAR_FILE" <<'PY'
import json
import sys
from pathlib import Path
from modules.lib import mastodon_helper

cfg = mastodon_helper.load_config(Path(sys.argv[1]))
sites = mastodon_helper.list_instances(cfg)
print("\n".join(sites))
PY
}

mastodon_site_exists() {
    python3 - "$PILLAR_FILE" "$1" <<'PY'
import sys
from pathlib import Path
from modules.lib import mastodon_helper

cfg = mastodon_helper.load_config(Path(sys.argv[1]))
sites = set(mastodon_helper.list_instances(cfg))
sys.exit(0 if sys.argv[2] in sites else 1)
PY
}

mastodon_ensure_site() {
    local site="$1"
    if ! mastodon_site_exists "$site"; then
        log_error "Mastodon site '${site}' 未在 pillar mastodon:instances 中配置。"
        exit 1
    fi
}

mastodon_site_json() {
    local site="$1"
    python3 - "$PILLAR_FILE" "$site" <<'PY'
import json
import sys
from pathlib import Path
from modules.lib import mastodon_helper

cfg = mastodon_helper.load_config(Path(sys.argv[1]))
try:
    inst = mastodon_helper.get_instance(cfg, sys.argv[2])
except KeyError as exc:
    raise SystemExit(str(exc))
print(json.dumps(inst))
PY
}

mastodon_field() {
    local site="$1" field="$2"
    python3 - "$PILLAR_FILE" "$site" "$field" <<'PY'
import json
import sys
from pathlib import Path
from modules.lib import mastodon_helper

cfg = mastodon_helper.load_config(Path(sys.argv[1]))
data = mastodon_helper.get_instance(cfg, sys.argv[2])
value = data
for part in sys.argv[3].split("."):
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
        break
if isinstance(value, (dict, list)):
    print(json.dumps(value))
elif value is not None:
    print(value)
PY
}

mastodon_base_dir() {
    local site="$1"
    mastodon_field "$site" "base_dir"
}

mastodon_backups_dir() {
    local site="$1"
    mastodon_field "$site" "storage.backups_dir"
}

mastodon_domain() {
    local site="$1"
    mastodon_field "$site" "domain" 2>/dev/null || echo ""
}

mastodon_prepare_nginx() {
    local site="$1"
    local domain
    domain="$(mastodon_domain "$site")"
    if [[ -z "${domain}" ]]; then
        return
    fi
    local nginx_pillar="${SCRIPT_DIR}/salt/pillar/nginx.sls"
    local docker_pillar="${SCRIPT_DIR}/salt/pillar/docker.sls"
    python3 - "$PILLAR_FILE" "$nginx_pillar" "$docker_pillar" "$site" <<'PY'
import json
import sys
from pathlib import Path

import yaml

from modules.lib import mastodon_helper

pillar_path = Path(sys.argv[1])
nginx_path = Path(sys.argv[2])
docker_path = Path(sys.argv[3])
site = sys.argv[4]

cfg = mastodon_helper.load_config(pillar_path)
site_cfg = mastodon_helper.get_instance(cfg, site)

domain = (site_cfg.get("domain") or "").strip()
if not domain:
    sys.exit(0)

aliases = []
traefik_cfg = site_cfg.get("traefik") or {}
raw_aliases = traefik_cfg.get("aliases") or []
if isinstance(raw_aliases, str):
    raw_aliases = [raw_aliases]
for alias in raw_aliases:
    alias = (alias or "").strip()
    if alias and alias not in aliases:
        aliases.append(alias)

domains = [domain] + [a for a in aliases if a and a != domain]

if nginx_path.exists():
    nginx_data = yaml.safe_load(nginx_path.read_text(encoding="utf-8")) or {}
else:
    nginx_data = {}
if not isinstance(nginx_data, dict):
    nginx_data = {}
nginx_cfg = nginx_data.setdefault("nginx", {})
sites_cfg = nginx_cfg.setdefault("sites", {})
entry = sites_cfg.get(f"mastodon-{site}")
if not isinstance(entry, dict):
    entry = {
        "enabled": True,
        "server_name": [],
        "listen": [{"port": 80}],
        "root": f"/var/www/mastodon-{site}",
        "php": {"enabled": False},
        "headers": {
            "X-Frame-Options": "SAMEORIGIN",
            "X-Content-Type-Options": "nosniff",
        },
    }
    sites_cfg[f"mastodon-{site}"] = entry

server_names = entry.setdefault("server_name", [])
for host in domains:
    if host not in server_names:
        server_names.append(host)

traefik_port = 18080
if docker_path.exists():
    try:
        docker_cfg = yaml.safe_load(docker_path.read_text(encoding="utf-8")) or {}
    except Exception:
        docker_cfg = {}
    if isinstance(docker_cfg, dict):
        docker_node = docker_cfg.get("docker") or {}
        if isinstance(docker_node, dict):
            traefik_data = docker_node.get("traefik") or {}
            if isinstance(traefik_data, dict):
                traefik_port = traefik_data.get("http_port", traefik_port)

entry["listen"] = [{"port": 80}]

cert_path = Path(f"/etc/letsencrypt/live/{domain}/fullchain.pem")
key_path = Path(f"/etc/letsencrypt/live/{domain}/privkey.pem")
if cert_path.exists() and key_path.exists():
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
    f"alias /var/www/mastodon-{site}/.well-known/acme-challenge/",
    "try_files $uri =404",
]

nginx_path.write_text(yaml.safe_dump(nginx_data, sort_keys=False, default_flow_style=False), encoding="utf-8")
PY
    sudo mkdir -p "/var/www/mastodon-${site}"
}

mastodon_project_name() {
    local site="$1"
    echo "mastodon-${site}"
}

mastodon_traefik_tls_enabled() {
    local site="$1"
    local value
    value="$(mastodon_field "$site" "traefik.tls.enabled" 2>/dev/null || echo "false")"
    case "${value,,}" in
        true|1|"\"true\""|"\"1\"")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

mastodon_compose_cmd() {
    local site="$1"
    mastodon_ensure_site "$site"
    shift || true
    local base_dir
    base_dir="$(mastodon_base_dir "$site")"
    if [[ ! -d "$base_dir" ]]; then
        log_warning "未找到 ${base_dir}，请先执行 'saltgoat mastodon install ${site}'。"
    fi
    local project
    project="$(mastodon_project_name "$site")"
    (cd "$base_dir" && sudo env COMPOSE_PROJECT_NAME="$project" docker compose "$@")
}

mastodon_compose_run() {
    local site="$1"
    shift || true
    if [[ $# -eq 0 ]]; then
        log_error "mastodon_compose_run 需要指定要执行的命令。"
        exit 1
    fi
    mastodon_compose_cmd "$site" run --rm web "$@"
}


mastodon_install() {
    local site="$1"
    ensure_pillar
    mastodon_ensure_site "$site"
    mastodon_prepare_nginx "$site"
    log_highlight "部署 Mastodon 实例: ${site}"
    if ! sudo salt-call --local state.apply optional.mastodon pillar="{'mastodon_site': '${site}'}" >/dev/null; then
        log_error "Salt 状态 optional.mastodon 执行失败，请检查 salt-call 日志。"
        exit 1
    fi
    log_info "运行数据库迁移..."
    mastodon_compose_run "$site" bundle exec rake db:migrate
    local domain
    domain="$(mastodon_domain "$site" || true)"
    if [[ -n "${domain}" ]]; then
        log_info "注册本地域名 ${domain}..."
        mastodon_compose_cmd "$site" run --rm web tootctl domains add "${domain}" >/dev/null 2>&1 || true
    fi
    mastodon_compose_cmd "$site" up -d
    mastodon_issue_ssl "$site"
    log_info "请手动执行 'docker compose run --rm web bin/tootctl accounts create ...' 创建管理员。"
    log_success "Mastodon 实例 ${site} 已部署完成。"
}

mastodon_issue_ssl() {
    local site="$1"
    if mastodon_traefik_tls_enabled "$site"; then
        return
    fi
    local domain
    domain="$(mastodon_domain "$site")"
    if [[ -z "${domain}" ]]; then
        return
    fi
    local nginx_site="mastodon-${site}"
    if [[ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
        log_info "检测到 ${domain} 已存在证书，跳过自动申请。"
        return
    fi
    log_info "ACME dry-run: ${domain}"
    if ! "${SCRIPT_DIR}/saltgoat" nginx add-ssl "${nginx_site}" "${domain}" -dry-on; then
        log_warning "证书 dry-run 失败 (${domain})，请手动执行 'saltgoat nginx add-ssl ${nginx_site} ${domain}'。"
        return
    fi
    log_info "自动申请 Let's Encrypt 证书: ${domain}"
    if "${SCRIPT_DIR}/saltgoat" nginx add-ssl "${nginx_site}" "${domain}"; then
        log_success "证书申请完成 (${domain})。"
    else
        log_warning "证书申请失败 (${domain})，请手动执行 'saltgoat nginx add-ssl ${nginx_site} ${domain}'。"
    fi
}

mastodon_status() {
    local site="$1"
    mastodon_compose_cmd "$site" ps
}

mastodon_logs() {
    local site="$1"
    shift || true
    local lines="200"
    if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
        lines="$1"
        shift
    fi
    if [[ $# -gt 0 ]]; then
        mastodon_compose_cmd "$site" logs --tail "${lines}" "$@"
    else
        mastodon_compose_cmd "$site" logs --tail "${lines}"
    fi
}

mastodon_restart() {
    local site="$1"
    log_info "重启 Mastodon ${site} ..."
    mastodon_compose_cmd "$site" up -d
    log_success "Mastodon ${site} 已启动。"
}

mastodon_down() {
    local site="$1"
    mastodon_compose_cmd "$site" down
    log_success "Mastodon ${site} 容器已停止。"
}

mastodon_pull() {
    local site="$1"
    mastodon_compose_cmd "$site" pull
    log_success "镜像已更新，请运行 'saltgoat mastodon restart ${site}'。"
}

mastodon_upgrade() {
    local site="$1"
    log_highlight "升级 Mastodon ${site} ..."
    mastodon_compose_cmd "$site" pull
    mastodon_compose_run "$site" bundle exec rake db:migrate
    mastodon_compose_cmd "$site" up -d
    log_success "Mastodon ${site} 升级完成。"
}

mastodon_backup_db() {
    local site="$1"
    mastodon_ensure_site "$site"
    local backups_dir
    backups_dir="$(mastodon_backups_dir "$site")"
    local db_name db_user
    db_name="$(mastodon_field "$site" "postgres.db")"
    db_user="$(mastodon_field "$site" "postgres.user")"
    local db_pass
    db_pass="$(mastodon_field "$site" "postgres.password")"
    local timestamp
    timestamp="$(date -u +"%Y%m%d_%H%M%S")"
    local target="${backups_dir}/db-${timestamp}.sql.gz"
    log_info "导出数据库到 ${target}"
    sudo mkdir -p "${backups_dir}"
    local base_dir
    base_dir="$(mastodon_base_dir "$site")"
    local project
    project="$(mastodon_project_name "$site")"
    if ! sudo env COMPOSE_PROJECT_NAME="$project" docker compose -f "${base_dir}/docker-compose.yml" exec -T db bash -lc "PGPASSWORD='${db_pass}' pg_dump -U '${db_user}' '${db_name}'" | gzip | sudo tee "${target}" >/dev/null; then
        log_error "数据库备份失败。"
        exit 1
    fi
    sudo chown root:root "${target}"
    log_success "数据库备份完成: ${target}"
}

mastodon_usage() {
    cat <<'EOF'
用法: saltgoat mastodon <command> [site] [options]

命令:
  list                         列出已配置的 Mastodon 实例
  install <site>               部署或更新指定实例
  status <site>                查看 docker compose 状态
  logs <site> [lines] [svc]    查看日志（默认 200 行）
  restart <site>               重新启动容器
  down <site>                  停止并移除容器
  pull <site>                  拉取最新镜像
  upgrade <site>               拉取 + 迁移 + 启动
  backup-db <site>             导出 PostgreSQL 备份
  help                         显示此帮助
EOF
}

mastodon_handler() {
    local action="${1:-help}"
    shift || true
    case "${action}" in
        list)
            ensure_pillar
            mastodon_list_sites
            ;;
        install)
            if [[ $# -lt 1 ]]; then
                log_error "用法: saltgoat mastodon install <site>"
                exit 1
            fi
            mastodon_install "$1"
            ;;
        status)
            [[ $# -lt 1 ]] && { log_error "用法: saltgoat mastodon status <site>"; exit 1; }
            mastodon_status "$1"
            ;;
        logs)
            if [[ $# -lt 1 ]]; then
                log_error "用法: saltgoat mastodon logs <site> [lines] [service]"
                exit 1
            fi
            local site="$1"
            shift
            local lines="200"
            if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
                lines="$1"
                shift
            fi
            mastodon_logs "$site" "$lines" "$@"
            ;;
        restart)
            [[ $# -lt 1 ]] && { log_error "用法: saltgoat mastodon restart <site>"; exit 1; }
            mastodon_restart "$1"
            ;;
        down)
            [[ $# -lt 1 ]] && { log_error "用法: saltgoat mastodon down <site>"; exit 1; }
            mastodon_down "$1"
            ;;
        pull)
            [[ $# -lt 1 ]] && { log_error "用法: saltgoat mastodon pull <site>"; exit 1; }
            mastodon_pull "$1"
            ;;
        upgrade)
            [[ $# -lt 1 ]] && { log_error "用法: saltgoat mastodon upgrade <site>"; exit 1; }
            mastodon_upgrade "$1"
            ;;
        backup-db)
            [[ $# -lt 1 ]] && { log_error "用法: saltgoat mastodon backup-db <site>"; exit 1; }
            mastodon_backup_db "$1"
            ;;
        help|--help|-h|"")
            mastodon_usage
            ;;
        *)
            log_error "未知命令: ${action}"
            mastodon_usage
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    mastodon_handler "$@"
fi

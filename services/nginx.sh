#!/bin/bash
# Nginx 管理入口（Salt 原生状态封装）

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"
PILLAR_FILE="${PROJECT_ROOT}/salt/pillar/nginx.sls"

# shellcheck disable=SC1091
source "${PROJECT_ROOT}/lib/logger.sh"

ensure_pillar_file() {
    if [[ ! -f "${PILLAR_FILE}" ]]; then
        cat <<'EOF' > "${PILLAR_FILE}"
nginx:
  package: nginx
  service: nginx
  user: www-data
  group: www-data
  default_site: false
  client_max_body_size: 64m
  sites: {}
EOF
    fi
}

python_update() {
    local mode="$1"; shift
    MODE="${mode}" \
    PILLAR_FILE="${PILLAR_FILE}" \
    SITE="${1:-}" \
    DOMAINS="${2:-}" \
    ROOT_PATH="${3:-}" \
    EMAIL="${4:-}" \
    SSL_DOMAIN="${5:-}" \
    python3 <<'PY'
import os
import sys
from pathlib import Path

try:
    import yaml  # type: ignore
except ImportError:
    sys.stderr.write("PyYAML 未安装，无法管理 Nginx pillar。\n")
    sys.exit(1)

pillar_path = Path(os.environ["PILLAR_FILE"])
mode = os.environ["MODE"]
site = os.environ.get("SITE") or ""
domains = os.environ.get("DOMAINS", "")
root_path = os.environ.get("ROOT_PATH") or ""
email = os.environ.get("EMAIL") or ""
ssl_domain = os.environ.get("SSL_DOMAIN") or ""

if pillar_path.exists():
    data = yaml.safe_load(pillar_path.read_text()) or {}
else:
    data = {}

nginx = data.setdefault("nginx", {})
sites = nginx.setdefault("sites", {})

def save():
    pillar_path.write_text(
        yaml.safe_dump(data, sort_keys=False, default_flow_style=False)
    )

if mode == "create":
    if not site or not domains:
        sys.stderr.write("站点与域名均为必填。\n")
        sys.exit(1)
    if site in sites:
        sys.stderr.write(f"站点 {site} 已存在。\n")
        sys.exit(1)
    domains_list = [d for d in domains.split() if d]
    if not domains_list:
        sys.stderr.write("至少提供一个域名。\n")
        sys.exit(1)
    root = root_path or f"/var/www/{site}"
    sites[site] = {
        "enabled": True,
        "server_name": domains_list,
        "listen": [{"port": 80}],
        "root": root,
        "index": ["index.php", "index.html"],
        "php": {
            "enabled": True,
            "fastcgi_pass": "unix:/run/php/php8.3-fpm.sock",
        },
        "headers": {
            "X-Frame-Options": "SAMEORIGIN",
            "X-Content-Type-Options": "nosniff",
        },
    }
    save()
elif mode == "delete":
    if site not in sites:
        sys.stderr.write(f"站点 {site} 不存在。\n")
        sys.exit(1)
    del sites[site]
    save()
elif mode in {"enable", "disable"}:
    if site not in sites:
        sys.stderr.write(f"站点 {site} 不存在。\n")
        sys.exit(1)
    sites[site]["enabled"] = mode == "enable"
    save()
elif mode == "ssl":
    if site not in sites:
        sys.stderr.write(f"站点 {site} 不存在。\n")
        sys.exit(1)
    candidates = sites[site].get("server_name", [])
    domain = ssl_domain or (candidates[0] if candidates else "")
    if not domain:
        sys.stderr.write("未找到可用于 SSL 的域名。\n")
        sys.exit(1)
    cert_path = f"/etc/letsencrypt/live/{domain}/fullchain.pem"
    key_path = f"/etc/letsencrypt/live/{domain}/privkey.pem"
    ssl = sites[site].setdefault("ssl", {})
    ssl.update(
        {
            "enabled": True,
            "cert": cert_path,
            "key": key_path,
            "protocols": "TLSv1.2 TLSv1.3",
            "prefer_server_ciphers": False,
        }
    )
    if email:
        nginx["ssl_email"] = email
    save()
elif mode == "list":
    for name, cfg in sites.items():
        enabled = cfg.get("enabled", True)
        domains = ", ".join(cfg.get("server_name", []))
        root = cfg.get("root", "")
        ssl_enabled = cfg.get("ssl", {}).get("enabled", False)
        print(f"{name}: enabled={enabled}, ssl={ssl_enabled}, root={root}, domains=[{domains}]")
else:
    sys.stderr.write(f"未知操作: {mode}\n")
    sys.exit(1)
PY
}

ensure_sites_exist() {
    ensure_pillar_file
    python_update list >/dev/null
}

cmd_apply() {
    ensure_sites_exist
    log_highlight "应用 core.nginx 状态..."
    salt-call --local --retcode-passthrough state.apply core.nginx
}

cmd_reload() {
    log_highlight "重载 Nginx 服务..."
    salt-call --local --retcode-passthrough service.reload nginx
}

cmd_test() {
    log_highlight "执行 nginx -t 配置测试..."
    salt-call --local --retcode-passthrough cmd.run 'nginx -t -c /etc/nginx/nginx.conf'
}

cmd_create() {
    local site="$1"
    local domains="$2"
    local root_path="${3:-}"
    ensure_pillar_file
    python_update create "$site" "$domains" "$root_path"
    log_success "站点 ${site} 已写入 pillar。"
    cmd_apply
}

cmd_delete() {
    local site="$1"
    ensure_pillar_file
    python_update delete "$site"
    log_success "已移除站点 ${site}。"
    cmd_apply
}

cmd_enable_disable() {
    local action="$1"
    local site="$2"
    ensure_pillar_file
    python_update "$action" "$site"
    log_success "站点 ${site} 已标记为 ${action}。"
    cmd_apply
}

cmd_list() {
    ensure_pillar_file
    python_update list
}

cmd_ssl() {
    local site="$1"
    local domain="${2:-}"
    local email="${3:-}"
    ensure_pillar_file
    python_update ssl "$site" "" "" "$email" "$domain"
    log_info "已更新站点 ${site} 的 SSL 信息。请确保证书已存在或执行 salt-call state.apply optional.certbot。"
    cmd_apply
}

nginx_cli_help() {
    cat <<'EOF'
用法:
  saltgoat nginx apply                     # 套用 core.nginx Salt 状态
  saltgoat nginx list                      # 查看所有站点
  saltgoat nginx create <站点> "<域名 ...>" [根目录]
  saltgoat nginx delete <站点>
  saltgoat nginx enable <站点>
  saltgoat nginx disable <站点>
  saltgoat nginx add-ssl <站点> [域名] [email]
  saltgoat nginx reload
  saltgoat nginx test
EOF
}

_nginx_dispatch() {
    local action="${1:-help}"
    case "$action" in
        apply)
            cmd_apply
            ;;
        list)
            cmd_list
            ;;
        create)
            local site="${2:-}"
            local domains="${3:-}"
            local root="${4:-}"
            if [[ -z "$site" || -z "$domains" ]]; then
                log_error "用法: saltgoat nginx create <站点> \"<域名 ...>\" [根目录]"
                exit 1
            fi
            cmd_create "$site" "$domains" "$root"
            ;;
        delete)
            local site="${2:-}"
            if [[ -z "$site" ]]; then
                log_error "用法: saltgoat nginx delete <站点>"
                exit 1
            fi
            cmd_delete "$site"
            ;;
        enable|disable)
            local site="${2:-}"
            if [[ -z "$site" ]]; then
                log_error "用法: saltgoat nginx $action <站点>"
                exit 1
            fi
            cmd_enable_disable "$action" "$site"
            ;;
        add-ssl)
            local site="${2:-}"
            if [[ -z "$site" ]]; then
                log_error "用法: saltgoat nginx add-ssl <站点> [域名] [email]"
                exit 1
            fi
            cmd_ssl "$site" "${3:-}" "${4:-}"
            ;;
        reload)
            cmd_reload
            ;;
        test)
            cmd_test
            ;;
        help|--help|-h|"")
            nginx_cli_help
            ;;
        modsecurity)
            if [[ -f "${PROJECT_ROOT}/modules/security/modsecurity-salt.sh" ]]; then
                # shellcheck disable=SC1091
                source "${PROJECT_ROOT}/modules/security/modsecurity-salt.sh"
                modsecurity_salt_handler "modsecurity" "$2" "$3"
            else
                log_error "ModSecurity Salt 模块不存在"
                exit 1
            fi
            ;;
        csp)
            if [[ -f "${PROJECT_ROOT}/modules/security/csp-salt.sh" ]]; then
                # shellcheck disable=SC1091
                source "${PROJECT_ROOT}/modules/security/csp-salt.sh"
                csp_salt_handler "csp" "$2" "$3"
            else
                log_error "CSP Salt 模块不存在"
                exit 1
            fi
            ;;
        *)
            log_error "未知操作: $action"
            nginx_cli_help
            exit 1
            ;;
    esac
}

nginx_handler() {
    # saltgoat 传入的第一个参数为 "nginx"
    _nginx_dispatch "${@:2}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _nginx_dispatch "$@"
fi

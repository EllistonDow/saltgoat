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

run_salt_call() {
    local -a cmd=(salt-call --local --retcode-passthrough "$@")
    if [[ $EUID -ne 0 ]]; then
        cmd=(sudo "${cmd[@]}")
    fi
    "${cmd[@]}"
}

cleanup_site_files() {
    local site="$1"
    local available="/etc/nginx/sites-available/${site}"
    local enabled="/etc/nginx/sites-enabled/${site}"
    local access_log="/var/log/nginx/${site}.access.log"
    local error_log="/var/log/nginx/${site}.error.log"

    if [[ -e "$available" || -L "$enabled" ]]; then
        log_info "清理站点残留文件..."
    fi

    if [[ -e "$available" ]]; then
        if [[ $EUID -ne 0 ]]; then
            sudo rm -f "$available"
        else
            rm -f "$available"
        fi
    fi

    if [[ -L "$enabled" || -e "$enabled" ]]; then
        if [[ $EUID -ne 0 ]]; then
            sudo rm -f "$enabled"
        else
            rm -f "$enabled"
        fi
    fi

    if [[ -f "$access_log" ]]; then
        if [[ $EUID -ne 0 ]]; then
            sudo rm -f "$access_log"
        else
            rm -f "$access_log"
        fi
    fi

    if [[ -f "$error_log" ]]; then
        if [[ $EUID -ne 0 ]]; then
            sudo rm -f "$error_log"
        else
            rm -f "$error_log"
        fi
    fi
}

detect_magento_admin_path() {
    local roots
    roots=$(PILLAR_FILE="${PILLAR_FILE}" python3 <<'PY'
import os
import yaml
from pathlib import Path

pillar = Path(os.environ.get("PILLAR_FILE", ""))
if not pillar.exists():
    exit()

data = yaml.safe_load(pillar.read_text()) or {}
sites = (data.get("nginx") or {}).get("sites") or {}
for name, site in sites.items():
    if isinstance(site, dict) and site.get("magento"):
        root = site.get("root") or f"/var/www/{name}"
        if root:
            print(root)
PY
)
    local default_path="/admin_tattoo"
    local root
    while IFS= read -r root; do
        [[ -z "$root" ]] && continue
        local env_path="${root%/}/app/etc/env.php"
        if [[ -f "$env_path" ]]; then
            local front_name
            if [[ $EUID -ne 0 ]]; then
                front_name=$(sudo env "MAGENTO_ENV_PATH=$env_path" php -r 'error_reporting(0); $app = @include getenv("MAGENTO_ENV_PATH"); if (is_array($app) && isset($app["backend"]["frontName"])) echo $app["backend"]["frontName"];' 2>/dev/null || true)
            else
                front_name=$(MAGENTO_ENV_PATH="$env_path" php -r 'error_reporting(0); $app = @include getenv("MAGENTO_ENV_PATH"); if (is_array($app) && isset($app["backend"]["frontName"])) echo $app["backend"]["frontName"];' 2>/dev/null || true)
            fi
            if [[ -n "$front_name" ]]; then
                if [[ "$front_name" == /* ]]; then
                    echo "$front_name"
                else
                    echo "/${front_name#/}"
                fi
                return 0
            fi
        fi
    done <<<"$roots"
    echo "$default_path"
}

nginx_supports_modsecurity() {
    if ! command -v nginx >/dev/null 2>&1; then
        return 1
    fi
    if nginx -V 2>&1 | grep -qi 'modsecurity'; then
        return 0
    fi
    if ls /etc/nginx/modules-enabled/ngx_http_modsecurity_module.so >/dev/null 2>&1 2>/dev/null; then
        return 0
    fi
    if ls /usr/lib/nginx/modules/ngx_http_modsecurity_module.so >/dev/null 2>&1 2>/dev/null; then
        return 0
    fi
    return 1
}

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

read_pillar_value() {
    local key="$1"
    python3 <<'PY' 2>/dev/null
import os
import yaml
from pathlib import Path

pillar_path = Path(os.environ.get("PILLAR_FILE", ""))
key_path = os.environ.get("KEY_PATH", "")

if not pillar_path.exists():
    exit(0)

data = yaml.safe_load(pillar_path.read_text()) or {}

def get_by_path(d, path):
    parts = path.split(":")
    cur = d
    for part in parts:
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur

value = get_by_path(data, key_path)
if value is not None:
    import json
    print(json.dumps(value))
PY
}

python_update() {
    local mode="$1"; shift
    local site_arg="${1:-}"
    local domains_arg="${2:-}"
    local root_arg="${3:-}"
    local email_arg="${4:-}"
    local ssl_arg="${5:-}"
    local magento_env="${6:-}"
    local -a env_vars=(
        "MODE=${mode}"
        "PILLAR_FILE=${PILLAR_FILE}"
        "SITE=${site_arg}"
        "DOMAINS=${domains_arg}"
        "ROOT_PATH=${root_arg}"
        "EMAIL=${email_arg}"
        "SSL_DOMAIN=${ssl_arg}"
    )
    if [[ -n "$magento_env" ]]; then
        env_vars+=("MAGENTO_FLAG=${magento_env}")
    fi
    if [[ -n "${CSP_LEVEL:-}" ]]; then
        env_vars+=("CSP_LEVEL=${CSP_LEVEL}")
    fi
    if [[ -n "${MODSEC_LEVEL:-}" ]]; then
        env_vars+=("MODSEC_LEVEL=${MODSEC_LEVEL}")
    fi
    if [[ -n "${MODSEC_ADMIN_PATH:-}" ]]; then
        env_vars+=("MODSEC_ADMIN_PATH=${MODSEC_ADMIN_PATH}")
    fi
    if [[ -n "${CSP_ENABLED:-}" ]]; then
        env_vars+=("CSP_ENABLED=${CSP_ENABLED}")
    fi
    if [[ -n "${MODSEC_ENABLED:-}" ]]; then
        env_vars+=("MODSEC_ENABLED=${MODSEC_ENABLED}")
    fi
    env "${env_vars[@]}" python3 <<'PY'
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
magento_flag = os.environ.get("MAGENTO_FLAG") == "1"

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
    if magento_flag:
        sites[site]["magento"] = True
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
elif mode == "csp_level":
    levels = {
        1: "default-src 'self' http: https: data: blob: 'unsafe-inline' 'unsafe-eval'",
        2: "default-src 'self' http: https: data: blob: 'unsafe-inline' 'unsafe-eval'; script-src 'self' 'unsafe-inline' 'unsafe-eval'",
        3: "default-src 'self' http: https: data: blob: 'unsafe-inline'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'",
        4: "default-src 'self' http: https: data: blob:; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' http: https: data:; font-src 'self' http: https: data:",
        5: "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' http: https: data:; font-src 'self' http: https: data:; connect-src 'self' http: https:; frame-src 'self'"
    }
    level = int(os.environ.get("CSP_LEVEL", "0") or 0)
    enabled_flag = os.environ.get("CSP_ENABLED")
    csp_cfg = nginx.setdefault("csp", {})
    if level <= 0 or enabled_flag == "0":
        csp_cfg.update({"enabled": False, "level": 0, "policy": ""})
    else:
        if level not in levels:
            sys.stderr.write(f"不支持的 CSP 等级: {level}\n")
            sys.exit(1)
        csp_cfg.update({"enabled": True, "level": level, "policy": levels[level]})
    save()
elif mode == "modsecurity_level":
    level_raw = os.environ.get("MODSEC_LEVEL", "0") or "0"
    try:
        level = int(level_raw)
    except ValueError:
        sys.stderr.write(f"无效的 ModSecurity 等级: {level_raw}\n")
        sys.exit(1)
    enabled_flag = os.environ.get("MODSEC_ENABLED")
    admin_path = os.environ.get("MODSEC_ADMIN_PATH") or nginx.get("modsecurity", {}).get("admin_path", "/admin")
    mod_cfg = nginx.setdefault("modsecurity", {})
    if level <= 0 or enabled_flag == "0":
        mod_cfg.update({"enabled": False, "level": 0, "admin_path": admin_path})
    else:
        if level < 1 or level > 10:
            sys.stderr.write(f"ModSecurity 等级必须在 1-10 之间: {level}\n")
            sys.exit(1)
        mod_cfg.update({"enabled": True, "level": level, "admin_path": admin_path})
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

get_csp_policy() {
    local level="$1"
    case "$level" in
        1) echo "default-src 'self' http: https: data: blob: 'unsafe-inline' 'unsafe-eval'" ;;
        2) echo "default-src 'self' http: https: data: blob: 'unsafe-inline' 'unsafe-eval'; script-src 'self' 'unsafe-inline' 'unsafe-eval'" ;;
        3) echo "default-src 'self' http: https: data: blob: 'unsafe-inline'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'" ;;
        4) echo "default-src 'self' http: https: data: blob:; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' http: https: data:; font-src 'self' http: https: data:" ;;
        5) echo "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' http: https: data:; font-src 'self' http: https: data:; connect-src 'self' http: https:; frame-src 'self'" ;;
        *) return 1 ;;
    esac
}

show_csp_status() {
    local json
    json=$(KEY_PATH="nginx:csp" PILLAR_FILE="${PILLAR_FILE}" read_pillar_value "nginx:csp")
    if [[ -n "$json" ]]; then
        JSON_DATA="$json" python3 - <<'PY'
import json, os
data = json.loads(os.environ.get("JSON_DATA", "{}"))
enabled = data.get("enabled", False)
level = data.get("level", 0)
policy = data.get("policy", "")
if enabled and level:
    print(f"CSP 已启用，等级 {level}")
    print(f"策略: {policy}")
else:
    print("CSP 当前禁用")
PY
    else
        log_info "CSP 当前禁用"
    fi
}

show_modsecurity_status() {
    local json
    json=$(KEY_PATH="nginx:modsecurity" PILLAR_FILE="${PILLAR_FILE}" read_pillar_value "nginx:modsecurity")
    if [[ -n "$json" ]]; then
        JSON_DATA="$json" python3 - <<'PY'
import json, os
data = json.loads(os.environ.get("JSON_DATA", "{}"))
enabled = data.get("enabled", False)
level = data.get("level", 0)
admin_path = data.get("admin_path", "/admin")
if enabled and level:
    print(f"ModSecurity 已启用，等级 {level}，后台路径 {admin_path}")
else:
    print("ModSecurity 当前禁用")
PY
    else
        log_info "ModSecurity 当前禁用"
    fi
}

handle_csp_command() {
    local sub="${1:-}"
    case "$sub" in
        level)
            local level="${2:-}"
            if [[ -z "$level" ]]; then
                log_error "用法: saltgoat nginx csp level <0-5>"
                return 1
            fi
            if [[ "$level" == "0" ]]; then
                CSP_LEVEL=0 CSP_ENABLED=0 python_update csp_level
                log_success "已禁用 CSP"
            else
                if ! get_csp_policy "$level" >/dev/null; then
                    log_error "不支持的 CSP 等级: $level (仅 1-5，可用 0 禁用)"
                    return 1
                fi
                CSP_LEVEL="$level" CSP_ENABLED=1 python_update csp_level
                log_success "已设置 CSP 等级为 $level"
            fi
            cmd_apply
            ;;
        disable)
            CSP_LEVEL=0 CSP_ENABLED=0 python_update csp_level
            log_success "已禁用 CSP"
            cmd_apply
            ;;
        status|"")
            show_csp_status
            ;;
        *)
            log_error "未知的 CSP 操作: $sub"
            log_info "支持的操作: level <0-5>, disable, status"
            return 1
            ;;
    esac
}

handle_modsecurity_command() {
    local sub="${1:-}"
    case "$sub" in
        level)
            local level="${2:-}"
            local admin_path=""
            local -a args=("${@:3}")
            local i=0
            while [[ $i -lt ${#args[@]} ]]; do
                case "${args[$i]}" in
                    --admin-path)
                        ((i++))
                        if (( i >= ${#args[@]} )); then
                            log_error "--admin-path 需要指定路径"
                            return 1
                        fi
                        admin_path="${args[$i]}"
                        ;;
                    *)
                        log_warning "忽略未知参数: ${args[$i]}"
                        ;;
                esac
                ((i++))
            done
            if [[ -z "$level" ]]; then
                log_error "用法: saltgoat nginx modsecurity level <0-10> [--admin-path /admin]"
                return 1
            fi
            if [[ -z "$admin_path" ]]; then
                admin_path=$(detect_magento_admin_path)
                if [[ "$admin_path" != "/admin" ]]; then
                    log_info "自动检测 Magento 后台路径: ${admin_path}"
                else
                    log_info "未检测到 Magento 后台路径，使用默认 /admin_tattoo"
                fi
            fi
            if [[ "$level" == "0" ]]; then
                MODSEC_LEVEL=0 MODSEC_ENABLED=0 MODSEC_ADMIN_PATH="$admin_path" python_update modsecurity_level
                log_success "已禁用 ModSecurity"
                cmd_apply
                return $?
            fi
            if ! [[ "$level" =~ ^[0-9]+$ ]] || ((level < 1 || level > 10)); then
                log_error "ModSecurity 等级需为 1-10，或使用 0 禁用"
                return 1
            fi
            MODSEC_LEVEL="$level" MODSEC_ENABLED=1 MODSEC_ADMIN_PATH="$admin_path" python_update modsecurity_level
            if ! cmd_apply; then
                log_error "core.nginx 状态应用失败，ModSecurity 未成功启用。"
                MODSEC_LEVEL=0 MODSEC_ENABLED=0 MODSEC_ADMIN_PATH="$admin_path" python_update modsecurity_level
                log_warning "已将 Pillar 回退为禁用状态，请先解决依赖再重试。"
                return 1
            fi
            if nginx_supports_modsecurity; then
                log_success "已设置 ModSecurity 等级为 $level，后台路径 ${admin_path}"
            else
                log_warning "未检测到 Nginx ModSecurity 模块，请确认 libnginx-mod-http-modsecurity 已安装并在 nginx.conf 中 load_module。"
            fi
            ;;
        disable)
            MODSEC_LEVEL=0 MODSEC_ENABLED=0 python_update modsecurity_level
            log_success "已禁用 ModSecurity"
            cmd_apply
            ;;
        status|"")
            show_modsecurity_status
            ;;
        *)
            log_error "未知的 ModSecurity 操作: $sub"
            log_info "支持的操作: level <0-10> [--admin-path], disable, status"
            return 1
            ;;
    esac
}

cmd_apply() {
    ensure_sites_exist
    log_highlight "应用 core.nginx 状态..."
    if run_salt_call state.apply core.nginx; then
        log_success "core.nginx 状态应用完成。"
    else
        log_error "套用 core.nginx 状态失败，请检查上方 salt-call 输出。"
        return 1
    fi
}

cmd_reload() {
    log_highlight "重载 Nginx 服务..."
    if run_salt_call service.reload nginx; then
        log_success "Nginx 已重载。"
    else
        log_error "Nginx 重载失败。"
        return 1
    fi
}

cmd_test() {
    log_highlight "执行 nginx -t 配置测试..."
    if run_salt_call cmd.run 'nginx -t -c /etc/nginx/nginx.conf'; then
        log_success "nginx -t 测试通过。"
    else
        log_error "nginx 配置测试失败。"
        return 1
    fi
}

cmd_create() {
    local site="$1"
    local domains="$2"
    local root_path="${3:-}"
    local magento_flag="${4:-0}"
    ensure_pillar_file
    MAGENTO_FLAG="$magento_flag" python_update create "$site" "$domains" "$root_path"
    log_success "站点 ${site} 已写入 pillar。"
    cmd_apply
}

cmd_delete() {
    local site="$1"
    ensure_pillar_file
    python_update delete "$site"
    log_success "已移除站点 ${site}。"
    cleanup_site_files "$site"
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
  saltgoat nginx create <站点> "<域名 ...>" [根目录|--root <路径>] [--magento]
  saltgoat nginx delete <站点>
  saltgoat nginx enable <站点>
  saltgoat nginx disable <站点>
  saltgoat nginx add-ssl <站点> [域名] [email]
  saltgoat nginx csp level <0-5>           # 设置/禁用 CSP 等级
  saltgoat nginx csp status|disable
  saltgoat nginx modsecurity level <0-10> [--admin-path /admin]
  saltgoat nginx modsecurity status|disable
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
            if [[ -z "$site" || -z "$domains" ]]; then
                log_error "用法: saltgoat nginx create <站点> \"<域名 ...>\" [根目录|--root <路径>] [--magento]"
                exit 1
            fi
            local root=""
            local magento_flag=0
            shift 3
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --magento)
                        magento_flag=1
                        ;;
                    --root)
                        shift
                        if [[ $# -eq 0 ]]; then
                            log_error "--root 需要指定路径"
                            exit 1
                        fi
                        root="$1"
                        ;;
                    *)
                        if [[ -z "$root" ]]; then
                            root="$1"
                        else
                            log_warning "忽略未知参数: $1"
                        fi
                        ;;
                esac
                shift
            done
            cmd_create "$site" "$domains" "$root" "$magento_flag"
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
            handle_modsecurity_command "${@:2}"
            ;;
        csp)
            handle_csp_command "${@:2}"
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

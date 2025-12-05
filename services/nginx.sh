#!/bin/bash
# Nginx 管理入口（Salt 原生状态封装）

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"
PILLAR_FILE="${PROJECT_ROOT}/salt/pillar/nginx.sls"
NGINX_CONTEXT="${PROJECT_ROOT}/modules/lib/nginx_context.py"
NGINX_PILLAR_HELPER="${PROJECT_ROOT}/modules/lib/nginx_pillar.py"

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
    if ! roots=$(pillar_cli magento-roots 2>/dev/null); then
        roots=""
    fi
    local default_path="/admin_tattoo"
    local root
    while IFS= read -r root; do
        [[ -z "$root" ]] && continue
        local env_path="${root%/}/app/etc/env.php"
        if [[ -f "$env_path" ]]; then
            local front_name
            # shellcheck disable=SC2016
            if [[ $EUID -ne 0 ]]; then
                front_name=$(sudo env "MAGENTO_ENV_PATH=$env_path" php -r 'error_reporting(0); $app = @include getenv("MAGENTO_ENV_PATH"); if (is_array($app) && isset($app["backend"]["frontName"])) echo $app["backend"]["frontName"];' 2>/dev/null || true)
            else
                # shellcheck disable=SC2016
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

is_stub_certificate() {
    local cert_path="$1"
    if [[ ! -f "$cert_path" ]]; then
        return 1
    fi
    if ! command -v openssl >/dev/null 2>&1; then
        return 1
    fi
    local metadata
    if ! metadata=$(openssl x509 -noout -subject -issuer -in "$cert_path" 2>/dev/null); then
        return 1
    fi
    if grep -qi 'saltgoat\.local' <<<"$metadata"; then
        return 0
    fi
    return 1
}

ensure_ssl_certificate() {
    local site="$1"
    local override_domain="${2:-}"

    local info_env
    if ! info_env=$(pillar_cli site-info --site "$site" --format env 2>/dev/null); then
        info_env=""
    fi

    if [[ -z "$info_env" ]]; then
        log_warning "站点 ${site} 配置信息为空，跳过证书申请。"
        return 1
    fi

    local fallback_root=""
    local magento_flag="0"
    local ssl_email=""
    local configured_webroot=""
    local domains_csv=""
    while IFS='=' read -r key value; do
        case "$key" in
            root) fallback_root="$value" ;;
            domains) domains_csv="$value" ;;
            email) ssl_email="$value" ;;
            magento) magento_flag="$value" ;;
            ssl_webroot) configured_webroot="$value" ;;
        esac
    done <<<"$info_env"

    local root_path=""
    if [[ -n "$configured_webroot" ]]; then
        root_path="$configured_webroot"
    elif [[ "$magento_flag" == "1" ]]; then
        root_path="${fallback_root%/}/pub"
    else
        root_path="$fallback_root"
    fi

    if [[ -z "$root_path" ]]; then
        root_path="/var/www/${site}"
    fi

    local -a domains=()
    if [[ -n "$domains_csv" ]]; then
        IFS=',' read -ra domains <<<"$domains_csv"
    fi

    if [[ -n "$override_domain" ]]; then
        local sanitized="${override_domain//,/ }"
        local -a override_list=()
        read -ra override_list <<<"$sanitized"
        for (( idx=${#override_list[@]}-1; idx>=0; idx-- )); do
            local od="${override_list[idx]}"
            [[ -z "$od" ]] && continue
            domains=("$od" "${domains[@]}")
        done
    fi

    # 去重，保留顺序
    local -a unique=()
    declare -A seen=()
    local d
    for d in "${domains[@]}"; do
        [[ -z "$d" ]] && continue
        if [[ -z "${seen[$d]:-}" ]]; then
            unique+=("$d")
            seen["$d"]=1
        fi
    done
    domains=("${unique[@]}")

    local primary="${domains[0]:-}"
    if [[ -z "$primary" ]]; then
        log_warning "未找到可用域名，跳过自动申请证书。"
        return 0
    fi

    local cert_dir="/etc/letsencrypt/live/${primary}"
    local cert_path="${cert_dir}/fullchain.pem"
    local key_path="${cert_dir}/privkey.pem"
    if [[ -f "$cert_path" ]]; then
        if is_stub_certificate "$cert_path"; then
            log_warning "检测到 ${primary} 使用占位自签证书 (${cert_path})，将重新申请 Let's Encrypt。"
            rm -f "$cert_path" "$key_path" 2>/dev/null || true
        else
            log_info "检测到现有证书: ${cert_path}"
            return 0
        fi
    fi

    log_highlight "未检测到 ${primary} 的证书，尝试自动申请 Let's Encrypt 证书..."

    if ! run_salt_call state.apply nginx.acme_helper pillar="{'nginx': {'current_site': '$site'}}"; then
        log_error "配置 ACME 路径失败。"
        return 1
    fi

    if ! run_salt_call state.apply optional.certbot; then
        log_error "安装/配置 Certbot 失败。"
        return 1
    fi

    local -a certbot_cmd=(certbot certonly --webroot -w "$root_path")
    for d in "${domains[@]}"; do
        certbot_cmd+=(-d "$d")
    done
    if [[ -n "$ssl_email" && "$ssl_email" == *@* && "$ssl_email" != -* ]]; then
        certbot_cmd+=(--email "$ssl_email")
    else
        log_warning "未检测到有效的 SSL 邮箱地址，使用 --register-unsafely-without-email。"
        certbot_cmd+=(--register-unsafely-without-email)
    fi
    certbot_cmd+=(--agree-tos --non-interactive --keep-until-expiring --expand)

    if [[ $EUID -ne 0 ]]; then
        certbot_cmd=(sudo "${certbot_cmd[@]}")
    fi

    if "${certbot_cmd[@]}"; then
        log_success "已成功申请证书: ${primary}"
        return 0
    fi

    log_error "自动申请证书失败，请检查域名解析、80 端口及 Certbot 日志后重试。"
    return 1
}

pillar_cli() {
    python3 "$NGINX_PILLAR_HELPER" --pillar "$PILLAR_FILE" "$@"
}

ensure_sites_exist() {
    ensure_pillar_file
    pillar_cli list >/dev/null
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
    json="$(pillar_cli get --key 'nginx:csp' 2>/dev/null || true)"
    if [[ -n "$json" ]]; then
        JSON_DATA="$json" python3 "$NGINX_CONTEXT" csp-status
    else
        log_info "CSP 当前禁用"
    fi
}

show_modsecurity_status() {
    local json
    json="$(pillar_cli get --key 'nginx:modsecurity' 2>/dev/null || true)"
    if [[ -n "$json" ]]; then
        JSON_DATA="$json" python3 "$NGINX_CONTEXT" modsecurity-status
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
                pillar_cli csp-level --level 0 --enabled 0
                log_success "已禁用 CSP"
            else
                if ! get_csp_policy "$level" >/dev/null; then
                    log_error "不支持的 CSP 等级: $level (仅 1-5，可用 0 禁用)"
                    return 1
                fi
                pillar_cli csp-level --level "$level" --enabled 1
                log_success "已设置 CSP 等级为 $level"
            fi
            cmd_apply
            ;;
        disable)
            pillar_cli csp-level --level 0 --enabled 0
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
                pillar_cli modsecurity-level --level 0 --enabled 0 --admin-path "$admin_path"
                log_success "已禁用 ModSecurity"
                cmd_apply
                return $?
            fi
            if ! [[ "$level" =~ ^[0-9]+$ ]] || ((level < 1 || level > 10)); then
                log_error "ModSecurity 等级需为 1-10，或使用 0 禁用"
                return 1
            fi
            pillar_cli modsecurity-level --level "$level" --enabled 1 --admin-path "$admin_path"
            if ! cmd_apply; then
                log_error "core.nginx 状态应用失败，ModSecurity 未成功启用。"
                pillar_cli modsecurity-level --level 0 --enabled 0 --admin-path "$admin_path"
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
            pillar_cli modsecurity-level --level 0 --enabled 0 --admin-path "$(detect_magento_admin_path)"
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
    local domains_arg="$2"
    local root_path="${3:-}"
    local magento_flag="${4:-0}"
    local php_pool="${5:-}"
    local php_fastcgi="${6:-}"
    local magento_run_type="${7:-}"
    local magento_run_code="${8:-}"
    local magento_run_mode="${9:-}"
    ensure_pillar_file
    local normalized_domains="${domains_arg//,/ }"
    local -a domains=()
    read -ra domains <<<"$normalized_domains"
    if (( ${#domains[@]} == 0 )); then
        log_error "请至少提供一个域名。"
        return 1
    fi
    local -a args=(create --site "$site" --domains)
    args+=("${domains[@]}")
    if [[ -n "$root_path" ]]; then
        args+=("--root" "$root_path")
    fi
    if [[ "$magento_flag" == "1" ]]; then
        args+=("--magento")
    fi
    if [[ -n "$magento_run_type" ]]; then
        args+=("--magento-run-type" "$magento_run_type")
    fi
    if [[ -n "$magento_run_code" ]]; then
        args+=("--magento-run-code" "$magento_run_code")
    fi
    if [[ -n "$magento_run_mode" ]]; then
        args+=("--magento-run-mode" "$magento_run_mode")
    fi
    if [[ -n "$php_pool" ]]; then
        args+=("--php-pool" "$php_pool")
    fi
    if [[ -n "$php_fastcgi" ]]; then
        args+=("--php-fastcgi" "$php_fastcgi")
    fi
    pillar_cli "${args[@]}"
    log_success "站点 ${site} 已写入 pillar。"
    cmd_apply
}

cmd_delete() {
    local site="$1"
    ensure_pillar_file
    pillar_cli delete --site "$site"
    log_success "已移除站点 ${site}。"
    cleanup_site_files "$site"
    cmd_apply
}

cmd_enable_disable() {
    local action="$1"
    local site="$2"
    ensure_pillar_file
    pillar_cli "$action" --site "$site"
    log_success "站点 ${site} 已标记为 ${action}。"
    cmd_apply
}

cmd_list() {
    ensure_pillar_file
    pillar_cli list
}

cmd_ssl() {
    local site="$1"
    local domain="${2:-}"
    local email="${3:-}"
    local dry_run="${4:-0}"
    ensure_pillar_file
    local -a args=(ssl --site "$site")
    if [[ -n "$domain" ]]; then
        local sanitized="${domain//,/ }"
        local -a domain_tokens=()
        read -ra domain_tokens <<<"$sanitized"
        if (( ${#domain_tokens[@]} > 0 )); then
            args+=("--domain" "${domain_tokens[0]}")
        fi
    fi
    [[ -n "$email" ]] && args+=("--email" "$email")
    pillar_cli "${args[@]}"
    log_info "已更新站点 ${site} 的 SSL 信息。"
    if [[ "$dry_run" == "1" ]]; then
        log_info "Dry run 模式：仅写入 Pillar，已跳过证书申请与 core.nginx 状态套用。"
        return 0
    fi
    if ! ensure_ssl_certificate "$site" "$domain"; then
        log_warning "证书申请失败，已跳过 core.nginx 状态套用。"
        return 1
    fi
    cmd_apply
}

nginx_cli_help() {
    cat <<'EOF'
用法:
  saltgoat nginx apply                     # 套用 core.nginx Salt 状态
  saltgoat nginx list                      # 查看所有站点
  saltgoat nginx create --site <站点> --domain <域名 ...> [--root <路径>] [--magento]
  saltgoat nginx delete <站点>
  saltgoat nginx enable <站点>
  saltgoat nginx disable <站点>
  saltgoat nginx add-ssl --site <站点> [--domain <域名 ...>] [--email <邮箱>] [--dry-run]
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
            shift
            local site=""
            local -a domains_input=()
            local root=""
            local magento_flag=0
            local php_pool=""
            local php_fastcgi=""
            local magento_run_type=""
            local magento_run_code=""
            local magento_run_mode=""
            local -a leftover=()
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --site)
                        site="${2:-}"
                        shift 2
                        ;;
                    --site=*)
                        site="${1#*=}"
                        shift
                        ;;
                    --domains)
                        domains_input+=("${2:-}")
                        shift 2
                        ;;
                    --domains=*)
                        domains_input+=("${1#*=}")
                        shift
                        ;;
                    --domain)
                        shift
                        while [[ $# -gt 0 ]]; do
                            local possible="$1"
                            if [[ -z "$possible" ]]; then
                                shift
                                continue
                            fi
                            if [[ "$possible" == -* ]]; then
                                break
                            fi
                            domains_input+=("$possible")
                            shift
                        done
                        continue
                        ;;
                    --domain=*)
                        domains_input+=("${1#*=}")
                        shift
                        ;;
                    --magento)
                        magento_flag=1
                        shift
                        ;;
                    --root)
                        root="${2:-}"
                        shift 2
                        ;;
                    --root=*)
                        root="${1#*=}"
                        shift
                        ;;
                    --php-pool)
                        php_pool="${2:-}"
                        shift 2
                        ;;
                    --php-pool=*)
                        php_pool="${1#*=}"
                        shift
                        ;;
                    --php-fastcgi)
                        php_fastcgi="${2:-}"
                        shift 2
                        ;;
                    --php-fastcgi=*)
                        php_fastcgi="${1#*=}"
                        shift
                        ;;
                    --magento-run-type)
                        magento_run_type="${2:-}"
                        shift 2
                        ;;
                    --magento-run-type=*)
                        magento_run_type="${1#*=}"
                        shift
                        ;;
                    --magento-run-code)
                        magento_run_code="${2:-}"
                        shift 2
                        ;;
                    --magento-run-code=*)
                        magento_run_code="${1#*=}"
                        shift
                        ;;
                    --magento-run-mode)
                        magento_run_mode="${2:-}"
                        shift 2
                        ;;
                    --magento-run-mode=*)
                        magento_run_mode="${1#*=}"
                        shift
                        ;;
                    *)
                        leftover+=("$1")
                        shift
                        ;;
                esac
            done
            if [[ -z "$site" && ${#leftover[@]} -ge 1 ]]; then
                site="${leftover[0]}"
            fi
            if [[ ${#domains_input[@]} -eq 0 && ${#leftover[@]} -ge 2 ]]; then
                domains_input+=("${leftover[1]}")
            fi
            if [[ -z "$root" && ${#leftover[@]} -ge 3 ]]; then
                root="${leftover[2]}"
            fi
            if [[ -z "$site" || ${#domains_input[@]} -eq 0 ]]; then
                log_error "用法: saltgoat nginx create --site <站点> --domain <域名...> [--root <路径>] [--magento]"
                exit 1
            fi
            local domains_arg="${domains_input[*]}"
            cmd_create "$site" "$domains_arg" "$root" "$magento_flag" "$php_pool" "$php_fastcgi" "$magento_run_type" "$magento_run_code" "$magento_run_mode"
            ;;
        delete)
            shift
            local site=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --site)
                        site="${2:-}"
                        shift 2
                        ;;
                    --site=*)
                        site="${1#*=}"
                        shift
                        ;;
                    *)
                        if [[ -z "$site" ]]; then
                            site="$1"
                        fi
                        shift
                        ;;
                esac
            done
            if [[ -z "$site" ]]; then
                log_error "用法: saltgoat nginx delete --site <站点>"
                exit 1
            fi
            cmd_delete "$site"
            ;;
        enable|disable)
            shift
            local site=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --site)
                        site="${2:-}"
                        shift 2
                        ;;
                    --site=*)
                        site="${1#*=}"
                        shift
                        ;;
                    *)
                        if [[ -z "$site" ]]; then
                            site="$1"
                        fi
                        shift
                        ;;
                esac
            done
            if [[ -z "$site" ]]; then
                log_error "用法: saltgoat nginx $action --site <站点>"
                exit 1
            fi
            cmd_enable_disable "$action" "$site"
            ;;
        add-ssl)
            shift
            local site=""
            local -a override_domains=()
            local email=""
            local dry_run=0
            local -a leftover_ssl=()
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --site)
                        site="${2:-}"
                        shift 2
                        ;;
                    --site=*)
                        site="${1#*=}"
                        shift
                        ;;
                    --domains)
                        override_domains+=("${2:-}")
                        shift 2
                        ;;
                    --domains=*)
                        override_domains+=("${1#*=}")
                        shift
                        ;;
                    --domain)
                        shift
                        while [[ $# -gt 0 ]]; do
                            local next="$1"
                            if [[ -z "$next" ]]; then
                                shift
                                continue
                            fi
                            if [[ "$next" == -* ]]; then
                                break
                            fi
                            override_domains+=("$next")
                            shift
                        done
                        continue
                        ;;
                    --domain=*)
                        override_domains+=("${1#*=}")
                        shift
                        ;;
                    --email)
                        email="${2:-}"
                        shift 2
                        ;;
                    --email=*)
                        email="${1#*=}"
                        shift
                        ;;
                    -dry-on|--dry-run)
                        dry_run=1
                        shift
                        ;;
                    -*)
                        log_warning "忽略未知参数: $1"
                        shift
                        ;;
                    *)
                        leftover_ssl+=("$1")
                        shift
                        ;;
                esac
            done
            if [[ -z "$site" && ${#leftover_ssl[@]} -ge 1 ]]; then
                site="${leftover_ssl[0]}"
            fi
            if [[ ${#override_domains[@]} -eq 0 && ${#leftover_ssl[@]} -ge 2 ]]; then
                override_domains+=("${leftover_ssl[1]}")
            fi
            if [[ -z "$email" && ${#leftover_ssl[@]} -ge 3 ]]; then
                email="${leftover_ssl[2]}"
            fi
            if [[ -z "$site" ]]; then
                log_error "用法: saltgoat nginx add-ssl --site <站点> [--domain <域名...>] [--email addr] [--dry-run]"
                exit 1
            fi
            local domain_override="${override_domains[*]}"
            cmd_ssl "$site" "$domain_override" "$email" "$dry_run"
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

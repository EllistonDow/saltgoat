#!/bin/bash
# Magento 多站点创建/回滚助手
# Usage: saltgoat magetools multisite <action> [options]

set -euo pipefail

: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
MONITORING_HELPER="${SCRIPT_DIR}/modules/lib/monitoring_sites.py"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"

ACTION="${1:-}"
shift || true

ROOT_SITE=""
STORE_CODE=""
DOMAIN=""
STORE_NAME=""
WEBSITE_CODE=""
GROUP_CODE=""
LOCALE="en_US"
CURRENCY="USD"
ROOT_CATEGORY_ID="2"
DRY_RUN=0
SKIP_VARNISH=0
SKIP_NGINX=0
SKIP_SSL=0
NGINX_SITE=""
SSL_EMAIL=""
RUN_DEPLOY=0

SALTGOAT_BIN="${SCRIPT_DIR}/saltgoat"
MONITORING_PILLAR_FILE="${SCRIPT_DIR}/salt/pillar/monitoring.sls"
PHP_POOL_HELPER="${SCRIPT_DIR}/modules/lib/php_pool_helper.py"
PHP_POOL_PILLAR="${SCRIPT_DIR}/salt/pillar/magento-optimize.sls"
ADJUST_PHP_POOL=1
PHP_POOL_WEIGHT=""
PHP_POOL_BASE_WEIGHT=1
PHP_POOL_PER_STORE=1
PHP_POOL_MAX_WEIGHT=""
PHP_FPM_VERSION="8.3"
PHP_POOL_MAX_CHILDREN=12
PHP_POOL_START_SERVERS=6
PHP_POOL_MIN_SPARE=4
PHP_POOL_MAX_SPARE=8

usage() {
    cat <<'EOF'
Magento 多站点自动化

用法:
  saltgoat magetools multisite <create|rollback|status> --site <root_site> --code <store_code> --domain <fqdn> [选项]

常用选项:
  --site <root_site>         已部署的 Magento 根站点目录名称（例如 bank）
  --code <store_code>        新建 Store View 的代码（将自动派生 website/group 代码）
  --domain <fqdn>            新域名（用于 base_url），会自动补全为 https://<fqdn>/
  --store-name <name>        Store View 名称，默认使用域名
  --website-code <code>      自定义 Website code（默认: <store_code>_ws）
  --group-code <code>        自定义 Store Group code（默认: <store_code>_grp）
  --locale <en_US>           Store View 语言（默认: en_US）
  --currency <USD>           Store View 货币（默认: USD）
  --root-category <id>       Store Group 根分类 ID（默认: 2）
  --dry-run                  仅打印计划，不执行改动
  --skip-varnish             不尝试自动调整 Varnish
  --skip-nginx               跳过自动创建/删除 Nginx 站点与证书
  --skip-ssl                 跳过自动申请/续期 SSL 证书
  --ssl-email <email>        指定证书申请邮箱（缺省时尝试从 Pillar 获取）
  --nginx-site <name>        自定义 Nginx 站点标识（默认同 --code）
  --run-deploy               创建完成后执行 Magento 部署流程（静态资源/索引等）
  --adjust-php-pool          （默认）启用 PHP-FPM 池自动扩容逻辑
  --no-adjust-php-pool       禁用 PHP-FPM 池自动扩容
  --php-pool-weight <int>    指定池 weight（跳过自动计算）
  --php-pool-base-weight <int>  自动计算的最小 weight（默认 1）
  --php-pool-per-store <int> 每个 Store 叠加的 weight（默认 1）
  --php-pool-max-weight <int>   weight 上限
  --skip-pillar              (兼容参数) 等同 --skip-nginx
  -h, --help                 显示帮助

示例:
  saltgoat magetools multisite create --site bank --code duobank --domain duobank.magento.tattoogoat.com
  saltgoat magetools multisite status --site bank --code duobank --domain duobank.magento.tattoogoat.com
  saltgoat magetools multisite rollback --site bank --code duobank --domain duobank.magento.tattoogoat.com
EOF
}

if [[ -z "$ACTION" || "$ACTION" == "--help" || "$ACTION" == "-h" ]]; then
    usage
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --site)
            if [[ $# -lt 2 ]]; then
                log_error "--site 需要一个参数值，例如 --site bank"
                exit 1
            fi
            ROOT_SITE="$2"
            shift 2
            ;;
        --code)
            if [[ $# -lt 2 ]]; then
                log_error "--code 需要一个参数值，例如 --code duobank"
                exit 1
            fi
            STORE_CODE="$2"
            shift 2
            ;;
        --domain)
            if [[ $# -lt 2 ]]; then
                log_error "--domain 需要一个参数值，例如 --domain example.com"
                exit 1
            fi
            DOMAIN="$2"
            shift 2
            ;;
        --store-name)
            if [[ $# -lt 2 ]]; then
                log_error "--store-name 需要一个参数值"
                exit 1
            fi
            STORE_NAME="$2"
            shift 2
            ;;
        --website-code)
            if [[ $# -lt 2 ]]; then
                log_error "--website-code 需要一个参数值"
                exit 1
            fi
            WEBSITE_CODE="$2"
            shift 2
            ;;
        --group-code)
            if [[ $# -lt 2 ]]; then
                log_error "--group-code 需要一个参数值"
                exit 1
            fi
            GROUP_CODE="$2"
            shift 2
            ;;
        --locale)
            if [[ $# -lt 2 ]]; then
                log_error "--locale 需要一个参数值"
                exit 1
            fi
            LOCALE="$2"
            shift 2
            ;;
        --currency)
            if [[ $# -lt 2 ]]; then
                log_error "--currency 需要一个参数值"
                exit 1
            fi
            CURRENCY="$2"
            shift 2
            ;;
        --root-category)
            if [[ $# -lt 2 ]]; then
                log_error "--root-category 需要一个参数值"
                exit 1
            fi
            ROOT_CATEGORY_ID="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --skip-varnish)
            SKIP_VARNISH=1
            shift
            ;;
        --skip-nginx)
            SKIP_NGINX=1
            shift
            ;;
        --skip-ssl)
            SKIP_SSL=1
            shift
            ;;
        --run-deploy)
            RUN_DEPLOY=1
            shift
            ;;
        --adjust-php-pool)
            ADJUST_PHP_POOL=1
            shift
            ;;
        --no-adjust-php-pool)
            ADJUST_PHP_POOL=0
            shift
            ;;
        --php-pool-weight)
            if [[ $# -lt 2 ]]; then
                log_error "--php-pool-weight 需要一个整数参数"
                exit 1
            fi
            if [[ "$2" =~ ^[0-9]+$ ]]; then
                PHP_POOL_WEIGHT="$2"
            else
                log_error "--php-pool-weight 必须是整数"
                exit 1
            fi
            shift 2
            ;;
        --php-pool-base-weight)
            if [[ $# -lt 2 || ! "$2" =~ ^[0-9]+$ ]]; then
                log_error "--php-pool-base-weight 需要整数参数"
                exit 1
            fi
            PHP_POOL_BASE_WEIGHT="$2"
            shift 2
            ;;
        --php-pool-per-store)
            if [[ $# -lt 2 || ! "$2" =~ ^[0-9]+$ ]]; then
                log_error "--php-pool-per-store 需要整数参数"
                exit 1
            fi
            PHP_POOL_PER_STORE="$2"
            shift 2
            ;;
        --php-pool-max-weight)
            if [[ $# -lt 2 || ! "$2" =~ ^[0-9]+$ ]]; then
                log_error "--php-pool-max-weight 需要整数参数"
                exit 1
            fi
            PHP_POOL_MAX_WEIGHT="$2"
            shift 2
            ;;
        --ssl-email)
            if [[ $# -lt 2 ]]; then
                log_error "--ssl-email 需要一个参数值"
                exit 1
            fi
            SSL_EMAIL="$2"
            shift 2
            ;;
        --nginx-site)
            if [[ $# -lt 2 ]]; then
                log_error "--nginx-site 需要一个参数值"
                exit 1
            fi
            NGINX_SITE="$2"
            shift 2
            ;;
        --skip-pillar)
            SKIP_NGINX=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            log_error "未知参数: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$ROOT_SITE" ]]; then
    log_error "请使用 --site 指定现有站点目录"
    exit 1
fi

if [[ -z "$STORE_CODE" ]]; then
    log_error "请使用 --code 指定新的 Store View code"
    exit 1
fi

if [[ -z "$DOMAIN" ]]; then
    log_error "请使用 --domain 指定新域名"
    exit 1
fi

sanitize_code() {
    local raw="$1"
    echo "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_]/_/g'
}

STORE_CODE="$(sanitize_code "$STORE_CODE")"
if [[ -z "$STORE_NAME" ]]; then
    STORE_NAME="${DOMAIN}"
fi

if [[ -z "$WEBSITE_CODE" ]]; then
    WEBSITE_CODE="$(sanitize_code "${STORE_CODE}_ws")"
fi

if [[ -z "$GROUP_CODE" ]]; then
    GROUP_CODE="$(sanitize_code "${STORE_CODE}_grp")"
fi

if [[ -n "$NGINX_SITE" ]]; then
    NGINX_SITE="$(sanitize_code "$NGINX_SITE")"
else
    NGINX_SITE="$STORE_CODE"
fi

if [[ ! "$ROOT_CATEGORY_ID" =~ ^[0-9]+$ ]]; then
    log_warning "检测到无效的 root-category 值 (${ROOT_CATEGORY_ID})，已回退为 2。"
    ROOT_CATEGORY_ID="2"
fi

BASE_URL="https://${DOMAIN}/"
MAGENTO_ROOT="/var/www/${ROOT_SITE}"
MAGENTO_CURRENT="${MAGENTO_ROOT}"
if [[ ! -f "${MAGENTO_CURRENT}/bin/magento" ]]; then
    if [[ -d "${MAGENTO_ROOT}/current" && -f "${MAGENTO_ROOT}/current/bin/magento" ]]; then
        MAGENTO_CURRENT="${MAGENTO_ROOT}/current"
    fi
fi

if [[ ! -f "${MAGENTO_CURRENT}/bin/magento" ]]; then
    log_error "未找到 Magento CLI: ${MAGENTO_CURRENT}/bin/magento"
    exit 1
fi

MAGENTO_BOOTSTRAP="${MAGENTO_CURRENT}/app/bootstrap.php"

MAGENTO_COMMAND_CACHE=""

magento_cmd_build() {
    local -a args=("$@")
    local cmd="cd ${MAGENTO_CURRENT} && php bin/magento"
    local item
    for item in "${args[@]}"; do
        cmd+=" $(printf '%q' "$item")"
    done
    echo "$cmd"
}

run_magento_raw() {
    local cmd
    cmd="$(magento_cmd_build "$@")"
    sudo -u www-data -H bash -lc "$cmd"
}

run_magento_cmd() {
    local desc="$1"
    shift
    if (( DRY_RUN )); then
        log_info "[dry-run] ${desc}: bin/magento $*"
        return 0
    fi
    log_info "$desc"
    run_magento_raw "$@"
}

magento_load_command_cache() {
    if [[ -n "$MAGENTO_COMMAND_CACHE" ]]; then
        return
    fi
    local output
    output=$(sudo -u www-data -H bash -lc "cd ${MAGENTO_CURRENT} && php bin/magento list --raw" 2>/dev/null || true)
    MAGENTO_COMMAND_CACHE="$output"
}

magento_command_exists() {
    local cmd="$1"
    magento_load_command_cache
    if [[ -z "$MAGENTO_COMMAND_CACHE" ]]; then
        return 1
    fi
    printf '%s\n' "$MAGENTO_COMMAND_CACHE" | grep -Fx -- "$cmd" >/dev/null 2>&1
}

command_to_string() {
    local -a parts=("$@")
    local joined=""
    local part
    for part in "${parts[@]}"; do
        if [[ -z "$joined" ]]; then
            joined="$(printf '%q' "$part")"
        else
            joined+=" $(printf '%q' "$part")"
        fi
    done
    printf '%s' "$joined"
}

run_cli_command() {
    local desc="$1"
    shift
    local -a cmd=("$@")
    local rendered
    rendered="$(command_to_string "${cmd[@]}")"
    if (( DRY_RUN )); then
        log_info "[dry-run] ${desc}: ${rendered}"
        return 0
    fi
    log_info "$desc"
    if ! "${cmd[@]}"; then
        log_error "${desc} 失败，命令: ${rendered}"
        exit 1
    fi
}

determine_doc_root() {
    local candidate="${MAGENTO_CURRENT}/pub"
    if [[ -d "$candidate" ]]; then
        printf '%s' "$candidate"
    else
        printf '%s' "$MAGENTO_CURRENT"
    fi
}

nginx_site_available_path() {
    printf '/etc/nginx/sites-available/%s' "$NGINX_SITE"
}

nginx_site_exists() {
    [[ -f "$(nginx_site_available_path)" ]]
}

ssl_cert_path() {
    printf '/etc/letsencrypt/live/%s/fullchain.pem' "$DOMAIN"
}

ssl_cert_exists() {
    [[ -f "$(ssl_cert_path)" ]]
}

update_monitoring_pillar() {
    if [[ ! -f "$MONITORING_PILLAR_FILE" ]]; then
        log_warning "未找到监控 Pillar 文件: ${MONITORING_PILLAR_FILE}，已跳过。"
        return
    fi
    if (( DRY_RUN )); then
        log_info "[dry-run] 更新监控 Pillar: 追加站点 ${STORE_CODE} (${DOMAIN})."
        return
    fi
    if [[ -z "$DOMAIN" ]]; then
        log_warning "未提供 domain，跳过监控 Pillar 更新。"
        return
    fi
    sudo python3 "$MONITORING_HELPER" upsert \
        --file "$MONITORING_PILLAR_FILE" \
        --site "$STORE_CODE" \
        --domain "$DOMAIN"
    log_success "监控 Pillar 已更新: ${STORE_CODE} -> https://${DOMAIN}/"
}

remove_monitoring_entry() {
    if [[ ! -f "$MONITORING_PILLAR_FILE" ]]; then
        return
    fi
    if (( DRY_RUN )); then
        log_info "[dry-run] 从监控 Pillar 移除站点 ${STORE_CODE}."
        return
    fi
    sudo python3 "$MONITORING_HELPER" remove \
        --file "$MONITORING_PILLAR_FILE" \
        --site "$STORE_CODE"
    log_info "监控 Pillar 中已移除站点 ${STORE_CODE}."
}

apply_php_pool_state() {
    if (( DRY_RUN )); then
        log_info "[dry-run] 重新渲染 core.php Salt state。"
        return
    fi
    if ! sudo salt-call --local state.apply core.php >/dev/null; then
        log_warning "Salt core.php 状态失败，尝试直接重载 php${PHP_FPM_VERSION}-fpm。"
        sudo systemctl reload "php${PHP_FPM_VERSION}-fpm" || sudo systemctl restart "php${PHP_FPM_VERSION}-fpm"
    fi
}

php_pool_conf_path() {
    local pool_name="$1"
    printf '/etc/php/%s/fpm/pool.d/%s.conf' "$PHP_FPM_VERSION" "$pool_name"
}

php_pool_listen_path() {
    local pool_name="$1"
    printf '/run/php/php%s-fpm-%s.sock' "$PHP_FPM_VERSION" "$pool_name"
}

ensure_php_pool_conf() {
    local pool_name="$1"
    local conf_path
    conf_path=$(php_pool_conf_path "$pool_name")
    local listen_path
    listen_path=$(php_pool_listen_path "$pool_name")
    local slowlog_path="/var/log/php${PHP_FPM_VERSION}-fpm-${pool_name}.slow.log"
    if (( DRY_RUN )); then
        log_info "[dry-run] 写入 PHP-FPM 池配置 ${conf_path}"
        return 0
    fi
    sudo tee "$conf_path" >/dev/null <<EOF
[$pool_name]
user = www-data
group = www-data
listen = $listen_path
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = $PHP_POOL_MAX_CHILDREN
pm.start_servers = $PHP_POOL_START_SERVERS
pm.min_spare_servers = $PHP_POOL_MIN_SPARE
pm.max_spare_servers = $PHP_POOL_MAX_SPARE
pm.max_requests = 1500
ping.path = /ping
ping.response = pong
pm.status_path = /status
slowlog = $slowlog_path
request_slowlog_timeout = 10s
request_terminate_timeout = 330s
catch_workers_output = yes
chdir = /
clear_env = yes
php_admin_value[memory_limit] = 2048M
EOF
}

remove_php_pool_conf() {
    local pool_name="$1"
    local conf_path
    conf_path=$(php_pool_conf_path "$pool_name")
    if (( DRY_RUN )); then
        log_info "[dry-run] 删除 PHP-FPM 池配置 ${conf_path}"
        return
    fi
    sudo rm -f "$conf_path"
}

reload_php_fpm() {
    if (( DRY_RUN )); then
        log_info "[dry-run] reload php${PHP_FPM_VERSION}-fpm"
        return
    fi
    if ! sudo systemctl reload "php${PHP_FPM_VERSION}-fpm"; then
        log_warning "php${PHP_FPM_VERSION}-fpm reload 失败，尝试 restart"
        sudo systemctl restart "php${PHP_FPM_VERSION}-fpm"
    fi
}

adjust_php_pool() {
    local action="$1"
    if (( ADJUST_PHP_POOL == 0 )); then
        log_note "已跳过 PHP-FPM 池调整 (--no-adjust-php-pool)。"
        return
    fi
    if [[ ! -x "$PHP_POOL_HELPER" && ! -f "$PHP_POOL_HELPER" ]]; then
        log_warning "未找到 PHP 池 helper: ${PHP_POOL_HELPER}"
        return
    fi
    local apply_state=0
    local explicit_weight="${PHP_POOL_WEIGHT:-}"

    run_pool_helper() {
        local site_id="$1" pool_name="$2" primary_store="$3" store_code="$4" weight_arg="$5" helper_action="$6"
        local -a cmd=(
            sudo python3 "$PHP_POOL_HELPER" adjust
            --site "$site_id"
            --site-root "$MAGENTO_CURRENT"
            --pool-name "$pool_name"
            --pillar "$PHP_POOL_PILLAR"
            --primary-store "$primary_store"
            --action "$helper_action"
        )
        if [[ -n "$store_code" ]]; then
            cmd+=(--store-code "$store_code")
        fi
        if [[ -n "$weight_arg" ]]; then
            cmd+=(--set-weight "$weight_arg")
        else
            cmd+=(--base-weight "$PHP_POOL_BASE_WEIGHT" --per-store "$PHP_POOL_PER_STORE")
            if [[ -n "$PHP_POOL_MAX_WEIGHT" ]]; then
                cmd+=(--max-weight "$PHP_POOL_MAX_WEIGHT")
            fi
        fi
        if (( DRY_RUN )); then
            log_info "[dry-run] PHP-FPM 池 ${pool_name} (${site_id}) 将执行 ${helper_action}."
            return 0
        fi
        local out
        if ! out="$("${cmd[@]}")"; then
            log_error "PHP-FPM 池调整失败 (${pool_name})."
            return 1
        fi
        log_info "PHP 池状态(${pool_name}): ${out}"
        apply_state=1
        return 0
    }

    remove_pool_entry() {
        local site_id="$1"
        if (( DRY_RUN )); then
            log_info "[dry-run] 将从 Pillar 移除 PHP 池 ${site_id}."
            return
        fi
        sudo python3 - "$PHP_POOL_PILLAR" "$site_id" <<'PY'
import sys, yaml, pathlib
path = pathlib.Path(sys.argv[1])
site_id = sys.argv[2]
data = {}
if path.exists():
    data = yaml.safe_load(path.read_text()) or {}
if not isinstance(data, dict):
    data = {}
opt = data.get('magento_optimize', {}) or {}
sites = opt.get('sites', {}) or {}
if site_id in sites:
    sites.pop(site_id, None)
    opt['sites'] = sites
    data['magento_optimize'] = opt
    path.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False))
PY
        apply_state=1
    }

    if [[ -n "$STORE_CODE" && "$STORE_CODE" != "$ROOT_SITE" ]]; then
        run_pool_helper "$ROOT_SITE" "magento-${ROOT_SITE}" "$ROOT_SITE" "$STORE_CODE" "" "remove" || true
    fi
    run_pool_helper "$ROOT_SITE" "magento-${ROOT_SITE}" "$ROOT_SITE" "$ROOT_SITE" "$explicit_weight" "add" || true

    local store_pool_name="magento-${STORE_CODE}"
    local pool_conf_changed=0

    if [[ -n "$STORE_CODE" && "$STORE_CODE" != "$ROOT_SITE" ]]; then
        if [[ "$action" == "remove" ]]; then
            remove_pool_entry "$STORE_CODE"
            remove_php_pool_conf "$store_pool_name"
            pool_conf_changed=1
        else
            run_pool_helper "$STORE_CODE" "$store_pool_name" "$STORE_CODE" "$STORE_CODE" "$explicit_weight" "$action" || true
            ensure_php_pool_conf "$store_pool_name"
            pool_conf_changed=1
        fi
    fi

    if (( pool_conf_changed )); then
        reload_php_fpm
    fi

    if (( apply_state )); then
        if (( DRY_RUN )); then
            log_info "[dry-run] 将重新渲染 PHP-FPM 池。"
        else
            apply_php_pool_state
        fi
    fi
}

magento_cli() {
    local desc="$1"
    shift
    local cmd=("$@")
    local cmd_str=""
    if (( ${#cmd[@]} )); then
        printf -v cmd_str '%q ' "${cmd[@]}"
        cmd_str="${cmd_str% }"
    fi
    if (( DRY_RUN )); then
        log_info "[dry-run] ${desc}: ${cmd_str}"
        return
    fi
    run_cli_command "$desc" sudo -u www-data -H bash -lc "cd '${MAGENTO_CURRENT}' && ${cmd_str}"
}

run_deploy_tasks() {
    if (( RUN_DEPLOY == 0 )); then
        log_info "未启用部署流程 (--run-deploy 未设置)。"
        return
    fi

    local jobs
    jobs=$(nproc 2>/dev/null || echo 2)

    magento_cli "启用维护模式" "php bin/magento maintenance:enable"

    if (( ! DRY_RUN )); then
        run_cli_command "清理缓存目录" sudo bash -lc "cd '${MAGENTO_CURRENT}' && find var/cache var/page_cache var/view_preprocessed generated -mindepth 1 -delete"
        run_cli_command "清理静态目录" sudo bash -lc "cd '${MAGENTO_CURRENT}' && find pub/static -mindepth 1 ! -path '*/.htaccess' -delete"
        run_cli_command "清理媒体缓存" sudo bash -lc "cd '${MAGENTO_CURRENT}' && find pub/media/catalog/product/cache -mindepth 1 -delete"
        run_cli_command "重建 generated 目录" sudo bash -lc "cd '${MAGENTO_CURRENT}' && mkdir -p generated"
        run_cli_command "修正目录权限" sudo chown -R www-data:www-data "${MAGENTO_CURRENT}/generated" "${MAGENTO_CURRENT}/var" "${MAGENTO_CURRENT}/pub/static"
    else
        log_info "[dry-run] 清理缓存/静态/媒体目录"
    fi

    magento_cli "执行 setup:upgrade" "php bin/magento setup:upgrade"
    magento_cli "编译依赖注入" "php bin/magento setup:di:compile"
    magento_cli "部署静态资源" "php bin/magento setup:static-content:deploy -f en_US --jobs ${jobs}"
    magento_cli "重建索引" "php bin/magento indexer:reindex"
    magento_cli "关闭维护模式" "php bin/magento maintenance:disable"
    magento_cli "清理缓存" "php bin/magento cache:clean"
}

provision_nginx_and_ssl() {
    if (( SKIP_NGINX )); then
        log_note "已跳过 Nginx/SSL 自动化 (--skip-nginx)。"
        return
    fi

    local doc_root="$MAGENTO_CURRENT"
    if [[ -z "$doc_root" || ! -d "$doc_root" ]]; then
        doc_root="$(determine_doc_root)"
    fi
    local php_pool_name="magento-${STORE_CODE}"

    if nginx_site_exists; then
        log_warning "检测到现有 Nginx 站点 ${NGINX_SITE}，跳过创建。"
    else
        run_cli_command "创建 Nginx 站点 ${NGINX_SITE}" \
            "$SALTGOAT_BIN" nginx create "$NGINX_SITE" "$DOMAIN" --root "$doc_root" --magento \
            --magento-run-type website --magento-run-code "$WEBSITE_CODE" \
            --php-pool "$php_pool_name"
    fi

    if (( SKIP_SSL )); then
        log_note "已跳过 SSL 申请 (--skip-ssl)。"
        return
    fi

    local -a ssl_cmd=("$SALTGOAT_BIN" nginx add-ssl "$NGINX_SITE" "$DOMAIN")
    if [[ -n "$SSL_EMAIL" ]]; then
        ssl_cmd+=("$SSL_EMAIL")
    fi
    run_cli_command "申请/续期 SSL 证书 (${DOMAIN})" "${ssl_cmd[@]}"
}

cleanup_nginx_site() {
    if (( SKIP_NGINX )); then
        log_note "已跳过 Nginx 站点清理 (--skip-nginx)。"
        return
    fi

    if nginx_site_exists; then
        run_cli_command "删除 Nginx 站点 ${NGINX_SITE}" \
            "$SALTGOAT_BIN" nginx delete "$NGINX_SITE"
    else
        log_warning "未检测到 Nginx 站点 ${NGINX_SITE}，跳过删除。"
    fi
}

magento_eval() {
    local php_script="$1"
    [[ -f "$MAGENTO_BOOTSTRAP" ]] || return 1
    sudo -u www-data -H php <<PHP
<?php
require '${MAGENTO_BOOTSTRAP}';
\$bootstrap = \Magento\Framework\App\Bootstrap::create(BP, \$_SERVER);
\$objectManager = \$bootstrap->getObjectManager();
\$state = \$objectManager->get(\Magento\Framework\App\State::class);
try {
    \$state->setAreaCode('adminhtml');
} catch (\Magento\Framework\Exception\LocalizedException \$e) {
    // area already set
}
${php_script}
PHP
}

php_escape() {
    printf "%s" "$1" | sed "s/'/\\\\'/g"
}

get_entity_id() {
    local entity="$1"
    local code="$2"
    local entity_escaped
    entity_escaped=$(php_escape "$entity")
    local code_escaped
    code_escaped=$(php_escape "$code")
    local script
    read -r -d '' script <<PHP || true
\$entity = '${entity_escaped}';
\$code = '${code_escaped}';
\$id = 0;
switch (\$entity) {
    case 'website':
        \$model = \$objectManager->create(\Magento\Store\Model\Website::class);
        \$model->load(\$code, 'code');
        \$id = (int) \$model->getId();
        break;
    case 'store_group':
        \$model = \$objectManager->create(\Magento\Store\Model\Group::class);
        \$model->load(\$code, 'code');
        \$id = (int) \$model->getId();
        break;
    case 'store':
        \$model = \$objectManager->create(\Magento\Store\Model\Store::class);
        \$model->load(\$code, 'code');
        \$id = (int) \$model->getId();
        break;
}
echo \$id > 0 ? (string) \$id : "";
PHP
    magento_eval "$script" | tr -d $'\r'
}

check_website_exists() {
    local id
    id="$(get_entity_id "website" "$1")"
    [[ -n "$id" ]]
}

check_group_exists() {
    local id
    id="$(get_entity_id "store_group" "$1")"
    [[ -n "$id" ]]
}

check_store_exists() {
    local id
    id="$(get_entity_id "store" "$1")"
    [[ -n "$id" ]]
}

ensure_magento_entities_php() {
    local website_code_php store_name_php group_code_php store_code_php website_name_php
    website_code_php=$(php_escape "$WEBSITE_CODE")
    website_name_php=$(php_escape "$STORE_NAME")
    group_code_php=$(php_escape "$GROUP_CODE")
    store_code_php=$(php_escape "$STORE_CODE")
    store_name_php=$(php_escape "$STORE_NAME")

    local script
    script=$(cat <<PHP
try {
    /** @var \Magento\Store\Model\ResourceModel\Website \$websiteResource */
    \$websiteResource = \$objectManager->get(\Magento\Store\Model\ResourceModel\Website::class);
    /** @var \Magento\Store\Model\ResourceModel\Group \$groupResource */
    \$groupResource = \$objectManager->get(\Magento\Store\Model\ResourceModel\Group::class);
    /** @var \Magento\Store\Model\ResourceModel\Store \$storeResource */
    \$storeResource = \$objectManager->get(\Magento\Store\Model\ResourceModel\Store::class);

    /** @var \Magento\Store\Model\Website \$website */
    \$website = \$objectManager->create(\Magento\Store\Model\Website::class);
    \$websiteResource->load(\$website, '${website_code_php}', 'code');
    if (!\$website->getId()) {
        \$website->setCode('${website_code_php}');
        \$website->setName('${website_name_php}');
        \$website->setSortOrder(0);
        \$websiteResource->save(\$website);
        echo "Created website: ${WEBSITE_CODE}" . PHP_EOL;
    }
    \$websiteId = (int) \$website->getId();
    if (!\$websiteId) {
        throw new RuntimeException('无法获取 website ID');
    }

    /** @var \Magento\Store\Model\Group \$group */
    \$group = \$objectManager->create(\Magento\Store\Model\Group::class);
    \$groupResource->load(\$group, '${group_code_php}', 'code');
    if (!\$group->getId()) {
        \$group->setCode('${group_code_php}');
        \$group->setName('${store_name_php}');
        \$group->setWebsiteId(\$websiteId);
        \$group->setRootCategoryId(${ROOT_CATEGORY_ID});
        \$groupResource->save(\$group);
        echo "Created store group: ${GROUP_CODE}" . PHP_EOL;
    } else {
        \$needsSave = false;
        if (\$group->getWebsiteId() != \$websiteId) {
            \$group->setWebsiteId(\$websiteId);
            \$needsSave = true;
        }
        if (${ROOT_CATEGORY_ID} && \$group->getRootCategoryId() != ${ROOT_CATEGORY_ID}) {
            \$group->setRootCategoryId(${ROOT_CATEGORY_ID});
            \$needsSave = true;
        }
        if (\$needsSave) {
            \$groupResource->save(\$group);
            echo "Updated store group settings: ${GROUP_CODE}" . PHP_EOL;
        }
    }
    \$groupId = (int) \$group->getId();
    if (!\$groupId) {
        throw new RuntimeException('无法获取 store group ID');
    }

    /** @var \Magento\Store\Model\Store \$store */
    \$store = \$objectManager->create(\Magento\Store\Model\Store::class);
    \$storeResource->load(\$store, '${store_code_php}', 'code');
    if (!\$store->getId()) {
        \$store->setCode('${store_code_php}');
        \$store->setName('${store_name_php}');
        \$store->setWebsiteId(\$websiteId);
        \$store->setGroupId(\$groupId);
        \$store->setSortOrder(10);
        \$store->setIsActive(1);
        \$storeResource->save(\$store);
        echo "Created store: ${STORE_CODE}" . PHP_EOL;
    } else {
        \$storeChanged = false;
        if (\$store->getWebsiteId() != \$websiteId) {
            \$store->setWebsiteId(\$websiteId);
            \$storeChanged = true;
        }
        if (\$store->getGroupId() != \$groupId) {
            \$store->setGroupId(\$groupId);
            \$storeChanged = true;
        }
        if (!\$store->getIsActive()) {
            \$store->setIsActive(1);
            \$storeChanged = true;
        }
        if (\$storeChanged) {
            \$storeResource->save(\$store);
            echo "Updated store settings: ${STORE_CODE}" . PHP_EOL;
        }
    }
    \$storeId = (int) \$store->getId();
    if (!\$storeId) {
        throw new RuntimeException('无法获取 store ID');
    }

    if (\$group->getDefaultStoreId() != \$storeId) {
        \$group->setDefaultStoreId(\$storeId);
        \$groupResource->save(\$group);
        echo "Updated group default store: ${STORE_CODE}" . PHP_EOL;
    }

    if (\$website->getDefaultGroupId() != \$groupId) {
        \$website->setDefaultGroupId(\$groupId);
        \$websiteResource->save(\$website);
        echo "Updated website default group: ${GROUP_CODE}" . PHP_EOL;
    }

    echo 'Website ID: ' . \$websiteId . ', Group ID: ' . \$groupId . ', Store ID: ' . \$storeId . PHP_EOL;
} catch (\Throwable \$e) {
    echo 'ERROR:' . \$e->getMessage();
    exit(1);
}
PHP
)

    local output
    if ! output="$(magento_eval "$script")"; then
        if [[ -n "$output" ]]; then
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                log_error "$line"
            done <<< "$output"
        fi
        log_error "使用 PHP API 创建多站点实体失败。"
        exit 1
    fi

    if [[ -n "$output" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if [[ "$line" == ERROR:* ]]; then
                log_error "${line#ERROR:}"
                exit 1
            else
                log_info "$line"
            fi
        done <<< "$output"
    else
        log_info "Magento 实体已就绪：website=${WEBSITE_CODE}, group=${GROUP_CODE}, store=${STORE_CODE}"
    fi
}

delete_magento_entity() {
    local entity="$1"
    local id="$2"
    local label="$3"
    local code="$4"
    if [[ -z "$id" ]]; then
        log_warning "${label} (${code}) 未找到 ID，跳过删除。"
        return 0
    fi
    if (( DRY_RUN )); then
        log_info "[dry-run] 删除 ${label} (${code}) [ID=${id}]"
        return 0
    fi
    local entity_escaped
    entity_escaped=$(php_escape "$entity")
    local script
    read -r -d '' script <<PHP || true
\$entity = '${entity_escaped}';
\$id = (int) ${id};
\$registry = \$objectManager->get(\Magento\Framework\Registry::class);
if (!\$registry->registry('isSecureArea')) {
    \$registry->register('isSecureArea', true);
}

try {
    switch (\$entity) {
        case 'website':
            \$resource = \$objectManager->get(\Magento\Store\Model\ResourceModel\Website::class);
            \$model = \$objectManager->create(\Magento\Store\Model\Website::class);
            \$resource->load(\$model, \$id);
            if (!\$model->getId()) { echo "MISSING"; break; }
            if (method_exists(\$model, 'setIsDeleteAllowed')) { \$model->setIsDeleteAllowed(true); }
            \$resource->delete(\$model);
            echo "OK";
            break;
        case 'store_group':
            \$resource = \$objectManager->get(\Magento\Store\Model\ResourceModel\Group::class);
            \$model = \$objectManager->create(\Magento\Store\Model\Group::class);
            \$resource->load(\$model, \$id);
            if (!\$model->getId()) { echo "MISSING"; break; }
            if (method_exists(\$model, 'setIsDeleteAllowed')) { \$model->setIsDeleteAllowed(true); }
            \$resource->delete(\$model);
            echo "OK";
            break;
        case 'store':
            \$resource = \$objectManager->get(\Magento\Store\Model\ResourceModel\Store::class);
            \$model = \$objectManager->create(\Magento\Store\Model\Store::class);
            \$resource->load(\$model, \$id);
            if (!\$model->getId()) { echo "MISSING"; break; }
            if (method_exists(\$model, 'setIsDeleteAllowed')) { \$model->setIsDeleteAllowed(true); }
            if (method_exists(\$model, 'setForceDelete')) { \$model->setForceDelete(true); }
            \$resource->delete(\$model);
            echo "OK";
            break;
        default:
            echo "ERROR:未知实体类型";
    }
} catch (\Magento\Framework\Exception\NoSuchEntityException \$e) {
    echo "MISSING";
} catch (\Exception \$e) {
    echo "ERROR:" . \$e->getMessage();
} finally {
    if (\$registry->registry('isSecureArea')) {
        \$registry->unregister('isSecureArea');
    }
}
PHP
    local result
    result="$(magento_eval "$script" | tr -d $'\r')"
    case "$result" in
        OK)
            log_success "已删除 ${label} (${code}) [ID=${id}]"
            ;;
        MISSING)
            log_warning "${label} (${code}) [ID=${id}] 未找到，跳过删除。"
            ;;
        ERROR:*)
            log_error "删除 ${label} (${code}) 失败: ${result#ERROR:}"
            return 1
            ;;
        *)
            log_error "删除 ${label} (${code}) 返回未知结果: ${result}"
            return 1
            ;;
    esac
    return 0
}

current_base_url() {
    local scope="$1"
    local scope_code="$2"
    run_magento_raw config:show --scope "$scope" --scope-code "$scope_code" web/unsecure/base_url 2>/dev/null | tr -d $'\r'
}

print_summary() {
    log_highlight "多站点参数"
    echo "  Magento 根目录: ${MAGENTO_CURRENT}"
    echo "  Website code   : ${WEBSITE_CODE}"
    echo "  Store group    : ${GROUP_CODE}"
    echo "  Store code     : ${STORE_CODE}"
    echo "  Store name     : ${STORE_NAME}"
    echo "  Base URL       : ${BASE_URL}"
    echo "  Locale         : ${LOCALE}"
    echo "  Currency       : ${CURRENCY}"
    echo "  Root category  : ${ROOT_CATEGORY_ID}"
    if (( DRY_RUN )); then
        log_info "dry-run 模式，以下操作不会真正执行。"
    fi
}

ensure_backups_hint() {
    log_warning "在执行前请确认已备份数据库和 app/etc 配置。"
}

create_multisite() {
    print_summary
    ensure_backups_hint

    local has_website=0
    local has_group=0
    local has_store=0

    if check_website_exists "$WEBSITE_CODE"; then
        has_website=1
        log_info "Website '${WEBSITE_CODE}' 已存在，将跳过 CLI 创建。"
    fi
    if check_group_exists "$GROUP_CODE"; then
        has_group=1
        log_info "Store Group '${GROUP_CODE}' 已存在，将跳过 CLI 创建。"
    fi
    if check_store_exists "$STORE_CODE"; then
        has_store=1
        log_info "Store '${STORE_CODE}' 已存在，将跳过 CLI 创建。"
    fi

    local use_cli=1
    if ! (magento_command_exists "store:website:create" && \
        magento_command_exists "store:group:create" && \
        magento_command_exists "store:store:create"); then
        use_cli=0
        log_note "检测到 Magento CLI 缺少 store:* 创建命令，改用 PHP API 创建实体。"
    fi

    if (( use_cli )); then
        if (( has_website == 0 )); then
            run_magento_cmd "创建 Website ${WEBSITE_CODE}" \
                store:website:create \
                --code="$WEBSITE_CODE" \
                --name="$STORE_NAME"
        fi

        if (( has_group == 0 )); then
            run_magento_cmd "创建 Store Group ${GROUP_CODE}" \
                store:group:create \
                --website="$WEBSITE_CODE" \
                --code="$GROUP_CODE" \
                --name="$STORE_NAME" \
                --root-category-id="$ROOT_CATEGORY_ID"
        fi

        if (( has_store == 0 )); then
            run_magento_cmd "创建 Store ${STORE_CODE}" \
                store:store:create \
                --website="$WEBSITE_CODE" \
                --code="$STORE_CODE" \
                --name="$STORE_NAME" \
                --group="$GROUP_CODE" \
                --sort-order=10 \
                --is-active=1
        fi
    else
        if (( DRY_RUN )); then
            log_info "[dry-run] 使用 PHP API 创建/更新 Magento 实体 (website/group/store)。"
        else
            ensure_magento_entities_php
        fi
    fi

    run_magento_cmd "设置 Website base URL" \
        config:set \
        --scope=websites \
        --scope-code="$WEBSITE_CODE" \
        web/unsecure/base_url \
        "$BASE_URL"

    run_magento_cmd "设置 Website secure base URL" \
        config:set \
        --scope=websites \
        --scope-code="$WEBSITE_CODE" \
        web/secure/base_url \
        "$BASE_URL"

    run_magento_cmd "设置 Locale (${LOCALE})" \
        config:set \
        --scope=stores \
        --scope-code="$STORE_CODE" \
        general/locale/code \
        "$LOCALE"

    run_magento_cmd "设置 Currency (${CURRENCY})" \
        config:set \
        --scope=stores \
        --scope-code="$STORE_CODE" \
        currency/options/default \
        "$CURRENCY"

    run_magento_cmd "启用前台 HTTPS" \
        config:set \
        --scope=websites \
        --scope-code="$WEBSITE_CODE" \
        web/secure/use_in_frontend \
        1

    run_magento_cmd "刷新缓存" cache:flush

    provision_nginx_and_ssl
    update_monitoring_pillar
    adjust_php_pool "add"
    run_deploy_tasks

    if (( DRY_RUN == 0 )); then
        log_success "多站点基础配置完成。"
        if (( SKIP_NGINX )); then
            log_note "已跳过 Nginx/SSL 自动化，请手动更新 Pillar 并申请证书。"
        else
            log_info "Nginx 站点: $(nginx_site_available_path)"
            if ssl_cert_exists; then
                log_info "SSL 证书: $(ssl_cert_path)"
            else
                log_warning "未检测到证书文件: $(ssl_cert_path)"
            fi
        fi
        if (( SKIP_VARNISH == 0 )); then
            log_info "当前 Varnish 诊断结果："
            "${SCRIPT_DIR}/modules/magetools/varnish.sh" diagnose "${ROOT_SITE}" || true
        fi
    fi
}

delete_config_scope() {
    local scope="$1"
    local scope_code="$2"
    local path="$3"
    if magento_command_exists "config:delete"; then
        run_magento_cmd "删除配置 ${path} (${scope}:${scope_code})" \
            config:delete \
            --scope="$scope" \
            --scope-code="$scope_code" \
            "$path"
        return
    fi

    if (( DRY_RUN )); then
        log_info "[dry-run] 将通过 PHP 删除配置 ${path} (${scope}:${scope_code})"
        return
    fi

    local php_scope
    php_scope=$(php_escape "$scope")
    local php_scope_code
    php_scope_code=$(php_escape "$scope_code")
    local php_path
    php_path=$(php_escape "$path")
    local script
    read -r -d '' script <<PHP || true
\$scope = '${php_scope}';
\$scopeCode = '${php_scope_code}';
\$path = '${php_path}';
\$scopeId = 0;
if (\$scope === 'websites') {
    \$website = \$objectManager->create(\Magento\Store\Model\Website::class);
    \$website->load(\$scopeCode, 'code');
    \$scopeId = (int) \$website->getId();
} elseif (\$scope === 'stores') {
    \$store = \$objectManager->create(\Magento\Store\Model\Store::class);
    \$store->load(\$scopeCode, 'code');
    \$scopeId = (int) \$store->getId();
}
/** @var \Magento\Config\Model\ResourceModel\Config \$configResource */
\$configResource = \$objectManager->get(\Magento\Config\Model\ResourceModel\Config::class);
\$configResource->deleteConfig(\$path, \$scope, \$scopeId);
echo 'OK';
PHP
    local result
    result="$(magento_eval "$script" | tr -d $'\r')"
    if [[ "$result" == OK* ]]; then
        log_info "通过 PHP 删除配置 ${path} (${scope}:${scope_code})"
    else
        log_warning "通过 PHP 删除配置 ${path} (${scope}:${scope_code}) 结果: ${result}"
    fi
}

rollback_multisite() {
    print_summary
    ensure_backups_hint

    local store_id group_id website_id
    store_id="$(get_entity_id "store" "$STORE_CODE")"
    group_id="$(get_entity_id "store_group" "$GROUP_CODE")"
    website_id="$(get_entity_id "website" "$WEBSITE_CODE")"

    if [[ -z "$store_id" && -z "$group_id" && -z "$website_id" ]]; then
        log_warning "未检测到与 ${STORE_CODE} 相关的 Magento 实体，可能已回滚。"
    fi

    if [[ -n "$store_id" ]]; then
        delete_magento_entity "store" "$store_id" "Store" "$STORE_CODE"
    fi

    if [[ -n "$group_id" ]]; then
        delete_magento_entity "store_group" "$group_id" "Store Group" "$GROUP_CODE"
    fi

    if [[ -n "$website_id" ]]; then
        delete_magento_entity "website" "$website_id" "Website" "$WEBSITE_CODE"
    fi

    delete_config_scope websites "$WEBSITE_CODE" web/unsecure/base_url
    delete_config_scope websites "$WEBSITE_CODE" web/secure/base_url
    delete_config_scope stores "$STORE_CODE" general/locale/code
    delete_config_scope stores "$STORE_CODE" currency/options/default
    delete_config_scope websites "$WEBSITE_CODE" web/secure/use_in_frontend

    run_magento_cmd "刷新缓存" cache:flush

    cleanup_nginx_site
    remove_monitoring_entry
    adjust_php_pool "remove"

    if (( DRY_RUN == 0 )); then
        log_success "多站点已回滚。"
        log_note "请同步执行："
        if (( SKIP_NGINX )); then
            echo "  - 手动从 Pillar/Nginx 中移除 ${DOMAIN} 相关配置并清理证书。"
        else
            echo "  - 已尝试删除 Nginx 站点 ${NGINX_SITE}，请确认 Pillar/证书状态。"
        fi
        echo "  - 清理监控、通知等配套配置。"
        if (( SKIP_VARNISH == 0 )); then
            echo "  - 如站点启用 Varnish，可执行 'saltgoat magetools varnish disable ${ROOT_SITE}' 或重新生成 snippet。"
        fi
    fi
}

status_multisite() {
    print_summary

    local website_id group_id store_id
    website_id="$(get_entity_id "website" "$WEBSITE_CODE")"
    group_id="$(get_entity_id "store_group" "$GROUP_CODE")"
    store_id="$(get_entity_id "store" "$STORE_CODE")"

    if [[ -n "$website_id" ]]; then
        log_success "Website ${WEBSITE_CODE} (ID: ${website_id}) 已存在。"
        log_info "  web/unsecure/base_url: $(current_base_url websites "$WEBSITE_CODE")"
        log_info "  web/secure/base_url : $(run_magento_raw config:show --scope websites --scope-code "$WEBSITE_CODE" web/secure/base_url 2>/dev/null | tr -d $'\r')"
    else
        log_warning "Website ${WEBSITE_CODE} 尚未创建。"
    fi

    if [[ -n "$group_id" ]]; then
        log_success "Store Group ${GROUP_CODE} (ID: ${group_id}) 已存在。"
    else
        log_warning "Store Group ${GROUP_CODE} 尚未创建。"
    fi

    if [[ -n "$store_id" ]]; then
        log_success "Store ${STORE_CODE} (ID: ${store_id}) 已存在。"
        log_info "  general/locale/code       : $(run_magento_raw config:show --scope stores --scope-code "$STORE_CODE" general/locale/code 2>/dev/null | tr -d $'\r')"
        log_info "  currency/options/default : $(run_magento_raw config:show --scope stores --scope-code "$STORE_CODE" currency/options/default 2>/dev/null | tr -d $'\r')"
    else
        log_warning "Store ${STORE_CODE} 尚未创建。"
    fi

    if nginx_site_exists; then
        log_success "Nginx 站点 ${NGINX_SITE} 已存在: $(nginx_site_available_path)"
    else
        log_warning "Nginx 站点 ${NGINX_SITE} 尚未创建。"
    fi

    if ssl_cert_exists; then
        log_success "SSL 证书存在: $(ssl_cert_path)"
    else
        log_warning "未检测到 SSL 证书文件: $(ssl_cert_path)"
    fi

    if (( SKIP_VARNISH == 0 )); then
        log_info "Varnish 诊断（若站点启用 Varnish，应包含新域名）:"
        "${SCRIPT_DIR}/modules/magetools/varnish.sh" diagnose "${ROOT_SITE}" || true
    fi

    if (( SKIP_NGINX )); then
        log_note "未自动管理 Nginx/SSL，请确认 Pillar 与证书状态。"
    fi
}

case "$ACTION" in
    create)
        create_multisite
        ;;
    rollback)
        rollback_multisite
        ;;
    status)
        status_multisite
        ;;
    *)
        log_error "未知操作: ${ACTION}"
        usage
        exit 1
        ;;
esac

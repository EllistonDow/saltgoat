#!/bin/bash
# SaltGoat Magento Varnish helper
# Usage: saltgoat magetools varnish <enable|disable> <site>

set -euo pipefail

: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"

ACTION="${1:-}"
SITE="${2:-}"
APP_DIR=""
APP_BOOTSTRAP=""
MAGENTO_OFFLOADER_CONFIG="web/secure/offloader_header"
RUN_CONTEXT_TYPE=""
RUN_CONTEXT_CODE=""
RUN_CONTEXT_MODE=""
DEFAULT_RUN_TYPE=""
DEFAULT_RUN_CODE=""
DEFAULT_RUN_MODE=""
SANITIZED_SITE=""
MAP_VAR_TYPE=""
MAP_VAR_CODE=""
MAP_VAR_MODE=""
declare -a SERVER_NAMES=()
declare -a HOST_RUN_ORDER=()
declare -A HOST_RUN_TYPE=()
declare -A HOST_RUN_CODE=()
declare -A HOST_RUN_MODE=()

require_site() {
    if [[ -z "${SITE}" ]]; then
        log_error "请提供站点名称: saltgoat magetools varnish <enable|disable> <site>"
        exit 1
    fi
    if [[ ! -d "/var/www/${SITE}" ]]; then
        log_error "站点目录不存在: /var/www/${SITE}"
        exit 1
    fi
    if [[ ! -f "/etc/nginx/sites-available/${SITE}" ]]; then
        log_error "Nginx 站点配置不存在: /etc/nginx/sites-available/${SITE}"
        exit 1
    fi
    APP_DIR="/var/www/${SITE}"
    APP_BOOTSTRAP="${APP_DIR}/app/bootstrap.php"
    SANITIZED_SITE="$(echo "${SITE}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g')"
    [[ -n "$SANITIZED_SITE" ]] || SANITIZED_SITE="${SITE}"
}

run_magento() {
    local args=("$@")
    sudo -u www-data -H bash -lc "cd /var/www/${SITE} && php bin/magento ${args[*]}"
}

magento_php() {
    local php_script="$1"
    [[ -f "$APP_BOOTSTRAP" ]] || return 1
    sudo -u www-data -H php <<PHP
<?php
require '${APP_BOOTSTRAP}';
\$bootstrap = \Magento\Framework\App\Bootstrap::create(BP, \$_SERVER);
\$objectManager = \$bootstrap->getObjectManager();
\$state = \$objectManager->get(\Magento\Framework\App\State::class);
try {
    \$state->setAreaCode('adminhtml');
} catch (\Magento\Framework\Exception\LocalizedException \$e) {
    // area code already set
}
${php_script}
PHP
}

magento_list_websites() {
    # shellcheck disable=SC2016
    magento_php '
$storeManager = $objectManager->get(\Magento\Store\Model\StoreManagerInterface::class);
foreach ($storeManager->getWebsites() as $website) {
    $code = $website->getCode();
    if ($code && $code !== "admin") {
        echo $code, PHP_EOL;
    }
}
'
}

magento_list_stores() {
    # shellcheck disable=SC2016
    magento_php '
$storeManager = $objectManager->get(\Magento\Store\Model\StoreManagerInterface::class);
foreach ($storeManager->getStores() as $store) {
    $code = $store->getCode();
    if ($code && $code !== "admin") {
        echo $code, PHP_EOL;
    }
}
'
}

ensure_magento_offload_header() {
    if [[ ! -f "$APP_BOOTSTRAP" ]]; then
        log_warning "未找到 ${APP_BOOTSTRAP}，跳过 Magento offload header 设置"
        return
    fi
    local header="${MAGENTO_OFFLOAD_HEADER:-X-Forwarded-Proto}"

    run_magento config:set "${MAGENTO_OFFLOADER_CONFIG}" "$header" >/dev/null 2>&1 || true

    local code
    while IFS= read -r code; do
        [[ -z "$code" ]] && continue
        run_magento config:set --scope=websites --scope-code "$code" "${MAGENTO_OFFLOADER_CONFIG}" "$header" >/dev/null 2>&1 || true
    done < <(magento_list_websites 2>/dev/null)

    while IFS= read -r code; do
        [[ -z "$code" ]] && continue
        run_magento config:set --scope=stores --scope-code "$code" "${MAGENTO_OFFLOADER_CONFIG}" "$header" >/dev/null 2>&1 || true
    done < <(magento_list_stores 2>/dev/null)
}

backup_dir() {
    echo "/etc/nginx/sites-available/.saltgoat-varnish-backups"
}

frontend_snippet() {
    echo "/etc/nginx/snippets/varnish-frontend-${SITE}.conf"
}

backend_conf() {
    echo "/etc/nginx/sites-available/${SITE}-backend"
}

backend_symlink() {
    echo "/etc/nginx/sites-enabled/${SITE}-backend"
}

map_config_path() {
    local ident="${SANITIZED_SITE}"
    [[ -n "$ident" ]] || ident="$(echo "${SITE}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g')"
    [[ -n "$ident" ]] || ident="${SITE}"
    echo "/etc/nginx/conf.d/varnish-run-${ident}.conf"
}

load_run_context() {
    local pillar_file="${SCRIPT_DIR}/salt/pillar/nginx.sls"
    RUN_CONTEXT_TYPE=""
    RUN_CONTEXT_CODE=""
    RUN_CONTEXT_MODE=""
    if [[ -f "$pillar_file" ]]; then
        while IFS='=' read -r key value; do
            case "$key" in
                type) RUN_CONTEXT_TYPE="$value" ;;
                code) RUN_CONTEXT_CODE="$value" ;;
                mode) RUN_CONTEXT_MODE="$value" ;;
            esac
        done < <(sudo python3 - "$pillar_file" "$SITE" <<'PY'
import sys, yaml
path, site = sys.argv[1:3]
try:
    with open(path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
except FileNotFoundError:
    data = {}
sites = ((data.get("nginx") or {}).get("sites") or {})
run_cfg = sites.get(site, {}).get("magento_run") or {}
if isinstance(run_cfg, dict):
    default_type = run_cfg.get("type") or ""
    default_code = run_cfg.get("code") or ""
    default_mode = run_cfg.get("mode") or ""
else:
    default_type = default_code = default_mode = ""
print(f"type={default_type}")
print(f"code={default_code}")
print(f"mode={default_mode}")
PY
)
    fi
    [[ -z "$RUN_CONTEXT_TYPE" ]] && RUN_CONTEXT_TYPE="store"
    [[ -z "$RUN_CONTEXT_CODE" ]] && RUN_CONTEXT_CODE="$SITE"
    [[ -z "$RUN_CONTEXT_MODE" ]] && RUN_CONTEXT_MODE="production"
}

collect_server_names() {
    sudo python3 - "$SITE" <<'PY'
import sys
import pathlib
import re

site = sys.argv[1]
path = pathlib.Path("/etc/nginx/sites-available") / site
names = []
if path.exists():
    data = path.read_text(encoding="utf-8")
    pattern = re.compile(r"server_name\s+([^;]+);", re.IGNORECASE)
    for match in pattern.finditer(data):
        tokens = match.group(1).split()
        for token in tokens:
            tok = token.strip()
            if tok and tok not in names:
                names.append(tok)
for name in names:
    print(name)
PY
}

magento_base_domains() {
    [[ -f "$APP_BOOTSTRAP" ]] || return
    # shellcheck disable=SC2016
    magento_php '
$storeManager = $objectManager->get(\Magento\Store\Model\StoreManagerInterface::class);
$domains = [];
foreach ($storeManager->getStores() as $store) {
    $code = $store->getCode();
    foreach ([\Magento\Framework\UrlInterface::URL_TYPE_WEB, \Magento\Framework\UrlInterface::URL_TYPE_LINK] as $type) {
        foreach ([true, false] as $secure) {
            try {
                $url = $store->getBaseUrl($type, $secure);
            } catch (\Throwable $e) {
                continue;
            }
            if (!$url) {
                continue;
            }
            $host = parse_url($url, PHP_URL_HOST);
            if ($host) {
                if (!isset($domains[$host])) {
                    $domains[$host] = [];
                }
                $domains[$host][$code] = true;
            }
        }
    }
}
foreach (array_keys($domains) as $host) {
    $codes = array_keys($domains[$host]);
    echo $host, "|", implode(",", $codes), PHP_EOL;
}
' 2>/dev/null
}

build_run_contexts() {
    local -a server_names=()
    local -a config_hosts=()
    local -A seen=()
    local -A config_seen=()
    local -A host_to_store=()
    local name
    load_run_context
    HOST_RUN_ORDER=()
    HOST_RUN_TYPE=()
    HOST_RUN_CODE=()
    HOST_RUN_MODE=()
    [[ -n "$SANITIZED_SITE" ]] || SANITIZED_SITE="$(echo "${SITE}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g')"
    local prefix="mage_${SANITIZED_SITE}"
    MAP_VAR_TYPE="\$${prefix}_run_type"
    MAP_VAR_CODE="\$${prefix}_run_code"
    MAP_VAR_MODE="\$${prefix}_run_mode"
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        if [[ -z "${config_seen[$name]:-}" ]]; then
            config_hosts+=("$name")
            config_seen[$name]=1
        fi
        if [[ -z "${seen[$name]:-}" ]]; then
            server_names+=("$name")
            seen[$name]=1
        fi
    done < <(collect_server_names 2>/dev/null || true)
    while IFS='|' read -r name store_codes; do
        [[ -z "$name" ]] && continue
        local cleaned="${store_codes//,/ }"
        if [[ -n "$cleaned" ]]; then
            local existing="${host_to_store[$name]:-}"
            if [[ -n "$existing" ]]; then
                for code in $cleaned; do
                    [[ -z "$code" ]] && continue
                    if [[ " $existing " != *" $code "* ]]; then
                        existing="$existing $code"
                    fi
                done
                host_to_store[$name]="$(echo "$existing" | xargs)"
            else
                host_to_store[$name]="$(echo "$cleaned" | xargs)"
            fi
        fi
        if [[ -z "${seen[$name]:-}" ]]; then
            server_names+=("$name")
            seen[$name]=1
        fi
    done < <(magento_base_domains 2>/dev/null || true)
    if [[ ${#server_names[@]} -eq 0 ]]; then
        server_names=("${SITE}")
    fi
    if (( ${#config_hosts[@]} > 0 )); then
        log_info "继承站点 server_name: ${config_hosts[*]}"
    fi
    if (( ${#host_to_store[@]} > 0 )); then
        log_info "Magento store Base URL 域名映射:"
        for name in "${server_names[@]}"; do
            local stores="${host_to_store[$name]:-}"
            [[ -z "$stores" ]] && continue
            log_info "  - ${name} (stores: ${stores})"
        done
    fi
    local default_host="${server_names[0]}"
    local default_run_type="${RUN_CONTEXT_TYPE}"
    local default_run_code="${RUN_CONTEXT_CODE}"
    local default_run_mode="${RUN_CONTEXT_MODE}"
    local stores_for_default="${host_to_store[$default_host]}"
    if [[ ( -z "$RUN_CONTEXT_CODE" || "$RUN_CONTEXT_CODE" == "$SITE" ) && -n "$stores_for_default" ]]; then
        read -r default_run_code _ <<<"$stores_for_default"
        default_run_type="store"
    fi
    if [[ -z "$default_run_type" ]]; then
        default_run_type="store"
    fi
    if [[ -z "$default_run_code" ]]; then
        default_run_code="$SITE"
    fi
    if [[ -z "$default_run_mode" ]]; then
        default_run_mode="production"
    fi
    for name in "${server_names[@]}"; do
        local host_run_type="$default_run_type"
        local host_run_code="$default_run_code"
        local host_run_mode="$default_run_mode"
        local stores="${host_to_store[$name]}"
        if [[ -n "$stores" ]]; then
            read -r first_store _ <<<"$stores"
            if [[ -n "$first_store" ]]; then
                host_run_type="store"
                host_run_code="$first_store"
            fi
        fi
        if [[ "$name" == "$default_host" ]]; then
            default_run_type="$host_run_type"
            default_run_code="$host_run_code"
        fi
        HOST_RUN_TYPE["$name"]="$host_run_type"
        HOST_RUN_CODE["$name"]="$host_run_code"
        HOST_RUN_MODE["$name"]="$host_run_mode"
    done
    DEFAULT_RUN_TYPE="$default_run_type"
    DEFAULT_RUN_CODE="$default_run_code"
    DEFAULT_RUN_MODE="$default_run_mode"
    SERVER_NAMES=("${server_names[@]}")
    HOST_RUN_ORDER=("${server_names[@]}")
}

detect_admin_prefix() {
    local env_file="/var/www/${SITE}/app/etc/env.php"
    if [[ ! -f "$env_file" ]]; then
        echo "admin"
        return
    fi
    local prefix
    prefix="$(sudo -u www-data -H php -r "(\$env = include '${env_file}'); echo isset(\$env['backend']['frontName']) ? trim(\$env['backend']['frontName']) : 'admin';" 2>/dev/null | tr -dc '[:alnum:]_-')"
    if [[ -z "$prefix" ]]; then
        echo "admin"
    else
        echo "$prefix"
    fi
}

ensure_backup() {
    local dir file tmp
    dir="$(backup_dir)"
    file="${dir}/${SITE}.conf.orig"
    sudo mkdir -p "$dir"
    tmp="$(mktemp)"
    if ! sanitize_site_config >"$tmp"; then
        rm -f "$tmp"
        log_error "无法生成 ${SITE} 的非 Varnish 配置快照"
        exit 1
    fi
    if [[ ! -s "$tmp" ]]; then
        rm -f "$tmp"
        log_error "非 Varnish 配置快照为空，放弃继续操作"
        exit 1
    fi
    if [[ -f "$file" ]]; then
        if cmp -s "$tmp" "$file"; then
            rm -f "$tmp"
            return
        fi
        log_info "更新 ${file} 以匹配当前原始配置"
    else
        log_info "备份原始 Nginx 配置到 ${file}"
    fi
    sudo cp "$tmp" "$file"
    rm -f "$tmp"
}

restore_backup() {
    local file target tmp
    file="$(backup_dir)/${SITE}.conf.orig"
    target="/etc/nginx/sites-available/${SITE}"
    if [[ -f "$file" ]]; then
        log_info "恢复原始 Nginx 配置"
        sudo cp "$file" "$target"
        return
    fi
    log_warning "未找到备份文件，尝试基于当前配置回滚 Varnish 变更"
    tmp="$(mktemp)"
    if ! sanitize_site_config >"$tmp"; then
        rm -f "$tmp"
        log_error "无法构造回滚配置，请先执行 'sudo salt-call --local state.apply core.nginx'"
        exit 1
    fi
    sudo cp "$tmp" "$target"
    rm -f "$tmp"
}

replace_include() {
    local target="$1"
    sudo python3 - "$SITE" "$target" <<'PY'
import sys, pathlib, re
site = sys.argv[1]
target = sys.argv[2]
path = pathlib.Path("/etc/nginx/sites-available") / site
data = path.read_text(encoding="utf-8")
snippet_line = f'    include {target};'
if snippet_line in data:
    sys.exit(0)
sample_pattern = re.compile(r'^\s*include\s+/var/www/' + re.escape(site) + r'/nginx\.conf\.sample;\s*$', re.MULTILINE)
if sample_pattern.search(data):
    data = sample_pattern.sub(snippet_line, data, count=1)
else:
    mage_pattern = re.compile(r'^\s*set\s+\$MAGE_ROOT.*$', re.MULTILINE)
    match = mage_pattern.search(data)
    if match:
        idx = match.end()
        data = data[:idx] + "\n" + snippet_line + data[idx:]
    else:
        data += "\n" + snippet_line + "\n"
path.write_text(data, encoding="utf-8")
PY
}

restore_include_sample() {
    sudo python3 - "$SITE" <<'PY'
import sys, pathlib, re
site = sys.argv[1]
path = pathlib.Path("/etc/nginx/sites-available") / site
data = path.read_text(encoding="utf-8")
snippet_pattern = re.compile(r'^\s*include\s+/etc/nginx/snippets/varnish-frontend-' + re.escape(site) + r'\.conf;\s*$', re.MULTILINE)
if snippet_pattern.search(data):
    data = snippet_pattern.sub(f'    include /var/www/{site}/nginx.conf.sample;', data, count=1)
path.write_text(data, encoding="utf-8")
PY
}

sanitize_site_config() {
    python3 - "$SITE" <<'PY'
import sys, pathlib, re
site = sys.argv[1]
path = pathlib.Path("/etc/nginx/sites-available") / site
try:
    data = path.read_text(encoding="utf-8")
except FileNotFoundError:
    sys.stderr.write(f"[sanitize] missing nginx config: {path}\n")
    sys.exit(1)
snippet_pattern = re.compile(r'^\s*include\s+/etc/nginx/snippets/varnish-frontend-' + re.escape(site) + r'\.conf;\s*$', re.MULTILINE)
data = snippet_pattern.sub(f'    include /var/www/{site}/nginx.conf.sample;', data)
sys.stdout.write(data)
PY
}

ensure_direct_run_context() {
    build_run_contexts
    local config="/etc/nginx/sites-available/${SITE}"
    local default_run_type="$DEFAULT_RUN_TYPE"
    local default_run_code="$DEFAULT_RUN_CODE"
    local default_run_mode="$DEFAULT_RUN_MODE"
    local map_run_type="$MAP_VAR_TYPE"
    local map_run_code="$MAP_VAR_CODE"
    local map_run_mode="$MAP_VAR_MODE"
    sudo python3 - "$config" "$default_run_type" "$default_run_code" "$default_run_mode" "$map_run_type" "$map_run_code" "$map_run_mode" <<'PY'
import sys, pathlib, re

config_path = pathlib.Path(sys.argv[1])
default_run_type, default_run_code, default_run_mode, map_run_type, map_run_code, map_run_mode = sys.argv[2:]

try:
    data = config_path.read_text(encoding="utf-8")
except FileNotFoundError:
    sys.stderr.write(f"[direct-run] missing nginx config: {config_path}\n")
    sys.exit(1)

set_block_pattern = re.compile(r'^\s*set\s+\$MAGE_(?:RUN_TYPE|RUN_CODE|MODE)\s+.*?;$', re.MULTILINE)
data = set_block_pattern.sub('', data)

block_lines = [
    f'    set $MAGE_RUN_TYPE {default_run_type};',
    f'    set $MAGE_RUN_CODE {default_run_code};',
    f'    set $MAGE_MODE {default_run_mode};',
]

map_lines = []
if map_run_type and map_run_code and map_run_mode:
    map_lines = [
        f'    set $MAGE_RUN_TYPE {map_run_type};',
        f'    set $MAGE_RUN_CODE {map_run_code};',
        f'    set $MAGE_MODE {map_run_mode};',
    ]

block = "\n".join(block_lines + map_lines) + "\n"

root_pattern = re.compile(r'(set\s+\$MAGE_ROOT\s+[^\n]+;\s*)', re.IGNORECASE)
match = root_pattern.search(data)
if match:
    insert_pos = match.end()
    data = data[:insert_pos] + "\n" + block + data[insert_pos:]
else:
    data = block + "\n" + data

data = re.sub(r'\n{3,}', '\n\n', data)
config_path.write_text(data.strip() + "\n", encoding="utf-8")
PY
}

write_map_config() {
    build_run_contexts
    local map_path
    map_path="$(map_config_path)"
    local default_run_type="$DEFAULT_RUN_TYPE"
    local default_run_code="$DEFAULT_RUN_CODE"
    local default_run_mode="$DEFAULT_RUN_MODE"
    local map_run_type="$MAP_VAR_TYPE"
    local map_run_code="$MAP_VAR_CODE"
    local map_run_mode="$MAP_VAR_MODE"
    local host
    local -A printed=()

    {
        echo "# Auto-generated by SaltGoat varnish enable"
        echo "map \$http_host ${map_run_type} {"
        echo "    default ${default_run_type};"
        printed=()
        for host in "${HOST_RUN_ORDER[@]}"; do
            [[ -z "$host" ]] && continue
            if [[ ! "$host" =~ ^[A-Za-z0-9._-]+$ ]]; then
                continue
            fi
            if [[ -n "${printed[$host]:-}" ]]; then
                continue
            fi
            printed[$host]=1
            echo "    ${host} ${HOST_RUN_TYPE[$host]:-${default_run_type}};"
        done
        echo "}"
        echo ""
        echo "map \$http_host ${map_run_code} {"
        echo "    default ${default_run_code};"
        printed=()
        for host in "${HOST_RUN_ORDER[@]}"; do
            [[ -z "$host" ]] && continue
            if [[ ! "$host" =~ ^[A-Za-z0-9._-]+$ ]]; then
                continue
            fi
            if [[ -n "${printed[$host]:-}" ]]; then
                continue
            fi
            printed[$host]=1
            echo "    ${host} ${HOST_RUN_CODE[$host]:-${default_run_code}};"
        done
        echo "}"
        echo ""
        echo "map \$http_host ${map_run_mode} {"
        echo "    default ${default_run_mode};"
        printed=()
        for host in "${HOST_RUN_ORDER[@]}"; do
            [[ -z "$host" ]] && continue
            if [[ ! "$host" =~ ^[A-Za-z0-9._-]+$ ]]; then
                continue
            fi
        if [[ -n "${printed[$host]:-}" ]]; then
            continue
        fi
        printed[$host]=1
        echo "    ${host} ${HOST_RUN_MODE[$host]:-${default_run_mode}};"
    done
    echo "}"
} | sudo tee "$map_path" >/dev/null
    log_info "更新运行上下文 map: ${map_path}"
}

remove_map_config() {
    local map_path
    map_path="$(map_config_path)"
    if [[ -f "$map_path" ]]; then
        sudo rm -f "$map_path"
    fi
}

other_varnish_sites_exist() {
    local current_snippet current_backend current_map path
    current_snippet="$(frontend_snippet)"
    current_backend="$(backend_conf)"
    current_map="$(map_config_path)"

    for path in /etc/nginx/snippets/varnish-frontend-*.conf; do
        [[ -e "$path" ]] || continue
        [[ "$path" == "$current_snippet" ]] && continue
        return 0
    done

    for path in /etc/nginx/sites-available/*-backend; do
        [[ -e "$path" ]] || continue
        [[ "$path" == "$current_backend" ]] && continue
        return 0
    done

    for path in /etc/nginx/conf.d/varnish-run-*.conf; do
        [[ -e "$path" ]] || continue
        [[ "$path" == "$current_map" ]] && continue
        return 0
    done

    return 1
}

write_frontend_snippet() {
    local snippet admin_prefix extra_admin_block
    admin_prefix="$(detect_admin_prefix)"
    [[ -z "$admin_prefix" ]] && admin_prefix="admin"
    snippet="$(frontend_snippet)"
    log_info "检测到后台前缀: /${admin_prefix}/"
    extra_admin_block=""
    if [[ "$admin_prefix" != "admin" ]]; then
        log_info "额外兼容 /admin/ 直通 backend 以处理历史链接"
        extra_admin_block="$(
cat <<'EOADMIN'

location ^~ /admin/ {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Port $server_port;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Ssl on;
    proxy_set_header X-Magento-Vary $http_x_magento_vary;
    proxy_http_version 1.1;
    proxy_set_header Connection keep-alive;
    proxy_buffering on;
    proxy_buffers 64 256k;
    proxy_buffer_size 512k;
    proxy_busy_buffers_size 512k;
    proxy_temp_file_write_size 512k;
    proxy_max_temp_file_size 0;
    proxy_cache_bypass $http_cache_control;
}
EOADMIN
)"
    fi
    build_run_contexts
    local default_run_type="$DEFAULT_RUN_TYPE"
    local default_run_code="$DEFAULT_RUN_CODE"
    local default_run_mode="$DEFAULT_RUN_MODE"
    local map_run_type="$MAP_VAR_TYPE"
    local map_run_code="$MAP_VAR_CODE"
    local map_run_mode="$MAP_VAR_MODE"
    sudo tee "$snippet" >/dev/null <<EOF
# Auto-generated by SaltGoat varnish enable
set \$MAGE_RUN_TYPE ${default_run_type};
set \$MAGE_RUN_CODE ${default_run_code};
set \$MAGE_MODE ${default_run_mode};
set \$MAGE_RUN_TYPE ${map_run_type};
set \$MAGE_RUN_CODE ${map_run_code};
set \$MAGE_MODE ${map_run_mode};
proxy_hide_header Content-Security-Policy;
proxy_hide_header Content-Security-Policy-Report-Only;
add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline' 'unsafe-eval'; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://assets.adobedtm.com; style-src 'self' 'unsafe-inline'" always;
add_header Content-Security-Policy-Report-Only "default-src 'self' http: https: data: blob: 'unsafe-inline' 'unsafe-eval'; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://assets.adobedtm.com; style-src 'self' 'unsafe-inline'" always;
location ^~ /.well-known/acme-challenge/ {
    root /var/www/${SITE}/pub;
}

location ^~ /${admin_prefix}/ {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Ssl on;
    proxy_set_header X-Magento-Vary \$http_x_magento_vary;
    proxy_http_version 1.1;
    proxy_set_header Connection keep-alive;
    proxy_buffering on;
    proxy_buffers 64 256k;
    proxy_buffer_size 512k;
    proxy_busy_buffers_size 512k;
    proxy_temp_file_write_size 512k;
    proxy_max_temp_file_size 0;
    proxy_cache_bypass \$http_cache_control;
}

$extra_admin_block

location ^~ /customer/ {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Ssl on;
    proxy_set_header X-Magento-Vary \$http_x_magento_vary;
    proxy_http_version 1.1;
    proxy_set_header Connection keep-alive;
    proxy_buffering off;
    proxy_buffer_size 512k;
    proxy_buffers 64 256k;
    proxy_busy_buffers_size 512k;
    proxy_temp_file_write_size 512k;
    proxy_max_temp_file_size 0;
}

location ^~ /rest/ {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Ssl on;
    proxy_set_header X-Magento-Vary \$http_x_magento_vary;
    proxy_http_version 1.1;
    proxy_set_header Connection keep-alive;
    proxy_buffering off;
}

location ^~ /graphql {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Ssl on;
    proxy_set_header X-Magento-Vary \$http_x_magento_vary;
    proxy_http_version 1.1;
    proxy_set_header Connection keep-alive;
    proxy_buffering off;
}

location ^~ /page_cache/ {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Ssl on;
    proxy_set_header X-Magento-Vary \$http_x_magento_vary;
    proxy_http_version 1.1;
    proxy_set_header Connection keep-alive;
    proxy_buffering off;
    proxy_buffer_size 512k;
    proxy_buffers 64 256k;
    proxy_busy_buffers_size 512k;
    proxy_temp_file_write_size 512k;
    proxy_max_temp_file_size 0;
}

location / {
    proxy_pass http://127.0.0.1:6081;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Ssl on;
    proxy_set_header X-Magento-Vary \$http_x_magento_vary;
    proxy_http_version 1.1;
    proxy_set_header Connection keep-alive;
    proxy_buffering on;
    proxy_buffers 64 256k;
    proxy_buffer_size 512k;
    proxy_busy_buffers_size 512k;
    proxy_temp_file_write_size 512k;
    proxy_max_temp_file_size 0;
    proxy_cache_bypass \$http_cache_control;
}
EOF
}

write_backend_config() {
    local backend
    backend="$(backend_conf)"
    build_run_contexts
    local default_run_type="$DEFAULT_RUN_TYPE"
    local default_run_code="$DEFAULT_RUN_CODE"
    local default_run_mode="$DEFAULT_RUN_MODE"
    local map_run_type="$MAP_VAR_TYPE"
    local map_run_code="$MAP_VAR_CODE"
    local map_run_mode="$MAP_VAR_MODE"
    local server_name_line="${SERVER_NAMES[*]}"
    if [[ -z "$server_name_line" ]]; then
        server_name_line="${SITE}"
    fi
    log_info "backend server_name 已设置为: ${server_name_line}"

    sudo tee "$backend" >/dev/null <<EOF
# Auto-generated by SaltGoat varnish enable
server {
    listen 127.0.0.1:8080;
    server_name ${server_name_line};

    set \$MAGE_ROOT /var/www/${SITE};
    set \$MAGE_RUN_TYPE ${default_run_type};
    set \$MAGE_RUN_CODE ${default_run_code};
    set \$MAGE_MODE ${default_run_mode};
    set \$MAGE_RUN_TYPE ${map_run_type};
    set \$MAGE_RUN_CODE ${map_run_code};
    set \$MAGE_MODE ${map_run_mode};
    include /var/www/${SITE}/nginx.conf.sample;
}
EOF
    sudo ln -sf "$backend" "$(backend_symlink)"
}

remove_backend_config() {
    local backend link
    backend="$(backend_conf)"
    link="$(backend_symlink)"
    if [[ -L "$link" ]]; then
        sudo rm -f "$link"
    fi
    if [[ -f "$backend" ]]; then
        sudo rm -f "$backend"
    fi
}

nginx_reload() {
    if ! sudo bash -c 'nginx -t > /tmp/nginx-test.log 2>&1'; then
        log_error "nginx -t 失败："
        cat /tmp/nginx-test.log
        exit 1
    fi
    sudo systemctl reload nginx
    log_success "Nginx 已重新加载"
}

apply_varnish_state() {
    log_info "应用 Varnish Salt 状态"
    sudo bash -c 'salt-call --local state.apply optional.varnish > /tmp/varnish-state.log 2>&1' || {
        log_error "应用 optional.varnish 状态失败，详情："
        cat /tmp/varnish-state.log
        exit 1
    }
    sudo systemctl enable --now varnish >/dev/null 2>&1 || true
    sudo systemctl restart varnish
}

configure_magento_varnish() {
    log_info "更新 Magento 缓存配置为 Varnish"
    run_magento config:set system/full_page_cache/caching_application 2 >/dev/null
    run_magento config:set system/full_page_cache/varnish/backend_host 127.0.0.1 >/dev/null
    run_magento config:set system/full_page_cache/varnish/backend_port 8080 >/dev/null
    run_magento config:set system/full_page_cache/varnish/access_list 127.0.0.1 >/dev/null
    run_magento cache:flush >/dev/null
}

configure_magento_builtin() {
    if other_varnish_sites_exist; then
        log_info "检测到其他站点仍启用 Varnish，保留 Magento 缓存设置为 Varnish"
        return
    fi
    log_info "恢复 Magento 缓存为 Built-in"
    run_magento config:set system/full_page_cache/caching_application 1 >/dev/null
    run_magento cache:flush >/dev/null
}

diagnose_varnish() {
    require_site
    log_highlight "诊断站点 ${SITE} 的 Varnish 集成"

    local -i checks=0 failures=0
    local snippet backend map_path vcl_path value
    local -a server_names=() domains=()

    snippet="$(frontend_snippet)"
    backend="$(backend_conf)"
    map_path="$(map_config_path)"
    vcl_path="${SCRIPT_DIR}/salt/states/optional/varnish.vcl"

    ((++checks))
    if [[ -f "$snippet" ]]; then
        log_success "前端 snippet 存在: ${snippet}"
    else
        log_error "缺少前端 snippet: ${snippet}（尚未执行 varnish enable?）"
        ((++failures))
    fi

    ((++checks))
    if [[ -f "$snippet" ]] && grep -q 'proxy_set_header X-Magento-Vary' "$snippet"; then
        log_success "snippet 透传 X-Magento-Vary 头，菜单/客户数据缓存安全"
    else
        log_error "snippet 未透传 X-Magento-Vary，可能导致菜单缺失"
        ((++failures))
    fi

    ((++checks))
    if [[ -f "$backend" ]]; then
        log_success "backend 配置存在: ${backend}"
        mapfile -t server_names < <(collect_server_names 2>/dev/null || true)
        if (( ${#server_names[@]} > 0 )); then
            log_info "backend server_name: ${server_names[*]}"
        else
            log_warning "backend 配置存在，但未解析出 server_name 行"
        fi
    else
        log_error "缺少 backend 配置: ${backend}"
        ((++failures))
    fi

    ((++checks))
    if [[ -f "$map_path" ]]; then
        log_success "运行上下文 map 存在: ${map_path}"
    else
        log_error "缺少运行上下文 map: ${map_path}"
        ((++failures))
    fi

    ((++checks))
    if [[ -f "$backend" ]] && grep -q 'include /var/www/.*/nginx.conf.sample' "$backend"; then
        log_success "backend 继承 Magento 官方 nginx.conf.sample（包含必需 FastCGI 参数）"
    else
        log_warning "请确认 backend 使用 Magento 官方 nginx.conf.sample，以防遗漏 X-Magento-Vary 透传"
    fi

    ((++checks))
    if [[ -f "$vcl_path" ]] && grep -q 'req.http.X-Magento-Vary' "$vcl_path"; then
        log_success "VCL 已将 X-Magento-Vary 纳入缓存键"
    else
        log_error "VCL 未检测到 req.http.X-Magento-Vary，建议更新 optional/varnish.vcl"
        ((++failures))
    fi

    ((++checks))
    value="$(run_magento config:show system/full_page_cache/caching_application 2>/dev/null | tr -d $'\r')"
    if [[ "$value" == "2" ]]; then
        log_success "Magento FPC 配置为 Varnish (caching_application=2)"
    else
        log_error "Magento FPC 当前不是 Varnish (值=${value:-空})"
        ((++failures))
    fi

    ((++checks))
    value="$(run_magento config:show ${MAGENTO_OFFLOADER_CONFIG} 2>/dev/null | tr -d $'\r')"
    if [[ -n "$value" ]]; then
        log_success "Magento offloader header 设置为 ${value}"
    else
        log_warning "Magento offloader header 未设置，HTTPS 回源可能读取到 HTTP 协议"
    fi

    mapfile -t domains < <(magento_base_domains 2>/dev/null || true)
    if (( ${#domains[@]} > 0 )); then
        log_info "Magento store Base URL 映射："
        local entry host stores
        for entry in "${domains[@]}"; do
            host="${entry%%|*}"
            stores="${entry#*|}"
            if [[ "$host" == "$stores" ]]; then
                log_info "  - ${host}"
            else
                log_info "  - ${host} (stores: ${stores//,/ })"
            fi
        done
    fi

    log_info "共执行 ${checks} 项诊断检查"
    if (( failures > 0 )); then
        log_error "诊断发现 ${failures} 项风险，请根据提示修正后再试"
        exit 1
    fi
    log_success "未发现阻塞性问题，Varnish 集成状态良好"
}

enable_varnish() {
    log_highlight "为站点 ${SITE} 启用 Varnish"
    ensure_backup
    write_map_config
    write_frontend_snippet
    replace_include "$(frontend_snippet)"
    write_backend_config
    nginx_reload
    apply_varnish_state
    configure_magento_varnish
    ensure_magento_offload_header
    log_success "站点 ${SITE} 已启用 Varnish（前端 Nginx -> Varnish -> backend Nginx/PHP）"
}

disable_varnish() {
    log_highlight "为站点 ${SITE} 停用 Varnish"
    restore_backup
    restore_include_sample
    sudo rm -f "$(frontend_snippet)"
    remove_backend_config
    write_map_config
    ensure_direct_run_context
    nginx_reload
    configure_magento_builtin
    log_success "站点 ${SITE} 已恢复为原始 Nginx/PHP 模式"
}

case "${ACTION}" in
    enable)
        require_site
        enable_varnish
        ;;
    diagnose)
        diagnose_varnish
        ;;
    disable)
        require_site
        disable_varnish
        ;;
    ""|help|--help|-h)
        cat <<EOF
用法: saltgoat magetools varnish <enable|disable> <site>

示例:
  sudo saltgoat magetools varnish enable bank
  sudo saltgoat magetools varnish disable bank
EOF
        ;;
    *)
        log_error "未知操作: ${ACTION}，支持: enable, disable"
        exit 1
        ;;
esac

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
    local dir file
    dir="$(backup_dir)"
    file="${dir}/${SITE}.conf.orig"
    sudo mkdir -p "$dir"
    if [[ ! -f "$file" ]]; then
        log_info "备份原始 Nginx 配置到 ${file}"
        sudo cp "/etc/nginx/sites-available/${SITE}" "$file"
    fi
}

restore_backup() {
    local file
    file="$(backup_dir)/${SITE}.conf.orig"
    if [[ -f "$file" ]]; then
        log_info "恢复原始 Nginx 配置"
        sudo cp "$file" "/etc/nginx/sites-available/${SITE}"
    else
        log_warning "未找到备份文件，跳过恢复"
    fi
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
    sudo tee "$snippet" >/dev/null <<EOF
# Auto-generated by SaltGoat varnish enable
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
    local -a server_names=()
    local -a config_hosts=()
    local -A seen=()
    local -A config_seen=()
    local -A host_to_store=()
    local name
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
    if [[ ${#config_hosts[@]} -gt 0 ]]; then
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
    log_info "backend server_name 已设置为: ${server_names[*]}"
    local server_name_line="${server_names[*]}"
    sudo tee "$backend" >/dev/null <<EOF
# Auto-generated by SaltGoat varnish enable
server {
    listen 127.0.0.1:8080;
    server_name ${server_name_line};

    set \$MAGE_ROOT /var/www/${SITE};
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
    if ! sudo nginx -t >/tmp/nginx-test.log 2>&1; then
        log_error "nginx -t 失败："
        cat /tmp/nginx-test.log
        exit 1
    fi
    sudo systemctl reload nginx
    log_success "Nginx 已重新加载"
}

apply_varnish_state() {
    log_info "应用 Varnish Salt 状态"
    sudo salt-call --local state.apply optional.varnish >/tmp/varnish-state.log 2>&1 || {
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
    log_info "恢复 Magento 缓存为 Built-in"
    run_magento config:set system/full_page_cache/caching_application 1 >/dev/null
    run_magento cache:flush >/dev/null
}

diagnose_varnish() {
    require_site
    log_highlight "诊断站点 ${SITE} 的 Varnish 集成"

    local -i checks=0 failures=0
    local snippet backend vcl_path value
    local -a server_names=() domains=()

    snippet="$(frontend_snippet)"
    backend="$(backend_conf)"
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

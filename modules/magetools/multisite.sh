#!/bin/bash
# Magento 多站点创建/回滚助手
# Usage: saltgoat magetools multisite <action> [options]

set -euo pipefail

: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
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

SALTGOAT_BIN="${SCRIPT_DIR}/saltgoat"

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

provision_nginx_and_ssl() {
    if (( SKIP_NGINX )); then
        log_note "已跳过 Nginx/SSL 自动化 (--skip-nginx)。"
        return
    fi

    local doc_root
    doc_root="$(determine_doc_root)"

    if nginx_site_exists; then
        log_warning "检测到现有 Nginx 站点 ${NGINX_SITE}，跳过创建。"
    else
        run_cli_command "创建 Nginx 站点 ${NGINX_SITE}" \
            "$SALTGOAT_BIN" nginx create "$NGINX_SITE" "$DOMAIN" --root "$doc_root" --magento
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
    read -r -d '' script <<PHP
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
    read -r -d '' script <<PHP
\$entity = '${entity_escaped}';
\$id = (int) ${id};
try {
    switch (\$entity) {
        case 'website':
            \$repo = \$objectManager->get(\Magento\Store\Api\WebsiteRepositoryInterface::class);
            \$repo->deleteById(\$id);
            echo "OK";
            break;
        case 'store_group':
            \$repo = \$objectManager->get(\Magento\Store\Api\GroupRepositoryInterface::class);
            \$repo->deleteById(\$id);
            echo "OK";
            break;
        case 'store':
            \$repo = \$objectManager->get(\Magento\Store\Api\StoreRepositoryInterface::class);
            \$repo->deleteById(\$id);
            echo "OK";
            break;
        default:
            echo "ERROR:未知实体类型";
    }
} catch (\Magento\Framework\Exception\NoSuchEntityException \$e) {
    echo "MISSING";
} catch (\Exception \$e) {
    echo "ERROR:" . \$e->getMessage();
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
    run_magento_cmd "删除配置 ${path} (${scope}:${scope_code})" \
        config:delete \
        --scope="$scope" \
        --scope-code="$scope_code" \
        "$path"
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

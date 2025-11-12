#!/bin/bash

ensure_directory() {
    if [[ ! -d "$PWA_ROOT" ]]; then
        log_info "创建站点目录: ${PWA_ROOT}"
        mkdir -p "$PWA_ROOT"
        chown www-data:www-data "$PWA_ROOT"
    fi
}

ensure_composer_project() {
    if [[ ! -f "$PWA_ROOT/composer.json" ]]; then
        if [[ -z "$PWA_REPO_USER" || -z "$PWA_REPO_PASS" ]]; then
            abort "未提供 Magento Repo 凭据，请在配置中设置 composer.repo_user / repo_pass。"
        fi

        log_info "为 www-data 写入 Magento Repo 凭据..."
        sudo -u www-data -H composer config --global http-basic.repo.magento.com "$PWA_REPO_USER" "$PWA_REPO_PASS"

        if [[ -n "$(find "$PWA_ROOT" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
            abort "目录 ${PWA_ROOT} 非空，且未检测到 composer.json，无法自动执行 composer create-project。"
        fi

        log_highlight "下载 Magento 核心 (composer create-project)..."
        sudo -u www-data -H composer create-project --repository-url=https://repo.magento.com/ magento/project-community-edition "${PWA_ROOT}"
    else
        log_info "检测到 composer.json，跳过 create-project。"
    fi
}

ensure_mysql_root_password() {
    local root_pass
    root_pass="$(get_local_pillar_value mysql_password || true)"
    if [[ -z "$root_pass" ]]; then
        abort "Pillar 中缺少 mysql_password，无法确认 MySQL root 凭据。"
    fi

    if mysql -uroot -p"$root_pass" -e "SELECT 1;" >/dev/null 2>&1; then
        log_success "已验证 MySQL root 密码与 Pillar 一致。"
        return
    fi

    log_warning "使用 Pillar 中的 root 密码连接失败，尝试通过 saltuser 重新同步..."

    if [[ ! -f /etc/salt/mysql_saltuser.cnf ]]; then
        abort "未找到 /etc/salt/mysql_saltuser.cnf，无法自动重置 root 密码；请手动处理后重试。"
    fi

    local salt_user salt_pass plugin esc_root_pass
    salt_user="$(sudo awk -F= '/^user=/{print $2}' /etc/salt/mysql_saltuser.cnf | tail -1)"
    salt_pass="$(sudo awk -F= '/^password=/{print $2}' /etc/salt/mysql_saltuser.cnf | tail -1)"

    if [[ -z "$salt_user" || -z "$salt_pass" ]]; then
        abort "/etc/salt/mysql_saltuser.cnf 缺少用户或密码字段。"
    fi

    if ! mysql -u"$salt_user" -p"$salt_pass" -e "SELECT 1;" >/dev/null 2>&1; then
        abort "saltuser 凭据失效，无法自动重置 root 密码。"
    fi

    plugin=$(mysql -u"$salt_user" -p"$salt_pass" -N -B -e "SELECT plugin FROM mysql.user WHERE user='root' AND host='localhost';" 2>/dev/null || true)
    if [[ -z "$plugin" ]]; then
        plugin="caching_sha2_password"
    fi

    esc_root_pass="${root_pass//\'/\'\'}"
    if mysql -u"$salt_user" -p"$salt_pass" -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH ${plugin} BY '${esc_root_pass}';"; then
        log_success "已通过 saltuser 重置 root 密码，与 Pillar 保持一致。"
    else
        abort "尝试重置 root 密码失败，请手动验证后重试。"
    fi
}

ensure_mysql_log_bin_trust() {
    local root_pass current
    root_pass="$(get_local_pillar_value mysql_password || true)"
    if [[ -z "$root_pass" ]]; then
        abort "Pillar 中缺少 mysql_password，无法配置 log_bin_trust_function_creators。"
    fi

    current=$(mysql -uroot -p"$root_pass" -N -B -e "SHOW VARIABLES LIKE 'log_bin_trust_function_creators';" 2>/dev/null | awk '{print $2}')
    if [[ "$current" == "1" ]]; then
        log_info "log_bin_trust_function_creators 已启用。"
        return
    fi

    log_info "启用 log_bin_trust_function_creators ..."
    if mysql -uroot -p"$root_pass" -e "SET GLOBAL log_bin_trust_function_creators = 1;" \
        && mysql -uroot -p"$root_pass" -e "SET PERSIST log_bin_trust_function_creators = 1;" >/dev/null 2>&1; then
        log_success "已启用 log_bin_trust_function_creators。"
    else
        log_warning "尝试设置 log_bin_trust_function_creators 失败，请手动检查二进制日志配置。"
    fi
}

ensure_database() {
    local root_pass
    root_pass="$(get_local_pillar_value mysql_password || true)"
    if [[ -z "$root_pass" ]]; then
        abort "Pillar 中缺少 mysql_password，无法自动创建数据库。"
    fi

    log_info "检查/创建数据库 ${PWA_DB_NAME} 与用户 ${PWA_DB_USER} ..."

    local esc_db esc_user esc_host esc_pass
    esc_db="${PWA_DB_NAME//\'/\'\'}"
    esc_user="${PWA_DB_USER//\'/\'\'}"
    esc_host="${PWA_DB_HOST//\'/\'\'}"
    esc_pass="${PWA_DB_PASSWORD//\'/\'\'}"

    mysql -uroot -p"$root_pass" <<SQL
CREATE DATABASE IF NOT EXISTS \`${esc_db}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${esc_user}'@'${esc_host}' IDENTIFIED WITH sha256_password BY '${esc_pass}';
ALTER USER '${esc_user}'@'${esc_host}' IDENTIFIED WITH sha256_password BY '${esc_pass}';
GRANT ALL PRIVILEGES ON \`${esc_db}\`.* TO '${esc_user}'@'${esc_host}';
FLUSH PRIVILEGES;
SQL
}

generate_crypt_key() {
    if [[ -n "$PWA_CRYPT_KEY" && "${PWA_CRYPT_KEY}" != "auto" ]]; then
        local trimmed
        trimmed="${PWA_CRYPT_KEY//[[:space:]]/}"
        if [[ "${#trimmed}" -eq 32 && "$trimmed" == "$PWA_CRYPT_KEY" ]]; then
            return
        fi
        log_warning "配置中的 crypt key 无效（需为 32 位且不含空白），将自动生成。"
        PWA_CRYPT_KEY=""
    fi

    if [[ -n "$PWA_CRYPT_KEY" ]]; then
        return
    fi
    log_info "未提供 crypt key，自动生成 32 字节十六进制密钥。"
    PWA_CRYPT_KEY="$(openssl rand -hex 16 | tr '[:lower:]' '[:upper:]')"
}

run_magento_install() {
    if [[ -f "$PWA_ROOT/app/etc/env.php" ]]; then
        log_warning "检测到 app/etc/env.php，跳过 setup:install。若需重新安装，请删除该文件或启用 cleanup_database。"
        return
    fi

    generate_crypt_key

    local cmd=(
        php bin/magento setup:install
        "--base-url=${PWA_BASE_URL}"
        "--base-url-secure=${PWA_BASE_URL_SECURE}"
        "--backend-frontname=${PWA_ADMIN_FRONTNAME}"
        "--key=${PWA_CRYPT_KEY}"
        "--db-host=${PWA_DB_HOST}"
        "--db-name=${PWA_DB_NAME}"
        "--db-user=${PWA_DB_USER}"
        "--db-password=${PWA_DB_PASSWORD}"
        "--admin-firstname=${PWA_ADMIN_FIRSTNAME}"
        "--admin-lastname=${PWA_ADMIN_LASTNAME}"
        "--admin-email=${PWA_ADMIN_EMAIL}"
        "--admin-user=${PWA_ADMIN_USER}"
        "--admin-password=${PWA_ADMIN_PASSWORD}"
        "--language=${PWA_LOCALE}"
        "--currency=${PWA_CURRENCY}"
        "--timezone=${PWA_TIMEZONE}"
        "--use-rewrites=$([[ "${PWA_USE_REWRITES}" == "true" ]] && echo 1 || echo 0)"
        "--use-secure=$([[ "${PWA_USE_SECURE}" == "true" ]] && echo 1 || echo 0)"
        "--use-secure-admin=$([[ "${PWA_USE_SECURE_ADMIN}" == "true" ]] && echo 1 || echo 0)"
        "--search-engine=opensearch"
        "--opensearch-host=${PWA_OPENSEARCH_HOST}"
        "--opensearch-port=${PWA_OPENSEARCH_PORT}"
        "--opensearch-index-prefix=${PWA_OPENSEARCH_PREFIX}"
        "--opensearch-timeout=${PWA_OPENSEARCH_TIMEOUT}"
    )

    if [[ "${PWA_OPENSEARCH_SCHEME}" == "https" ]]; then
        cmd+=("--opensearch-ssl-mode=enabled")
    fi

    if [[ "${PWA_OPENSEARCH_AUTH}" == "True" || "${PWA_OPENSEARCH_AUTH}" == "true" ]]; then
        cmd+=("--opensearch-enable-auth=1" "--opensearch-username=${PWA_OPENSEARCH_USERNAME}" "--opensearch-password=${PWA_OPENSEARCH_PASSWORD}")
    else
        cmd+=("--opensearch-enable-auth=0")
    fi

    if [[ "${PWA_CLEANUP_DATABASE}" == "true" ]]; then
        cmd+=("--cleanup-database")
    fi

    log_highlight "执行 Magento setup:install ..."
    sudo -u www-data -H bash -lc "cd '$PWA_ROOT' && ${cmd[*]}"
}

magento_command_exists() {
    local command="$1"
    local list_output
    if ! list_output=$(sudo -u www-data -H bash -lc "cd '$PWA_ROOT' && php bin/magento list --raw 2>/dev/null" || true); then
        return 1
    fi
    if [[ -z "$list_output" ]]; then
        return 1
    fi
    if grep -E -q "^${command}(\\s|$)" <<<"$list_output"; then
        return 0
    fi
    return 1
}

post_install_tasks() {
    log_highlight "执行 Magento 部署后操作..."
    pushd "$PWA_ROOT" >/dev/null || return 1
    sudo -u www-data -H php bin/magento deploy:mode:set production || true
    sudo -u www-data -H php bin/magento cache:enable || true
    sudo -u www-data -H php bin/magento indexer:reindex || true
    popd >/dev/null || return 1
}

permissions_need_fix() {
    local owner group
    owner="$(stat -c %U "$PWA_ROOT" 2>/dev/null || echo "")"
    group="$(stat -c %G "$PWA_ROOT" 2>/dev/null || echo "")"
    if [[ "$owner" != "www-data" || "$group" != "www-data" ]]; then
        return 0
    fi
    return 1
}

fix_permissions() {
    log_info "调用 fast_fix_magento_permissions_local ..."
    "$SCRIPT_DIR/modules/magetools/permissions.sh" fast_fix_magento_permissions_local "$PWA_ROOT" || log_warning "权限修复脚本失败，请手动处理。"
}

fix_permissions_if_needed() {
    if permissions_need_fix; then
        fix_permissions
    fi
}

install_cron_if_needed() {
    if magento_command_exists "cron:install"; then
        sudo -u www-data -H bash -lc "cd '$PWA_ROOT' && php bin/magento cron:install --force"
    else
        log_warning "检测到 Magento CLI 缺少 cron:install，跳过 Magento 内建 cron 注册。"
    fi
    "${SCRIPT_DIR}/modules/magetools/magento-cron.sh" "$PWA_SITE_NAME" install || true
}

configure_valkey_if_needed() {
    if ! is_true "${PWA_CONFIGURE_VALKEY}"; then
        return
    fi
    log_info "调用 valkey-setup ($PWA_SITE_NAME) ..."
    "${SCRIPT_DIR}/modules/magetools/valkey-setup.sh" "$PWA_SITE_NAME" --no-reuse || log_warning "valkey-setup 执行失败，请手动检查。"
}

configure_rabbitmq_if_needed() {
    if ! is_true "${PWA_CONFIGURE_RABBITMQ}"; then
        return
    fi
    log_info "调用 rabbitmq-salt smart ($PWA_SITE_NAME) ..."
    "${SCRIPT_DIR}/modules/magetools/rabbitmq-salt.sh" smart "$PWA_SITE_NAME" || log_warning "rabbitmq-salt 执行失败，请手动检查。"
}

magento_cli() {
    local desc="$1"
    shift
    local cmd=("php" "bin/magento" "$@")
    log_info "$desc"
    local rendered=""
    local part
    for part in "${cmd[@]}"; do
        if [[ -z "$rendered" ]]; then
            rendered="$(escape_arg "$part")"
        else
            rendered+=" $(escape_arg "$part")"
        fi
    done
    sudo -u www-data -H bash -lc "cd '$PWA_ROOT' && $rendered"
}

apply_cms_template_page() {
    local template_file="$1"
    local identifier="$2"
    local title="$3"
    local stores="${4:-${PWA_HOME_STORE_IDS:-0}}"
    if [[ ! -f "$template_file" ]]; then
        log_warning "CMS 模板不存在: ${template_file}"
        return 1
    fi
    local helper="${SCRIPT_DIR}/modules/pwa/lib/cms_apply_page.php"
    if [[ ! -f "$helper" ]]; then
        log_warning "缺少 CMS 同步脚本: ${helper}"
        return 1
    fi
    local cmd=(
        php "$helper"
        --magento-root "$PWA_ROOT"
        --identifier "$identifier"
        --title "$title"
        --template "$template_file"
        --stores "$stores"
    )
    if is_true "${PWA_HOME_FORCE_TEMPLATE:-true}"; then
        cmd+=(--force)
    fi
    sudo -u www-data -H "${cmd[@]}"
}

cms_page_exists() {
    local identifier="$1"
    magento_cli "检查 CMS 页面 (${identifier})" "cms:page:info" "$identifier" >/dev/null 2>&1
}

ensure_pwa_home_cms_page() {
    local template
    template="$(resolve_home_template_file)"
    if [[ -z "$template" ]]; then
        log_warning "未提供 PWA Home 模板，跳过 CMS 页面创建。"
        return
    fi
    local identifier
    identifier="$(read_pwa_env_value "MAGENTO_PWA_HOME_IDENTIFIER" 2>/dev/null || echo "home")"
    local stores="${PWA_HOME_STORE_IDS:-0}"
    local page_title="${PWA_HOME_TITLE:-PWA Home}"
    log_info "同步 CMS 页面 (${identifier})"
    if output=$(apply_cms_template_page "$template" "$identifier" "$page_title" "$stores" 2>&1); then
        log_info "CMS 页面 (${identifier}) 状态: ${output}"
        if [[ "$output" != "unchanged" ]]; then
            magento_clear_cms_cache
        fi
    else
        log_warning "CMS 页面同步失败: ${output}"
    fi
}

magento_clear_cms_cache() {
    log_info "清理 Magento Cache (block_html,full_page)"
    magento_cli "清理 Cache" "cache:clean" block_html full_page
}

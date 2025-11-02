#!/bin/bash
# Magento 2 + PWA 后端一键安装脚本

set -euo pipefail

: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/utils.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/modules/magetools/permissions.sh"

CONFIG_FILE="${SCRIPT_DIR}/salt/pillar/magento-pwa.sls"
DEFAULT_NODE_VERSION="18"
DEFAULT_PWA_PORT="8082"
declare -a PWA_REQUIRED_ENV_VARS=("MAGENTO_BACKEND_URL" "CHECKOUT_BRAINTREE_TOKEN")
PWA_WITH_FRONTEND="false"
PWA_HOME_TEMPLATE_WARNING=""

is_true() {
    case "$1" in
        1|true|TRUE|True|yes|YES|on|ON) return 0 ;;
    esac
    return 1
}

decode_b64_json() {
    local payload="$1"
    python3 - <<'PY' "$payload"
import base64
import json
import sys
data = sys.argv[1] if len(sys.argv) > 1 else ""
if not data:
    print("{}")
    raise SystemExit
try:
    decoded = base64.b64decode(data).decode("utf-8")
except Exception:
    print("{}")
    raise SystemExit
try:
    json.loads(decoded)
except Exception:
    print("{}")
else:
    print(decoded)
PY
}

usage() {
    cat <<'EOF'
SaltGoat Magento PWA 安装助手

用法:
  saltgoat pwa install <site> [--with-pwa|--no-pwa]
  saltgoat pwa status <site>
  saltgoat pwa sync-content <site> [--pull] [--rebuild]
  saltgoat pwa remove <site> [--purge]
  saltgoat pwa help

说明:
  - <site> 必须在 salt/pillar/magento-pwa.sls 中定义
  - 首次运行会自动安装 Node/Yarn（如缺失）、创建数据库/用户、生成 Magento 项目并执行 setup:install
  - 可选地调用现有的 Valkey / RabbitMQ / Cron 自动化脚本
  - 如配置中启用 pwa_studio.enable 或追加 --with-pwa，将自动克隆 PWA Studio 并执行 Yarn 构建
  - `status` 输出站点与前端服务状态；`sync-content` 用于重新应用 overrides/环境变量，按需拉取仓库或重建；`remove --purge` 可清理 systemd 服务并删除 PWA Studio 目录
EOF
}

abort() {
    log_error "$1"
    exit 1
}

systemd_unit_exists() {
    local unit="$1"
    systemctl list-unit-files "$unit" >/dev/null 2>&1
}

systemd_stop_unit() {
    local unit="$1"
    if systemd_unit_exists "$unit"; then
        if systemctl stop "$unit" >/dev/null 2>&1; then
            log_info "已停止 systemd 单元: ${unit}"
        fi
    fi
}

systemd_disable_unit() {
    local unit="$1"
    if systemd_unit_exists "$unit"; then
        if systemctl disable "$unit" >/dev/null 2>&1; then
            log_info "已禁用 systemd 单元: ${unit}"
        fi
    fi
}

pwa_service_name() {
    echo "pwa-frontend-${PWA_SITE_NAME}"
}

pwa_service_unit() {
    echo "$(pwa_service_name).service"
}

pwa_service_path() {
    echo "/etc/systemd/system/$(pwa_service_name).service"
}

safe_remove_path() {
    local target="$1"
    if [[ -z "$target" || "$target" == "/" || "$target" == "/*" ]]; then
        log_warning "安全保护：忽略对路径 '${target}' 的删除请求"
        return 1
    fi
    rm -rf --one-file-system "$target"
}

load_site_config() {
    local site="$1"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        abort "缺少配置文件: ${CONFIG_FILE}，请先复制 magento-pwa.sls.sample 并填入站点参数。"
    fi

    local exports
    if ! exports=$(python3 - "$CONFIG_FILE" "$site" <<'PY'
import json
import pathlib
import sys
import yaml

config_path = pathlib.Path(sys.argv[1])
site_name = sys.argv[2]

try:
    data = yaml.safe_load(config_path.read_text()) or {}
except Exception as exc:
    print(f"[ERROR] 无法解析 {config_path}: {exc}", file=sys.stderr)
    sys.exit(1)

sites = (
    data.get("magento_pwa", {}) or {}
).get("sites", {}) or {}

if site_name not in sites:
    print(f"[ERROR] 未在 {config_path} 中找到站点 {site_name}", file=sys.stderr)
    sys.exit(1)

cfg = sites[site_name]

def emit(key, value):
    if value is None:
        value = ""
    print(f'{key}={json.dumps(value)}')

emit("PWA_SITE_NAME", site_name)
emit("PWA_ROOT", cfg.get("root", f"/var/www/{site_name}"))
emit("PWA_BASE_URL", cfg.get("base_url", f"http://{site_name}.example.com/"))
emit("PWA_BASE_URL_SECURE", cfg.get("base_url_secure", cfg.get("base_url", f"https://{site_name}.example.com/")))

admin = cfg.get("admin", {}) or {}
emit("PWA_ADMIN_FRONTNAME", admin.get("frontname", "admin"))
emit("PWA_ADMIN_FIRSTNAME", admin.get("firstname", "Admin"))
emit("PWA_ADMIN_LASTNAME", admin.get("lastname", "User"))
emit("PWA_ADMIN_EMAIL", admin.get("email", f"{site_name}@example.com"))
emit("PWA_ADMIN_USER", admin.get("user", site_name))
emit("PWA_ADMIN_PASSWORD", admin.get("password", "ChangeMe!"))

emit("PWA_CRYPT_KEY", cfg.get("crypt_key", ""))

db = cfg.get("db", {}) or {}
emit("PWA_DB_HOST", db.get("host", "localhost"))
emit("PWA_DB_NAME", db.get("name", f"{site_name}mage"))
emit("PWA_DB_USER", db.get("user", site_name))
emit("PWA_DB_PASSWORD", db.get("password", "ChangeMeDb!"))

emit("PWA_TIMEZONE", cfg.get("timezone", "UTC"))
emit("PWA_LOCALE", cfg.get("locale", "en_US"))
emit("PWA_CURRENCY", cfg.get("currency", "USD"))

composer = cfg.get("composer", {}) or {}
emit("PWA_REPO_USER", composer.get("repo_user", ""))
emit("PWA_REPO_PASS", composer.get("repo_pass", ""))

opensearch = cfg.get("opensearch", {}) or {}
emit("PWA_OPENSEARCH_HOST", opensearch.get("host", "localhost"))
emit("PWA_OPENSEARCH_PORT", opensearch.get("port", 9200))
emit("PWA_OPENSEARCH_SCHEME", opensearch.get("scheme", "http"))
emit("PWA_OPENSEARCH_PREFIX", opensearch.get("index_prefix", site_name))
emit("PWA_OPENSEARCH_USERNAME", opensearch.get("username", ""))
emit("PWA_OPENSEARCH_PASSWORD", opensearch.get("password", ""))
emit("PWA_OPENSEARCH_TIMEOUT", opensearch.get("timeout", 15))
emit("PWA_OPENSEARCH_AUTH", bool(opensearch.get("username") or opensearch.get("password") or opensearch.get("enable_auth", False)))

options = cfg.get("options", {}) or {}
emit("PWA_USE_SECURE", options.get("use_secure", True))
emit("PWA_USE_SECURE_ADMIN", options.get("use_secure_admin", True))
emit("PWA_USE_REWRITES", options.get("use_rewrites", True))
emit("PWA_CLEANUP_DATABASE", options.get("cleanup_database", True))

node_cfg = cfg.get("node", {}) or {}
emit("PWA_ENSURE_NODE", node_cfg.get("ensure", True))
emit("PWA_NODE_VERSION", node_cfg.get("version", "18"))
emit("PWA_INSTALL_YARN", node_cfg.get("install_yarn", True))

services = cfg.get("services", {}) or {}
emit("PWA_INSTALL_CRON", services.get("install_cron", True))
emit("PWA_CONFIGURE_VALKEY", services.get("configure_valkey", False))
emit("PWA_CONFIGURE_RABBITMQ", services.get("configure_rabbitmq", False))

pwa_studio = cfg.get("pwa_studio", {}) or {}
emit("PWA_STUDIO_ENABLE", pwa_studio.get("enable", False))
emit("PWA_STUDIO_REPO", pwa_studio.get("repo", "https://github.com/magento/pwa-studio.git"))
emit("PWA_STUDIO_BRANCH", pwa_studio.get("branch", "develop"))
target_dir = pwa_studio.get("target_dir", f"{cfg.get('root', f'/var/www/{site_name}')}/pwa-studio")
emit("PWA_STUDIO_DIR", target_dir)
emit("PWA_STUDIO_INSTALL_COMMAND", pwa_studio.get("yarn_command", "yarn install"))
emit("PWA_STUDIO_BUILD_COMMAND", pwa_studio.get("build_command", "yarn build"))
emit("PWA_STUDIO_ENV_TEMPLATE", pwa_studio.get("env_template", "packages/venia-concept/.env.dist"))
env_file_default = pwa_studio.get("env_file", f"{target_dir}/.env")
emit("PWA_STUDIO_ENV_FILE", env_file_default)
emit("PWA_STUDIO_PORT", pwa_studio.get("serve_port", 8082))
import base64
def emit_b64(key, value):
    raw = json.dumps(value)
    encoded = base64.b64encode(raw.encode()).decode()
    print(f'{key}="{encoded}"')
emit_b64("PWA_STUDIO_ENV_OVERRIDES_B64", pwa_studio.get("env_overrides", {}))

cms_cfg = (cfg.get("cms") or {}).get("home", {}) or {}
def normalize_store_ids(value):
    if value is None:
        return ["0"]
    if isinstance(value, (list, tuple)):
        return [str(v) for v in value] or ["0"]
    return [str(value)]

emit("PWA_HOME_TITLE", cms_cfg.get("title", "PWA Home"))
emit("PWA_HOME_TEMPLATE", cms_cfg.get("template", ""))
emit("PWA_HOME_STORE_IDS", ",".join(normalize_store_ids(cms_cfg.get("store_ids"))))
emit("PWA_HOME_IDENTIFIER", cms_cfg.get("identifier", ""))
PY
    ); then
        log_error "解析 PWA 配置失败，请检查上方错误输出。"
        exit 1
    fi

    eval "$exports"
    PWA_STUDIO_ENV_OVERRIDES_JSON=$(decode_b64_json "${PWA_STUDIO_ENV_OVERRIDES_B64:-}")
    if [[ -n "${PWA_HOME_TEMPLATE:-}" ]]; then
        if [[ "${PWA_HOME_TEMPLATE}" != /* ]]; then
            PWA_HOME_TEMPLATE_PATH="${SCRIPT_DIR%/}/${PWA_HOME_TEMPLATE}"
        else
            PWA_HOME_TEMPLATE_PATH="${PWA_HOME_TEMPLATE}"
        fi
        if [[ ! -f "$PWA_HOME_TEMPLATE_PATH" ]]; then
            PWA_HOME_TEMPLATE_WARNING="模板文件未找到: ${PWA_HOME_TEMPLATE_PATH}"
        fi
    else
        PWA_HOME_TEMPLATE_PATH=""
    fi
    if is_true "${PWA_STUDIO_ENABLE:-false}"; then
        PWA_WITH_FRONTEND="true"
    else
        PWA_WITH_FRONTEND="false"
    fi
}


version_ge() {
    local current="$1"
    local required="$2"
    [[ "$(printf '%s\n%s\n' "$required" "$current" | sort -V | head -n1)" == "$required" ]]
}

ensure_node_yarn() {
    if ! is_true "${PWA_ENSURE_NODE}"; then
        log_info "已跳过 Node.js/Yarn 检查（配置 ensure=false）"
        return
    fi

    local desired="${PWA_NODE_VERSION:-$DEFAULT_NODE_VERSION}"
    local need_node=false

    if command_exists node; then
        local current
        current="$(node --version 2>/dev/null | sed 's/v//')"
        if ! version_ge "$current" "$desired"; then
            log_warning "检测到 Node.js $current，低于期望版本 $desired，将尝试升级。"
            need_node=true
        fi
    else
        need_node=true
    fi

    if [[ "$need_node" == "true" ]]; then
        log_info "安装/升级 Node.js 到 $desired.x ..."
        if ! command_exists curl; then
            log_info "安装 curl ..."
            apt-get update
            apt-get install -y curl
        fi
        curl -fsSL "https://deb.nodesource.com/setup_${desired}.x" | bash -
        apt-get install -y nodejs
    else
        log_success "Node.js 版本满足要求 ($(node --version))"
    fi

    if is_true "${PWA_INSTALL_YARN}"; then
        if command_exists yarn; then
            log_success "Yarn 已安装 ($(yarn --version))"
        else
            log_info "全局安装 Yarn..."
            npm install -g yarn
        fi
    fi
}

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
    if grep -E -q "^${command}(\s|$)" <<<"$list_output"; then
        return 0
    fi
    return 1
}

post_install_tasks() {
    log_info "刷新缓存 & 升级数据库 ..."
    if magento_command_exists "setup:config:set"; then
        sudo -u www-data -H bash -lc "cd '$PWA_ROOT' && php bin/magento setup:config:set --http-cache-hosts=127.0.0.1:6081 --no-interaction >/dev/null 2>&1 || true"
    else
        log_warning "检测到 Magento CLI 缺少 setup:config:set，已跳过 http-cache-hosts 更新。"
    fi

    if magento_command_exists "cache:flush"; then
        sudo -u www-data -H bash -lc "cd '$PWA_ROOT' && php bin/magento cache:flush"
    else
        log_warning "检测到 Magento CLI 缺少 cache:flush，跳过缓存刷新。"
    fi

    fix_permissions_if_needed
}

permissions_need_fix() {
    local root="$PWA_ROOT"
    [[ -d "$root" ]] || return 1

    local -a ownership_checks=(
        "$root"
        "$root/app"
        "$root/bin"
        "$root/generated"
        "$root/pub"
        "$root/pub/static"
        "$root/pub/media"
        "$root/var"
        "$root/vendor"
    )

    local path owner
    for path in "${ownership_checks[@]}"; do
        [[ -e "$path" ]] || continue
        owner="$(stat -c '%U:%G' "$path" 2>/dev/null || echo '')"
        if [[ "$owner" != "www-data:www-data" ]]; then
            return 0
        fi
    done

    # Ensure key writable directories expose group write/execute
    local -A perm_expect=(
        [var]=775
        [generated]=775
        ["pub/static"]=775
        ["pub/media"]=775
    )
    local rel perm
    for rel in "${!perm_expect[@]}"; do
        path="$root/$rel"
        [[ -d "$path" ]] || continue
        perm="$(stat -c '%a' "$path" 2>/dev/null || echo '')"
        if [[ "$perm" != "${perm_expect[$rel]}" ]]; then
            return 0
        fi
    done

    if [[ -f "$root/app/etc/env.php" ]]; then
        perm="$(stat -c '%a' "$root/app/etc/env.php" 2>/dev/null || echo '')"
        if [[ "$perm" != "660" && "$perm" != "640" ]]; then
            return 0
        fi
    fi

    return 1
}

fix_permissions() {
    log_info "修正权限（并行优化模式）..."
    fast_fix_magento_permissions_local "$PWA_ROOT" "www-data" "www-data"
}

fix_permissions_if_needed() {
    if permissions_need_fix; then
        fix_permissions
    else
        log_info "检测到权限配置已符合预期，跳过修复。"
    fi
}

install_cron_if_needed() {
    if ! is_true "${PWA_INSTALL_CRON}"; then
        log_info "已跳过 cron 安装（配置 install_cron=false）"
        return
    fi
    log_info "安装 Magento cron ..."
    if magento_command_exists "cron:install"; then
        local cron_output=""
        if ! cron_output="$(sudo -u www-data -H bash -lc "cd '$PWA_ROOT' && php bin/magento cron:install" 2>&1)"; then
            if grep -qi "Crontab has already been generated" <<<"$cron_output"; then
                log_info "检测到 Magento cron 已存在，跳过重复安装。"
            else
                log_warning "执行 cron:install 失败: ${cron_output}"
            fi
        elif [[ -n "$cron_output" ]]; then
            log_info "$cron_output"
        fi
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

ensure_git() {
    if command_exists git; then
        return
    fi
    log_info "安装 git..."
    apt-get update
    apt-get install -y git
}

prepare_pwa_repo() {
    ensure_git
    local dir="$PWA_STUDIO_DIR"
    local repo="$PWA_STUDIO_REPO"
    local branch="${PWA_STUDIO_BRANCH:-develop}"

    if [[ -d "$dir/.git" ]]; then
        log_info "更新 PWA Studio 仓库 (${repo} @ ${branch}) ..."
        sudo -u www-data -H bash -lc "cd '${dir}' && git fetch origin '${branch}' && git reset --hard 'origin/${branch}'"
    else
        local parent
        parent="$(dirname "$dir")"
        mkdir -p "$parent"
        case "${parent%/}/" in
            "${PWA_ROOT%/}/"*)
                chown www-data:www-data "$parent"
                ;;
        esac
        log_info "克隆 PWA Studio 仓库 (${repo} @ ${branch}) ..."
        sudo -u www-data -H bash -lc "git clone --branch '${branch}' '${repo}' '${dir}'"
    fi
}

ensure_saltgoat_extension_workspace() {
    local workspace_src="${SCRIPT_DIR}/modules/pwa/workspaces/saltgoat-venia-extension"
    if [[ ! -d "$workspace_src" ]]; then
        return
    fi

    local workspace_dest="${PWA_STUDIO_DIR%/}/packages/saltgoat-venia-extension"
    log_info "同步 SaltGoat Venia 扩展 workspace"
    sudo -u www-data -H mkdir -p "$(dirname "$workspace_dest")"
    sudo rsync -a "$workspace_src/" "$workspace_dest/"
    sudo chown -R www-data:www-data "$workspace_dest"

    sudo -u www-data -H python3 - "$PWA_STUDIO_DIR" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
pkg_path = root / "package.json"
data = json.loads(pkg_path.read_text(encoding="utf-8"))

workspace_entry = "packages/saltgoat-venia-extension"
workspaces = data.get("workspaces")
if isinstance(workspaces, list):
    if workspace_entry not in workspaces:
        workspaces.append(workspace_entry)
elif isinstance(workspaces, dict):
    packages = workspaces.setdefault("packages", [])
    if isinstance(packages, list) and workspace_entry not in packages:
        packages.append(workspace_entry)
else:
    workspaces = [workspace_entry]
    data["workspaces"] = workspaces

deps = data.setdefault("dependencies", {})
if deps.get("@saltgoat/venia-extension") != f"link:{workspace_entry}":
    deps["@saltgoat/venia-extension"] = f"link:{workspace_entry}"

pkg_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

    ensure_workspace_dependency "${PWA_STUDIO_DIR%/}/packages/venia-ui/package.json" \
        "@saltgoat/venia-extension" "link:../saltgoat-venia-extension"
    ensure_workspace_dependency "${PWA_STUDIO_DIR%/}/packages/venia-concept/package.json" \
        "@saltgoat/venia-extension" "link:../saltgoat-venia-extension"
}

ensure_workspace_dependency() {
    local package_json="$1"
    local package_name="$2"
    local package_value="$3"

    if [[ -z "$package_json" || -z "$package_name" || -z "$package_value" ]]; then
        return
    fi
    if [[ ! -f "$package_json" ]]; then
        log_warning "未找到 package.json (${package_json})，跳过依赖写入。"
        return
    fi

    sudo -u www-data -H python3 - "$package_json" "$package_name" "$package_value" <<'PY'
import json
import pathlib
import sys

pkg_path = pathlib.Path(sys.argv[1])
name = sys.argv[2]
value = sys.argv[3]

data = json.loads(pkg_path.read_text(encoding="utf-8"))
deps = data.setdefault("dependencies", {})
changed = False

if deps.get(name) != value:
    deps[name] = value
    changed = True

if changed:
    pkg_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

    sudo chown www-data:www-data "$package_json"
}

cleanup_package_lock() {
    local lock="${PWA_STUDIO_DIR%/}/package-lock.json"
    if [[ -f "$lock" ]]; then
        log_warning "检测到 package-lock.json，已删除以避免 npm/yarn 混用。"
        rm -f "$lock"
    fi
}

ensure_package_json_field() {
    local package_json="$1"
    local field="$2"
    local package_name="$3"
    local package_value="$4"

    if [[ -z "$package_json" || -z "$field" || -z "$package_name" || -z "$package_value" ]]; then
        return
    fi
    if [[ ! -f "$package_json" ]]; then
        log_warning "未找到 package.json (${package_json})，跳过 ${package_name} 写入。"
        return
    fi

    local changed
    changed=$(sudo -u www-data -H python3 - "$package_json" "$field" "$package_name" "$package_value" <<'PY'
import json
import pathlib
import sys

pkg_path = pathlib.Path(sys.argv[1])
field = sys.argv[2]
name = sys.argv[3]
value = sys.argv[4]
data = json.loads(pkg_path.read_text(encoding="utf-8"))
section = data.setdefault(field, {})
if section.get(name) == value:
    print("unchanged")
else:
    section[name] = value
    pkg_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print("updated")
PY
)

    if [[ "$changed" == "updated" ]]; then
        sudo chown www-data:www-data "$package_json"
        log_info "已在 ${package_json##*/} 中设置 ${field}.${package_name}=${package_value}"
    fi
}

ensure_package_json_dev_dependency() {
    ensure_package_json_field "$1" "devDependencies" "$2" "$3"
}

remove_package_json_field() {
    local package_json="$1"
    local field="$2"
    local package_name="$3"

    if [[ -z "$package_json" || -z "$field" || -z "$package_name" ]]; then
        return
    fi
    if [[ ! -f "$package_json" ]]; then
        return
    fi

    local changed
    changed=$(sudo -u www-data -H python3 - "$package_json" "$field" "$package_name" <<'PY'
import json
import pathlib
import sys

pkg_path = pathlib.Path(sys.argv[1])
field = sys.argv[2]
name = sys.argv[3]
data = json.loads(pkg_path.read_text(encoding="utf-8"))
section = data.get(field)
if not isinstance(section, dict) or name not in section:
    print("absent")
else:
    section.pop(name, None)
    if not section:
        data.pop(field, None)
    pkg_path.write_text(json.dumps(data, indent=2) + "\n", encoding='utf-8')
    print("removed")
PY
)

    if [[ "$changed" == "removed" ]]; then
        sudo chown www-data:www-data "$package_json"
        log_info "已从 ${package_json##*/} 移除 ${field}.${package_name}"
    fi
}

remove_package_json_dependency() {
    remove_package_json_field "$1" "dependencies" "$2"
}

prune_unused_pwa_extensions() {
    if ! is_true "${PWA_WITH_FRONTEND:-false}"; then
        return
    fi
    local extensions_dir="${PWA_STUDIO_DIR%/}/packages/extensions"
    if [[ ! -d "$extensions_dir" ]]; then
        return
    fi

    local live_search_enabled
    live_search_enabled="$(read_pwa_env_value "MAGENTO_LIVE_SEARCH_ENABLED" 2>/dev/null || echo "false")"
    local xp_enabled
    xp_enabled="$(read_pwa_env_value "MAGENTO_EXPERIENCE_PLATFORM_ENABLED" 2>/dev/null || echo "false")"

    local unused_packages=(
        "experience-platform-connector"
        "venia-pwa-live-search"
        "venia-sample-backends"
        "venia-sample-eventing"
        "venia-sample-language-packs"
        "venia-sample-payments-cashondelivery"
        "venia-sample-payments-checkmo"
        "venia-product-recommendations"
    )

    local concept_package="${PWA_STUDIO_DIR%/}/packages/venia-concept/package.json"
    if [[ -n "$concept_package" ]]; then
        if ! is_true "$xp_enabled"; then
            remove_package_json_dependency "$concept_package" "@magento/experience-platform-connector"
        fi
        remove_package_json_dependency "$concept_package" "@magento/venia-product-recommendations"
    fi

    local package
    for package in "${unused_packages[@]}"; do
        case "$package" in
            "experience-platform-connector")
                if is_true "$xp_enabled"; then
                    continue
                fi
                ;;
            "venia-pwa-live-search")
                if is_true "$live_search_enabled"; then
                    continue
                fi
                ;;
        esac

        local path="${extensions_dir}/${package}"
        if [[ -d "$path" ]]; then
            log_info "移除未使用的 PWA 扩展 (${package})"
            sudo rm -rf "$path"
        fi
    done
}

ensure_pwa_root_peer_dependencies() {
    if ! is_true "${PWA_WITH_FRONTEND:-false}"; then
        return
    fi
    local package_json="${PWA_STUDIO_DIR%/}/package.json"
    local deps=(
        "@apollo/client|~3.5.0"
        "@babel/core|~7.15.0"
        "@babel/plugin-proposal-class-properties|~7.14.5"
        "@babel/plugin-proposal-object-rest-spread|~7.14.7"
        "@babel/plugin-proposal-optional-chaining|~7.16.0"
        "@babel/plugin-proposal-private-property-in-object|~7.16.7"
        "@babel/plugin-syntax-dynamic-import|~7.8.3"
        "@babel/plugin-syntax-jsx|~7.2.0"
        "@babel/plugin-transform-react-jsx|~7.14.9"
        "@babel/preset-env|~7.16.0"
        "@babel/runtime|~7.15.3"
        "@graphql-inspector/config|2.1.0"
        "@graphql-inspector/loaders|2.1.0"
        "@graphql-tools/utils|6.0.0"
        "@octokit/core|^3.6.0"
        "apollo-cache-persist|~0.1.1"
        "babel-loader|~8.0.5"
        "babel-plugin-react-remove-properties|~0.3.0"
        "compression|~1.7.4"
        "css-loader|~5.2.7"
        "express|^4.18.2"
        "informed|~3.29.0"
        "jarallax|~1.11.1"
        "load-google-maps-api|~2.0.1"
        "lodash.escape|~4.0.1"
        "node-fetch|~2.3.0"
        "postcss|~8.3.6"
        "postcss-loader|~4.3.0"
        "react|~17.0.2"
        "braintree-web-drop-in|~1.43.0"
        "react-dom|~17.0.2"
        "react-intl|~5.20.0"
        "react-redux|~7.2.2"
        "react-refresh|0.8.3"
        "react-router-dom|~5.2.0"
        "react-slick|~0.28.0"
        "react-tabs|~3.1.0"
        "redux|~4.0.5"
        "redux-actions|~2.6.5"
        "redux-thunk|~2.3.0"
        "terser-webpack-plugin|~1.2.3"
        "typescript|~4.3.5"
        "webpack|~4.46.0"
        "workbox-webpack-plugin|~6.2.4"
        "yargs|15.3.1"
    )

    local item name version
    for item in "${deps[@]}"; do
        name="${item%%|*}"
        version="${item#*|}"
        ensure_package_json_dev_dependency "$package_json" "$name" "$version"
    done
}

check_single_react_version() {
    local result
    result=$(python3 - "${PWA_STUDIO_DIR%/}" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1]) / "node_modules"
names = ["react", "react-dom"]
report = []
exit_code = 0
if not root.exists():
    print("skip")
    sys.exit(0)
for name in names:
    versions = set()
    for path in root.rglob(f"*/{name}/package.json"):
        if ".cache" in path.parts:
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            continue
        if data.get("name") == name:
            versions.add(data.get("version"))
    if not versions:
        report.append(f"{name}=missing")
        exit_code = 1
    elif len(versions) == 1:
        report.append(f"{name}={next(iter(versions))}")
    else:
        report.append(f"{name}={','.join(sorted(versions))}")
        exit_code = 1
print("; ".join(report))
sys.exit(exit_code)
PY
)
    local status=$?
    if [[ "$result" == "skip" ]]; then
        return
    fi
    if [[ $status -ne 0 ]]; then
        log_warning "React 依赖检测异常: ${result}"
    else
        log_info "React 依赖检测: ${result}"
    fi
}

graphql_ping() {
    local base="${PWA_BASE_URL_SECURE:-$PWA_BASE_URL}"
    base="${base%/}"
    if [[ -z "$base" ]]; then
        return
    fi
    local url="${base}/graphql"
    local response
    response=$(curl -sS -m 5 -H 'Content-Type: application/json' -d '{"query":"{storeConfig{store_name}}"}' "$url" 2>&1)
    local status=$?
    if [[ $status -ne 0 ]]; then
        log_warning "GraphQL 探测失败: ${url} (${response})"
        return
    fi
    if ! grep -q '"storeConfig"' <<<"$response"; then
        log_warning "GraphQL 返回异常: ${response}"
    else
        log_info "GraphQL 探测成功: ${url}"
    fi
}

sync_env_copy() {
    local source_file="$1"
    local target_file="$2"
    if [[ -z "$source_file" || -z "$target_file" ]]; then
        return
    fi
    if [[ "$source_file" == "$target_file" ]]; then
        return
    fi
    local target_dir
    target_dir="$(dirname "$target_file")"
    sudo -u www-data -H mkdir -p "$target_dir"
    log_info "同步 PWA 环境变量到 ${target_file}"
    sudo -u www-data -H cp "$source_file" "$target_file"
}

ensure_env_default() {
    local env_file="$1"
    local key="$2"
    local value="$3"
    sudo -u www-data -H python3 - "$env_file" "$key" "$value" <<'PY'
import sys
from pathlib import Path

env_path = Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]

if not env_path.exists():
    env_path.write_text('', encoding='utf-8')

lines = []
found = False
for raw in env_path.read_text(encoding='utf-8').splitlines():
    if raw.strip().startswith('#') or '=' not in raw:
        lines.append(raw)
        continue
    current_key, _, current_val = raw.partition('=')
    if current_key.strip() == key:
        lines.append(raw)
        found = True
    else:
        lines.append(raw)

if not found:
    lines.append(f"{key}={value}")

output = '\n'.join(lines).rstrip() + '\n'
env_path.write_text(output, encoding='utf-8')
PY
}

apply_mos_graphql_fixes() {
    if ! is_true "${PWA_WITH_FRONTEND}"; then
        return
    fi

    ensure_saltgoat_extension_workspace

    local create_account_file="${PWA_STUDIO_DIR%/}/packages/peregrine/lib/talons/CreateAccount/createAccount.gql.js"
    if [[ -f "$create_account_file" && -n "$(grep -F 'is_confirmed' "$create_account_file" || true)" ]]; then
        log_info "移除 Commerce 专属字段 (is_confirmed) 以兼容 MOS GraphQL"
        sudo -u www-data -H python3 - "$create_account_file" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
lines = [line for line in text.splitlines() if 'is_confirmed' not in line]
new_text = '\n'.join(lines) + '\n'
if new_text != text:
    path.write_text(new_text, encoding='utf-8')
PY
    fi

    local product_fragment="${PWA_STUDIO_DIR%/}/packages/peregrine/lib/talons/RootComponents/Product/productDetailFragment.gql.js"
    local product_talon="${PWA_STUDIO_DIR%/}/packages/peregrine/lib/talons/ProductFullDetail/useProductFullDetail.js"
    local overrides_dir="${SCRIPT_DIR}/modules/pwa/overrides"

    if [[ -d "${overrides_dir}/packages" ]]; then
        log_info "同步 PWA 自定义 overrides (packages/*)"
        sudo rsync -a "${overrides_dir}/packages/" "${PWA_STUDIO_DIR%/}/packages/"
        sudo chown -R www-data:www-data "${PWA_STUDIO_DIR%/}/packages/venia-concept"
    fi

    if [[ -f "${overrides_dir}/productDetailFragment.gql.js" ]]; then
        log_info "应用内置 productDetailFragment.gql.js 覆盖"
        sudo cp "${overrides_dir}/productDetailFragment.gql.js" "$product_fragment"
        sudo chown www-data:www-data "$product_fragment"
    elif [[ -f "$product_fragment" && -n "$(grep -F 'ProductAttributeMetadata' "$product_fragment" || true)" ]]; then
        log_info "裁剪 ProductAttributeMetadata 相关片段，避免 MOS GraphQL schema 缺失"
        sudo -u www-data -H python3 - "$product_fragment" <<'PY'
import sys
from pathlib import Path

def strip_block(source: str, marker: str) -> str:
    while True:
        idx = source.find(marker)
        if idx == -1:
            return source
        # include preceding whitespace on the same line
        start = source.rfind('\n', 0, idx)
        if start == -1:
            start = idx
        depth = 0
        i = idx
        while i < len(source):
            ch = source[i]
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    i += 1
                    break
            i += 1
        source = source[:start] + source[i:]
    return source

def strip_lines_containing(source: str, keyword: str) -> str:
    lines = [line for line in source.splitlines() if keyword not in line]
    return '\n'.join(lines) + '\n'

path = Path(sys.argv[1])
original = path.read_text(encoding='utf-8')
text = strip_block(original, 'attribute_metadata {')
text = strip_lines_containing(text, '... on ProductAttributeMetadata')
text = strip_lines_containing(text, 'used_in_components')
text = strip_block(text, 'custom_attributes {')
text = strip_lines_containing(text, 'selected_attribute_options')
text = strip_lines_containing(text, 'entered_attribute_value')
if text != original:
    path.write_text(text, encoding='utf-8')
PY
    fi

    if [[ -f "${overrides_dir}/useProductFullDetail.js" ]]; then
        log_info "应用内置 useProductFullDetail.js 覆盖"
        sudo cp "${overrides_dir}/useProductFullDetail.js" "$product_talon"
        sudo chown www-data:www-data "$product_talon"
    elif [[ -f "$product_talon" ]] && grep -Fq -- "attribute1['attribute_metadata']" "$product_talon"; then
        log_info "调整 ProductFullDetail talon，兼容缺失的 custom_attributes 元数据"
        sudo python3 - "$product_talon" <<'PY'
from pathlib import Path
import sys
talon_path = Path(sys.argv[1])
text = talon_path.read_text(encoding='utf-8')

old_compare = """const attributeLabelCompare = (attribute1, attribute2) => {
    const label1 = attribute1['attribute_metadata']['label'].toLowerCase();
    const label2 = attribute2['attribute_metadata']['label'].toLowerCase();
    if (label1 < label2) return -1;
    else if (label1 > label2) return 1;
    else return 0;
};"""

new_compare = """const attributeLabelCompare = (attribute1, attribute2) => {
    const label1 =
        attribute1?.attribute_metadata?.label ??
        attribute1?.attribute_option?.label ??
        '';
    const label2 =
        attribute2?.attribute_metadata?.label ??
        attribute2?.attribute_option?.label ??
        '';
    const safeLabel1 = label1.toLowerCase();
    const safeLabel2 = label2.toLowerCase();
    if (safeLabel1 < safeLabel2) return -1;
    else if (safeLabel1 > safeLabel2) return 1;
    else return 0;
};"""

old_custom = """const getCustomAttributes = (product, optionCodes, optionSelections) => {
    const { custom_attributes, variants } = product;
    const isConfigurable = isProductConfigurable(product);
    const optionsSelected =
        Array.from(optionSelections.values()).filter(value => !!value).length >
        0;

    if (isConfigurable && optionsSelected) {
        const item = findMatchingVariant({
            optionCodes,
            optionSelections,
            variants
        });

        return item && item.product
            ? [...item.product.custom_attributes].sort(attributeLabelCompare)
            : [];
    }

    return custom_attributes
        ? [...custom_attributes].sort(attributeLabelCompare)
        : [];
};"""

new_custom = """const getCustomAttributes = (product, optionCodes, optionSelections) => {
    const {
        custom_attributes: baseAttributes = [],
        variants = []
    } = product;
    const isConfigurable = isProductConfigurable(product);
    const optionsSelected =
        Array.from(optionSelections.values()).filter(value => !!value).length >
        0;

    if (isConfigurable && optionsSelected) {
        const item = findMatchingVariant({
            optionCodes,
            optionSelections,
            variants
        });

        const variantAttributes = item?.product?.custom_attributes || [];

        return variantAttributes.length
            ? [...variantAttributes].sort(attributeLabelCompare)
            : [];
    }

    return baseAttributes.length
        ? [...baseAttributes].sort(attributeLabelCompare)
        : [];
};"""

updated = text
if old_compare in updated:
    updated = updated.replace(old_compare, new_compare)
if old_custom in updated:
    updated = updated.replace(old_custom, new_custom)

if updated != text:
    talon_path.write_text(updated, encoding='utf-8')
PY
    fi

    sanitize_checkout_graphql() {
        local target_file="$1"
        if [[ ! -f "$target_file" ]]; then
            return
        fi

        local patch_result=""
        patch_result=$(sudo -u www-data -H python3 - "$target_file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
lines = text.splitlines()
result = []
i = 0
modified = False
fields_to_sanitize = {
    'selected_payment_method': ['__typename', 'code', 'title'],
    'available_payment_methods': ['__typename', 'code', 'title']
}

while i < len(lines):
    line = lines[i]
    stripped = line.strip()
    matched_field = None
    for field in fields_to_sanitize:
        if (
            field in stripped
            and f'{field}s' not in stripped  # avoid plural forms
            and '{' in line
            and stripped.startswith(field)
        ):
            matched_field = field
            break

    if matched_field:
        block_lines = [line]
        depth = line.count('{') - line.count('}')
        i += 1
        while i < len(lines) and depth > 0:
            block_lines.append(lines[i])
            depth += lines[i].count('{') - lines[i].count('}')
            i += 1
        if any('... on ' in blk for blk in block_lines[1:]):
            indent = line[: len(line) - len(line.lstrip())]
            result.append(f"{indent}{matched_field} {{")
            for field_line in fields_to_sanitize[matched_field]:
                result.append(f"{indent}    {field_line}")
            result.append(f"{indent}}}")
            modified = True
        else:
            result.extend(block_lines)
        continue
    result.append(line)
    i += 1

if modified:
    new_text = '\n'.join(result).rstrip() + '\n'
    path.write_text(new_text, encoding='utf-8')
    print("changed")
else:
    print("unchanged")
PY
        )

        if [[ "$patch_result" == "changed" ]]; then
            log_info "裁剪 checkout GraphQL 片段 (${target_file##*/})，移除 Commerce 专属支付字段"
        fi
    }

    sanitize_checkout_graphql "${PWA_STUDIO_DIR%/}/packages/venia-ui/lib/components/CheckoutPage/PaymentInformation/paymentInformation.gql.js"
    sanitize_checkout_graphql "${PWA_STUDIO_DIR%/}/packages/venia-ui/lib/components/CheckoutPage/checkoutPage.gql.js"

    local cart_fragment="${PWA_STUDIO_DIR%/}/packages/peregrine/lib/talons/Header/cartTriggerFragments.gql.js"
    if [[ -f "$cart_fragment" && -n "$(grep -F 'total_summary_quantity_including_config' "$cart_fragment" || true)" ]]; then
        log_info "移除 MOS 不支持的购物车统计字段"
        sudo -u www-data -H python3 - "$cart_fragment" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
filtered = '\n'.join(
    line for line in text.splitlines()
    if 'total_summary_quantity_including_config' not in line
) + '\n'
if filtered != text:
    path.write_text(filtered, encoding='utf-8')
PY
    fi

    local cart_trigger_hook="${PWA_STUDIO_DIR%/}/packages/peregrine/lib/talons/Header/useCartTrigger.js"
    if [[ -f "$cart_trigger_hook" && -n "$(grep -F 'total_summary_quantity_including_config' "$cart_trigger_hook" || true)" ]]; then
        log_info "调整购物车角标统计，兼容 MOS 字段"
        sudo -u www-data -H python3 - "$cart_trigger_hook" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
old = 'const itemCount = data?.cart?.total_summary_quantity_including_config || 0;'
new = 'const itemCount = data?.cart?.total_quantity || 0;'
text = path.read_text(encoding='utf-8')
if old in text and new not in text:
    path.write_text(text.replace(old, new), encoding='utf-8')
PY
    fi

    local xp_intercept="${PWA_STUDIO_DIR%/}/packages/extensions/experience-platform-connector/intercept.js"
    if [[ -f "$xp_intercept" && -z "$(grep -F 'MAGENTO_EXPERIENCE_PLATFORM_ENABLED' "$xp_intercept" || true)" ]]; then
        log_info "禁用 Experience Platform 扩展（MOS 不支持）"
        sudo -u www-data -H python3 - "$xp_intercept" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
guard = "module.exports = targets => {\n    if (process.env.MAGENTO_EXPERIENCE_PLATFORM_ENABLED !== 'true') {\n        return;\n    }\n"
if text.startswith("module.exports = targets => {\n") and guard not in text:
    text = text.replace("module.exports = targets => {\n", guard, 1)
    path.write_text(text, encoding='utf-8')
PY
    fi

    local live_search_intercept="${PWA_STUDIO_DIR%/}/packages/extensions/venia-pwa-live-search/src/targets/intercept.js"
    if [[ -f "$live_search_intercept" && -z "$(grep -F 'MAGENTO_LIVE_SEARCH_ENABLED' "$live_search_intercept" || true)" ]]; then
        log_info "按需禁用 PWA Live Search 扩展"
        sudo -u www-data -H python3 - "$live_search_intercept" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
guard = "module.exports = targets => {\n    if (process.env.MAGENTO_LIVE_SEARCH_ENABLED !== 'true') {\n        return;\n    }\n"
if text.startswith("module.exports = targets => {\n") and guard not in text:
    text = text.replace("module.exports = targets => {\n", guard, 1)
    path.write_text(text, encoding='utf-8')
PY
    fi

    local webpack_config="${PWA_STUDIO_DIR%/}/packages/venia-concept/webpack.config.js"
    if [[ -f "$webpack_config" && -z "$(grep -F 'config.performance.hints = false' "$webpack_config" || true)" ]]; then
        log_info "调整 webpack 配置，禁用性能提示告警"
        sudo -u www-data -H python3 - "$webpack_config" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
marker = "    return [config];"
snippet = (
    "    config.performance = config.performance || {};\n"
    "    config.performance.hints = false;\n"
    "    config.performance.maxEntrypointSize = 1200 * 1024;\n"
    "    config.performance.maxAssetSize = 800 * 1024;\n"
)

if "config.performance.hints = false" not in text and marker in text:
    updated = text.replace(marker, snippet + "\n" + marker)
    if updated != text:
        path.write_text(updated, encoding='utf-8')
PY
    fi
}

prepare_pwa_env() {
    local env_file="$PWA_STUDIO_ENV_FILE"
    local template="$PWA_STUDIO_ENV_TEMPLATE"
    local overrides_json="$PWA_STUDIO_ENV_OVERRIDES_JSON"

    sudo -u www-data -H mkdir -p "$(dirname "$env_file")"

    if [[ -n "$template" && -f "$PWA_STUDIO_DIR/$template" ]]; then
        log_info "使用模板生成 PWA 环境变量文件"
        sudo -u www-data -H cp "$PWA_STUDIO_DIR/$template" "$env_file"
    elif [[ ! -f "$env_file" ]]; then
        log_info "创建新的 PWA 环境变量文件"
        sudo -u www-data -H touch "$env_file"
    fi

    if [[ -n "$overrides_json" && "$overrides_json" != "{}" ]]; then
        log_info "写入 PWA 环境变量覆盖项"
        python3 - <<'PY' "$env_file" "$overrides_json"
import json
import sys
from pathlib import Path

env_path = Path(sys.argv[1])
overrides = json.loads(sys.argv[2])

if not env_path.exists():
    env_path.write_text('', encoding='utf-8')

lines = []
existing = {}
for raw in env_path.read_text(encoding='utf-8').splitlines():
    if '=' in raw and not raw.strip().startswith('#'):
        key, _, _ = raw.partition('=')
        existing[key.strip()] = raw
    lines.append(raw)

for key, value in overrides.items():
    new_line = f"{key}={value}"
    if key in existing:
        lines = [new_line if l == existing[key] else l for l in lines]
    else:
        lines.append(new_line)

env_path.write_text('\n'.join(lines).rstrip() + '\n', encoding='utf-8')
PY
    fi

    if [[ -n "${PWA_HOME_IDENTIFIER:-}" ]]; then
        ensure_env_default "$env_file" "MAGENTO_PWA_HOME_IDENTIFIER" "${PWA_HOME_IDENTIFIER}"
    fi
    ensure_env_default "$env_file" "MAGENTO_BACKEND_EDITION" "MOS"
    ensure_env_default "$env_file" "MAGENTO_EXPERIENCE_PLATFORM_ENABLED" "false"
    ensure_env_default "$env_file" "MAGENTO_LIVE_SEARCH_ENABLED" "false"
    ensure_env_default "$env_file" "MAGENTO_PWA_HOME_IDENTIFIER" "home"

    local root_env="${PWA_STUDIO_DIR%/}/.env"
    local venia_env="${PWA_STUDIO_DIR%/}/packages/venia-concept/.env"
    sync_env_copy "$env_file" "$root_env"
    sync_env_copy "$env_file" "$venia_env"
}

ensure_pwa_env_vars() {
    local env_file="$PWA_STUDIO_ENV_FILE"
    if [[ ! -f "$env_file" ]]; then
        log_error "未找到 PWA 环境变量文件: ${env_file}"
        return 1
    fi
    local missing=()
    local key
    for key in "${PWA_REQUIRED_ENV_VARS[@]}"; do
        if ! grep -E -q "^${key}=" "$env_file"; then
            missing+=("$key")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "PWA 环境变量缺少必填项: ${missing[*]}"
        log_info "请在 salt/pillar/magento-pwa.sls 的 pwa_studio.env_overrides 中补充上述键值，或在运行时传入 --no-pwa 跳过前端构建。"
        return 1
    fi
    return 0
}

read_pwa_env_value() {
    local key="$1"
    local env_file="$PWA_STUDIO_ENV_FILE"
    python3 - "$env_file" "$key" <<'PY'
import sys
from pathlib import Path

env_path = Path(sys.argv[1])
target_key = sys.argv[2]
if not env_path.exists():
    sys.exit(1)
value = ""
for line in env_path.read_text(encoding="utf-8").splitlines():
    if line.strip().startswith("#") or "=" not in line:
        continue
    k, _, v = line.partition("=")
    if k.strip() == target_key:
        value = v
        break
if value:
    print(value.strip())
PY
}

log_pwa_home_identifier_hint() {
    local identifier
    identifier="$(read_pwa_env_value "MAGENTO_PWA_HOME_IDENTIFIER" 2>/dev/null || echo "")"
    if [[ -z "$identifier" ]]; then
        identifier="home"
    fi
    log_info "PWA 首页 CMS Identifier: ${identifier}"
    if [[ "$identifier" == "home" ]]; then
        log_info "提示：可在 Magento Admin 中创建 Identifier=pwa_home 的 Page Builder 页面，并在 Pillar env_overrides 中设置 MAGENTO_PWA_HOME_IDENTIFIER=pwa_home。"
    else
        log_info "请确保 Magento Admin 中存在 Identifier=${identifier} 的 CMS 页面，并已发布到对应 Store View。"
    fi
    if [[ -n "$PWA_HOME_TEMPLATE_WARNING" ]]; then
        log_warning "$PWA_HOME_TEMPLATE_WARNING"
    fi
}

resolve_home_template_file() {
    local identifier="$1"
    local template_path="${PWA_HOME_TEMPLATE_PATH:-}"
    if [[ -n "$template_path" && -f "$template_path" ]]; then
        printf '%s\n' "$template_path"
        return 0
    fi
    local default="${SCRIPT_DIR%/}/modules/pwa/templates/cms/${identifier}.html"
    if [[ -f "$default" ]]; then
        printf '%s\n' "$default"
        return 0
    fi
    printf '%s\n' ""
    return 1
}

ensure_magento_graphql_ready() {
    local backend_url graphql_endpoint
    backend_url="$(read_pwa_env_value "MAGENTO_BACKEND_URL" || true)"
    if [[ -z "$backend_url" ]]; then
        log_warning "无法从 PWA 环境文件读取 MAGENTO_BACKEND_URL，跳过 GraphQL 探测。"
        return 1
    fi
    backend_url="${backend_url%/}"
    graphql_endpoint="${backend_url}/graphql"
    log_info "检测 Magento GraphQL 接口: ${graphql_endpoint}"
    local response
    response="$(curl -sS -m 15 -H 'Content-Type: application/json' -d '{"query":"{storeConfig{store_name}}"}' "$graphql_endpoint" 2>/dev/null || true)"
    if [[ -z "$response" ]]; then
        log_warning "无法访问 ${graphql_endpoint}（HTTP 空响应），请确认 Magento 已完成安装并对外开放。"
        return 1
    fi
    if ! python3 - "$response" <<'PY'
import json, sys
payload_text = sys.argv[1]
try:
    payload = json.loads(payload_text)
except Exception:
    print("GraphQL 接口返回非 JSON 内容。")
    sys.exit(1)
errors = payload.get("errors")
if errors:
    print("GraphQL 返回 errors: {}".format(errors))
    sys.exit(1)
sys.exit(0)
PY
    then
        log_warning "Magento GraphQL 接口未准备就绪，已跳过 PWA 构建。"
        return 1
    fi
    return 0
}

prepare_yarn_environment() {
    local workdir="$1"
    local cache_dir="$workdir/.cache"
    local yarn_cache="$cache_dir/yarn"
    local yarn_global="$workdir/.yarn-global"
    local npm_cache="$cache_dir/npm"
    local npx_cache="$cache_dir/npx"
    sudo -u www-data -H mkdir -p "$cache_dir" "$yarn_cache" "$yarn_global" "$npm_cache" "$npx_cache"
    chown -R www-data:www-data "$workdir"
}

ensure_inotify_limits() {
    local min_watches="${PWA_INOTIFY_MIN_WATCHES:-524288}"
    local current
    current=$(sysctl -n fs.inotify.max_user_watches 2>/dev/null || echo "")
    if [[ -z "$current" ]]; then
        return
    fi
    if (( current >= min_watches )); then
        return
    fi

    if sysctl -w "fs.inotify.max_user_watches=${min_watches}" >/dev/null 2>&1; then
        log_info "提升 fs.inotify.max_user_watches=${min_watches}"
        local sysctl_dir="/etc/sysctl.d"
        local sysctl_conf="${sysctl_dir}/99-saltgoat-pwa.conf"
        if [[ -d "$sysctl_dir" && -w "$sysctl_dir" ]]; then
            if [[ ! -f "$sysctl_conf" ]] || ! grep -Fq -- 'fs.inotify.max_user_watches' "$sysctl_conf" 2>/dev/null; then
                printf "fs.inotify.max_user_watches = %s\n" "$min_watches" >>"$sysctl_conf"
                log_info "已写入 ${sysctl_conf}，重启后自动恢复该限制。"
            fi
        fi
    else
        log_warning "无法提升 fs.inotify.max_user_watches=${min_watches}，如需 yarn watch 请手动调整。"
    fi
}

run_yarn_task() {
    local command="$1"
    if [[ -z "$command" ]]; then
        return
    fi
    ensure_inotify_limits
    prepare_yarn_environment "$PWA_STUDIO_DIR"
    local yarn_cache_dir="${PWA_STUDIO_DIR}/.cache/yarn"
    local yarn_global_dir="${PWA_STUDIO_DIR}/.yarn-global"
    local npm_cache_dir="${PWA_STUDIO_DIR}/.cache/npm"
    local npx_cache_dir="${PWA_STUDIO_DIR}/.cache/npx"
    local backend_edition
    backend_edition="$(read_pwa_env_value "MAGENTO_BACKEND_EDITION" || true)"
    if [[ -z "$backend_edition" ]]; then
        backend_edition="MOS"
    fi
    log_info "执行 PWA 命令: ${command}"
    sudo -u www-data -H bash -lc "cd '${PWA_STUDIO_DIR}' \
        && export HOME='${PWA_STUDIO_DIR}' \
        && export YARN_CACHE_FOLDER='${yarn_cache_dir}' \
        && export YARN_GLOBAL_FOLDER='${yarn_global_dir}' \
        && export NPM_CONFIG_CACHE='${npm_cache_dir}' \
        && export npm_config_cache='${npm_cache_dir}' \
        && export npm_config_prefix='${yarn_global_dir}' \
        && export NPX_CACHE_DIR='${npx_cache_dir}' \
        && export MAGENTO_BACKEND_EDITION='${backend_edition}' \
        && ${command}"
}

build_pwa_frontend() {
    if ! is_true "${PWA_WITH_FRONTEND}"; then
        log_info "未启用 PWA Studio 前端构建（配置或参数）"
        return
    fi

    prepare_pwa_repo
    apply_mos_graphql_fixes
    prepare_pwa_env
    prune_unused_pwa_extensions
    cleanup_package_lock
    ensure_pwa_home_cms_page
    if ! ensure_pwa_env_vars; then
        log_warning "缺少必要的 PWA 环境变量，已跳过前端构建。"
        return
    fi
    if ! ensure_magento_graphql_ready; then
        return
    fi
    ensure_pwa_root_peer_dependencies
    run_yarn_task "${PWA_STUDIO_INSTALL_COMMAND:-yarn install}"
    check_single_react_version
    run_yarn_task "${PWA_STUDIO_BUILD_COMMAND:-yarn build}"
}

ensure_pwa_service() {
    if ! is_true "${PWA_WITH_FRONTEND}"; then
        return
    fi
    local service_name="pwa-frontend-${PWA_SITE_NAME}"
    local service_path="/etc/systemd/system/${service_name}.service"
    local port="${PWA_STUDIO_PORT:-$DEFAULT_PWA_PORT}"
    local service_root="${PWA_STUDIO_DIR%/}/packages/venia-concept"
    local proxy_root="${service_root}/.proxy-root"
    local yarn_cache="${service_root}/.cache/yarn"
    local yarn_global="${service_root}/.yarn-global"
    local npm_cache="${service_root}/.cache/npm"
    local npx_cache="${service_root}/.cache/npx"

    mkdir -p "$proxy_root" "$yarn_cache" "$yarn_global" "$npm_cache" "$npx_cache"
    chown -R www-data:www-data "$service_root"

    cat <<EOF > "$service_path"
[Unit]
Description=SaltGoat Venia PWA (${PWA_SITE_NAME})
After=network.target
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=${service_root}
Environment=HOME=${service_root}
Environment=NODE_ENV=production
Environment=NODE_OPTIONS=--openssl-legacy-provider
Environment=PORT=${port}
Environment=HOST=127.0.0.1
Environment=YARN_CACHE_FOLDER=${yarn_cache}
Environment=YARN_GLOBAL_FOLDER=${yarn_global}
Environment=NPM_CONFIG_CACHE=${npm_cache}
Environment=npm_config_cache=${npm_cache}
Environment=NPX_CACHE_DIR=${npx_cache}
ExecStart=/usr/bin/env yarn buildpack serve .
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "${service_name}.service"
    systemctl restart "${service_name}.service"
}

escape_arg() {
    local value="$1"
    local escaped
    printf -v escaped "%q" "$value"
    echo "$escaped"
}

magento_cli() {
    local cd_dir
    cd_dir="$(escape_arg "$PWA_ROOT")"
    local args=()
    local arg
    for arg in "$@"; do
        args+=("$(escape_arg "$arg")")
    done
    sudo -u www-data -H bash -lc "cd ${cd_dir} && php bin/magento ${args[*]}"
}

magento_apply_cms_page_php() {
    local identifier="$1"
    local title="$2"
    local store_ids="$3"
    local content_file="$4"
    local is_active="$5"
    local layout="$6"

    local php_file
    php_file="$(mktemp)"
    cat <<'PHP' > "$php_file"
<?php
require 'app/bootstrap.php';

use Magento\Cms\Api\Data\PageInterfaceFactory;
use Magento\Cms\Api\PageRepositoryInterface;
use Magento\Framework\App\Bootstrap;
use Magento\Framework\Api\SearchCriteriaBuilder;
use Magento\Framework\Exception\LocalizedException;

$identifier = $argv[1];
$title = $argv[2];
$storeIds = array_filter(explode(',', $argv[3]), 'strlen');
if (!$storeIds) {
    $storeIds = ['0'];
}
$contentFile = $argv[4];
$isActive = (int) $argv[5];
$pageLayout = $argv[6] ?: '1column';

if ($contentFile && file_exists($contentFile)) {
    $content = file_get_contents($contentFile);
} else {
    $content = '<h1>PWA Home Placeholder</h1><p>请在 Magento 后台编辑此页面。</p>';
}

$bootstrap = Bootstrap::create(BP, $_SERVER);
$objectManager = $bootstrap->getObjectManager();
$state = $objectManager->get(\Magento\Framework\App\State::class);
try {
    $state->setAreaCode('adminhtml');
} catch (LocalizedException $e) {
    // 已设置过 area code，可忽略
}

$repository = $objectManager->get(PageRepositoryInterface::class);
$factory = $objectManager->get(PageInterfaceFactory::class);
$searchCriteriaBuilder = $objectManager->get(SearchCriteriaBuilder::class);

$searchCriteria = $searchCriteriaBuilder->addFilter('identifier', $identifier)->create();
$existing = $repository->getList($searchCriteria)->getItems();

try {
    if ($existing) {
        $page = array_shift($existing);
        $page->setTitle($title);
        $page->setContent($content);
        $page->setIsActive($isActive);
        $page->setPageLayout($pageLayout);
        $page->setData('store_id', $storeIds);
        $repository->save($page);
        echo 'updated';
    } else {
        $page = $factory->create();
        $page->setIdentifier($identifier);
        $page->setTitle($title);
        $page->setContent($content);
        $page->setIsActive($isActive);
        $page->setPageLayout($pageLayout);
        $page->setData('store_id', $storeIds);
        $repository->save($page);
        echo 'created';
    }
} catch (\Exception $e) {
    fwrite(STDERR, $e->getMessage());
    exit(1);
}
PHP
    chmod 644 "$php_file"

    local output
    local root_escaped
    root_escaped="$(escape_arg "$PWA_ROOT")"
    if ! output=$(sudo -u www-data -H bash -lc "cd ${root_escaped} && php '$php_file' '$identifier' '$title' '$store_ids' '$content_file' '$is_active' '$layout'" 2>&1); then
        rm -f "$php_file"
        log_warning "通过 PHP API 应用 CMS 页面 ${identifier} 失败: ${output}"
        return 1
    fi
    rm -f "$php_file"
    if [[ "$output" == created* ]]; then
        log_success "已自动创建 CMS 页面 ${identifier}（PHP API）"
    elif [[ "$output" == updated* ]]; then
        log_info "已更新 CMS 页面 ${identifier}（PHP API）"
    else
        log_info "CMS 页面 ${identifier} 已处理: ${output}"
    fi
    return 0
}

cms_page_exists() {
    local identifier="$1"
    local root_pass
    root_pass="$(get_local_pillar_value mysql_password || true)"
    if [[ -z "$root_pass" ]]; then
        log_warning "缺少 mysql_password Pillar，无法检查 CMS 页面 ${identifier}。"
        return 1
    fi
    local escaped_identifier="${identifier//\'/\'\'}"
    local query="SELECT page_id FROM cms_page WHERE identifier='${escaped_identifier}' LIMIT 1;"
    local result
    result=$(mysql -uroot -p"$root_pass" -N -B -D "$PWA_DB_NAME" -e "$query" 2>/dev/null || true)
    if [[ -n "$result" ]]; then
        return 0
    fi
    return 1
}

ensure_pwa_home_cms_page() {
    local identifier
    identifier="$(read_pwa_env_value "MAGENTO_PWA_HOME_IDENTIFIER" 2>/dev/null || echo "")"
    identifier="${identifier//[$'\r\n']/}"
    if [[ -z "$identifier" ]]; then
        identifier="home"
    fi
    if [[ "$identifier" == "home" ]]; then
        return
    fi
    local title="${PWA_HOME_TITLE:-PWA Home}"
    local store_ids="${PWA_HOME_STORE_IDS:-0}"
    local content_file
    content_file="$(resolve_home_template_file "$identifier")"

    local has_cli="true"
    if ! magento_command_exists "cms:page:create"; then
        has_cli="false"
    fi

    if [[ "$has_cli" == "true" ]]; then
        if cms_page_exists "$identifier"; then
            log_info "CMS 页面 ${identifier} 已存在，准备更新标题和内容。"
            if [[ -n "$content_file" ]]; then
                if magento_cli cms:page:update "--identifier=${identifier}" "--title=${title}" --is-active=1 "--store-id=${store_ids}" --page-layout=1column "--content-file=${content_file}"; then
                    log_success "已更新 CMS 页面 ${identifier} 的内容与配置。"
                else
                    log_warning "更新 CMS 页面 ${identifier} 失败，请检查 Magento CLI 输出。"
                fi
            else
                log_info "未提供模板文件，保持现有页面内容。"
            fi
            return
        fi

        local tmp_file=""
        local cleanup_tmp="false"
        if [[ -n "$content_file" ]]; then
            tmp_file="$content_file"
        else
            tmp_file="$(mktemp)"
            cat <<'EOF' > "$tmp_file"
<h1>PWA Home Placeholder</h1>
<p>请在 Magento 后台 (Content &gt; Pages) 编辑此页面的 Page Builder 布局。</p>
EOF
            cleanup_tmp="true"
        fi

        if magento_cli cms:page:create "--title=${title}" "--identifier=${identifier}" --is-active=1 "--page-layout=1column" "--store-id=${store_ids}" "--content-file=${tmp_file}"; then
            log_success "已自动创建 CMS 页面 ${identifier}（PWA 首页占位内容）。"
        else
            log_warning "创建 CMS 页面 ${identifier} 失败，请在 Magento 后台手动创建。"
        fi

        if [[ "$cleanup_tmp" == "true" ]]; then
            rm -f "$tmp_file"
        fi
        return
    fi

    log_info "Magento CLI 缺少 cms:page:create，改用 PHP API 更新页面 ${identifier}。"
    if ! magento_apply_cms_page_php "$identifier" "$title" "$store_ids" "$content_file" 1 "1column"; then
        log_warning "自动创建/更新 CMS 页面 ${identifier} 失败，请手动处理。"
    fi
}

summarize_install() {
    echo ""
    log_highlight "PWA 站点安装完成"
    cat <<EOF
- 站点目录: ${PWA_ROOT}
- 后台地址: ${PWA_BASE_URL_SECURE}${PWA_ADMIN_FRONTNAME}
- 管理员账号: ${PWA_ADMIN_USER} / ${PWA_ADMIN_PASSWORD}
- 数据库: ${PWA_DB_NAME} (${PWA_DB_USER}@${PWA_DB_HOST})
- OpenSearch: ${PWA_OPENSEARCH_SCHEME:-http}://${PWA_OPENSEARCH_HOST}:${PWA_OPENSEARCH_PORT} (index prefix: ${PWA_OPENSEARCH_PREFIX})
- Node.js: $(command_exists node && node --version || echo "未安装")
- Yarn: $(command_exists yarn && yarn --version || echo "未安装")
EOF
    if [[ "$PWA_WITH_FRONTEND" == "true" ]]; then
        cat <<EOF
- PWA Studio: ${PWA_STUDIO_DIR}
- PWA 环境文件: ${PWA_STUDIO_ENV_FILE}
EOF
    fi

    log_info "后续建议:"
    cat <<EOF
1. 配置 SSL 证书并运行: sudo saltgoat magetools varnish enable ${PWA_SITE_NAME}
2. 运行: sudo saltgoat magetools valkey-setup ${PWA_SITE_NAME} （如未自动执行）
3. 运行: sudo saltgoat magetools rabbitmq-salt smart ${PWA_SITE_NAME} （如未自动执行）
4. 如启用 PWA Studio，可将构建产物通过 Nginx/PM2 对外发布，详见 docs/MAGENTO_PWA.md。
EOF
}

install_site() {
    local site="$1"
    local pwa_override="$2"
    load_site_config "$site"
    if [[ -n "$pwa_override" ]]; then
        if [[ "$pwa_override" == "true" ]]; then
            PWA_WITH_FRONTEND="true"
        elif [[ "$pwa_override" == "false" ]]; then
            PWA_WITH_FRONTEND="false"
        fi
    fi
    ensure_node_yarn
    ensure_directory
    ensure_composer_project
    ensure_mysql_root_password
    ensure_mysql_log_bin_trust
    ensure_database
    run_magento_install
    post_install_tasks
    install_cron_if_needed
    configure_valkey_if_needed
    configure_rabbitmq_if_needed
    build_pwa_frontend
    ensure_pwa_service
    summarize_install
}

status_site() {
    local site="$1"
    load_site_config "$site"

    local service_name
    service_name="$(pwa_service_name)"
    local service_unit
    service_unit="$(pwa_service_unit)"
    local service_path
    service_path="$(pwa_service_path)"
    local service_exists="no"
    local service_active="inactive"
    local service_enabled="disabled"
    if systemd_unit_exists "$service_unit"; then
        service_exists="yes"
        service_active="$(systemctl is-active "$service_name" 2>/dev/null || echo "inactive")"
        service_enabled="$(systemctl is-enabled "$service_name" 2>/dev/null || echo "disabled")"
    fi

    local studio_dir_status="absent"
    [[ -d "$PWA_STUDIO_DIR" ]] && studio_dir_status="present"

    local env_file_status="absent"
    [[ -f "$PWA_STUDIO_ENV_FILE" ]] && env_file_status="present"

    local home_identifier="home"
    if identifier="$(read_pwa_env_value "MAGENTO_PWA_HOME_IDENTIFIER" 2>/dev/null)"; then
        if [[ -n "$identifier" ]]; then
            home_identifier="$identifier"
        fi
    fi

    local template_path
    template_path="$(resolve_home_template_file "$home_identifier")"
    local template_note
    if [[ -n "$template_path" ]]; then
        template_note="$template_path"
    else
        template_note="<占位模板>"
    fi

    local pillar_frontend="disabled"
    if is_true "${PWA_WITH_FRONTEND:-false}"; then
        pillar_frontend="enabled"
    fi
    if ! is_true "${PWA_WITH_FRONTEND:-false}" && is_true "${PWA_STUDIO_ENABLE:-false}"; then
        pillar_frontend="enabled"
    fi

    log_highlight "PWA 状态（${PWA_SITE_NAME}）"
    cat <<EOF
- Magento 根目录: ${PWA_ROOT}
- PWA Studio 目录: ${PWA_STUDIO_DIR} (${studio_dir_status})
- PWA 环境文件: ${PWA_STUDIO_ENV_FILE} (${env_file_status})
- CMS 首页标识: ${home_identifier}
- CMS 首页模板: ${template_note}
- Pillar 前端开关: ${pillar_frontend}
- systemd 服务: ${service_name} (exists=${service_exists}, active=${service_active}, enabled=${service_enabled})
- PWA 服务端口: ${PWA_STUDIO_PORT:-$DEFAULT_PWA_PORT}
EOF
    if [[ "$service_exists" == "no" ]]; then
        log_info "如需同步覆盖并创建服务，可执行: saltgoat pwa sync-content ${PWA_SITE_NAME} --pull --rebuild"
    fi
    log_pwa_home_identifier_hint
    if [[ "$pillar_frontend" == "enabled" ]]; then
        check_single_react_version
        graphql_ping
    fi
}

sync_site_content() {
    local site="$1"
    local do_pull="$2"
    local do_rebuild="$3"
    load_site_config "$site"

    if ! is_true "${PWA_WITH_FRONTEND:-false}" && ! is_true "${PWA_STUDIO_ENABLE:-false}"; then
        log_warning "Pillar 未启用 PWA Studio，但仍尝试同步。"
    fi
    if [[ ! -d "$PWA_STUDIO_DIR" ]]; then
        if is_true "$do_pull"; then
            log_info "PWA Studio 目录缺失，将重新克隆。"
        else
            log_warning "未检测到 PWA Studio 目录: ${PWA_STUDIO_DIR}，建议添加 --pull 重新获取仓库。"
        fi
    fi

    local previous_flag="${PWA_WITH_FRONTEND:-false}"
    PWA_WITH_FRONTEND="true"

    if is_true "$do_pull"; then
        prepare_pwa_repo
    elif [[ ! -d "$PWA_STUDIO_DIR/.git" ]]; then
        log_warning "PWA Studio 仓库未初始化，可使用 --pull 自动克隆。"
    fi

    if [[ -d "$PWA_STUDIO_DIR" ]]; then
        apply_mos_graphql_fixes
        prepare_pwa_env
        prune_unused_pwa_extensions
        ensure_pwa_home_cms_page
        log_pwa_home_identifier_hint
        if is_true "$do_rebuild"; then
            cleanup_package_lock
            ensure_pwa_root_peer_dependencies
            if ensure_pwa_env_vars; then
                run_yarn_task "${PWA_STUDIO_INSTALL_COMMAND:-yarn install}"
                run_yarn_task "${PWA_STUDIO_BUILD_COMMAND:-yarn build}"
            else
                log_warning "缺少必需的 PWA 环境变量，已跳过 Yarn 构建。"
            fi
        fi
        ensure_pwa_service
        log_highlight "PWA 内容同步完成（${PWA_SITE_NAME}）"
    else
        log_warning "同步已结束，但 PWA Studio 目录仍不存在，请检查配置或使用 --pull 重新获取。"
    fi

    PWA_WITH_FRONTEND="$previous_flag"
}

remove_site() {
    local site="$1"
    local purge="$2"
    load_site_config "$site"

    local service_name
    service_name="$(pwa_service_name)"
    local service_unit
    service_unit="$(pwa_service_unit)"
    local service_path
    service_path="$(pwa_service_path)"

    systemd_stop_unit "$service_unit"
    systemd_disable_unit "$service_unit"

    if [[ -f "$service_path" ]]; then
        rm -f "$service_path"
        log_info "已移除 systemd 服务文件: ${service_path}"
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi

    if is_true "$purge"; then
        if [[ -d "$PWA_STUDIO_DIR" ]]; then
            log_info "清理 PWA Studio 目录: ${PWA_STUDIO_DIR}"
            safe_remove_path "$PWA_STUDIO_DIR"
        else
            log_info "未检测到 PWA Studio 目录，无需清理。"
        fi
    else
        log_info "保留 PWA Studio 目录: ${PWA_STUDIO_DIR}"
    fi

    log_highlight "已完成 PWA 前端卸载（${PWA_SITE_NAME}）"
}

ACTION="${1:-}"
case "$ACTION" in
    ""|"help"|"-h"|"--help")
        usage
        ;;
    "install")
        shift
        SITE=""
        PWA_OVERRIDE=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --with-pwa)
                    PWA_OVERRIDE="true"
                    shift
                    ;;
                --no-pwa)
                    PWA_OVERRIDE="false"
                    shift
                    ;;
                --help|-h)
                    usage
                    exit 0
                    ;;
                -*)
                    abort "未知参数: $1"
                    ;;
                *)
                    if [[ -z "$SITE" ]]; then
                        SITE="$1"
                    else
                        abort "检测到多余参数: $1"
                    fi
                    shift
                    ;;
            esac
        done
        if [[ -z "$SITE" ]]; then
            abort "请提供站点名称，例如: saltgoat pwa install pwa"
        fi
        install_site "$SITE" "$PWA_OVERRIDE"
        ;;
    "status")
        shift
        if [[ $# -lt 1 ]]; then
            abort "请提供站点名称，例如: saltgoat pwa status pwa"
        fi
        SITE="$1"
        shift
        if [[ $# -gt 0 ]]; then
            abort "检测到多余参数: $*"
        fi
        status_site "$SITE"
        ;;
    "sync-content")
        shift
        SITE=""
        DO_PULL="false"
        DO_REBUILD="false"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --pull)
                    DO_PULL="true"
                    shift
                    ;;
                --rebuild)
                    DO_REBUILD="true"
                    shift
                    ;;
                --help|-h)
                    usage
                    exit 0
                    ;;
                -*)
                    abort "未知参数: $1"
                    ;;
                *)
                    if [[ -z "$SITE" ]]; then
                        SITE="$1"
                    else
                        abort "检测到多余参数: $1"
                    fi
                    shift
                    ;;
            esac
        done
        if [[ -z "$SITE" ]]; then
            abort "请提供站点名称，例如: saltgoat pwa sync-content pwa"
        fi
        sync_site_content "$SITE" "$DO_PULL" "$DO_REBUILD"
        ;;
    "remove")
        shift
        SITE=""
        PURGE="false"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --purge)
                    PURGE="true"
                    shift
                    ;;
                --help|-h)
                    usage
                    exit 0
                    ;;
                -*)
                    abort "未知参数: $1"
                    ;;
                *)
                    if [[ -z "$SITE" ]]; then
                        SITE="$1"
                    else
                        abort "检测到多余参数: $1"
                    fi
                    shift
                    ;;
            esac
        done
        if [[ -z "$SITE" ]]; then
            abort "请提供站点名称，例如: saltgoat pwa remove pwa"
        fi
        remove_site "$SITE" "$PURGE"
        ;;
    *)
        abort "未知操作: ${ACTION}。支持: install, status, sync-content, remove, help"
        ;;
esac

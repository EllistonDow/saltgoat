#!/bin/bash
# Magento 2 Valkey 配置（Salt 原生调用）
# 用法:
#   saltgoat magetools valkey-setup <site> [--cache-db N --page-db N --session-db N]
#                                    [--cache-prefix PREFIX] [--session-prefix PREFIX]
#                                    [--host HOST] [--port PORT] [--reuse-existing]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/utils.sh"

readonly DB_MIN=10
readonly DB_MAX=99
readonly VALKEY_CONF="/etc/valkey/valkey.conf"
readonly DEFAULT_VALKEY_HOST="127.0.0.1"
readonly DEFAULT_VALKEY_PORT="6379"

readonly DEFAULT_COMPRESS_DATA="1"
readonly DEFAULT_TIMEOUT="2.5"
readonly DEFAULT_MAX_CONCURRENCY="6"
readonly DEFAULT_BREAK_FRONTEND="5"
readonly DEFAULT_BREAK_ADMIN="30"
readonly DEFAULT_FIRST_LIFETIME="600"
readonly DEFAULT_BOT_FIRST_LIFETIME="60"
readonly DEFAULT_BOT_LIFETIME="7200"
readonly DEFAULT_DISABLE_LOCKING="0"
readonly DEFAULT_MIN_LIFETIME="60"
readonly DEFAULT_MAX_LIFETIME="2592000"

SITE_NAME=""
SITE_PATH=""
SITE_REALPATH=""
ENV_FILE=""

VALKEY_PASSWORD=""
VALKEY_HOST="$DEFAULT_VALKEY_HOST"
VALKEY_PORT="$DEFAULT_VALKEY_PORT"

CACHE_DB_OVERRIDE=""
PAGE_DB_OVERRIDE=""
SESSION_DB_OVERRIDE=""
CACHE_PREFIX_OVERRIDE=""
SESSION_PREFIX_OVERRIDE=""

CACHE_DB=""
PAGE_DB=""
SESSION_DB=""
CACHE_PREFIX=""
SESSION_PREFIX=""

REUSE_EXISTING=false
REUSE_FLAG_SET=false
EXISTING_REDIS=false
EXISTING_CACHE_DB=""
EXISTING_PAGE_DB=""
EXISTING_SESSION_DB=""
EXISTING_CACHE_PREFIX=""
EXISTING_SESSION_PREFIX=""

ASSIGNMENTS_CHANGED=false
ENV_BACKUP_PATH=""
PILLAR_JSON=""

declare -a ORIGINAL_SELF_DBS=()
declare -a REDIS_CLI_ARGS=()
declare -A USED_BY_OTHER=()
declare -A USED_BY_SELF=()
declare -i CLEANED_DB_COUNT=0

usage() {
    cat <<'EOF'
SaltGoat Magento Valkey 配置工具 (Salt)

用法:
  saltgoat magetools valkey-setup <site> [选项]

选项:
  --cache-db N         指定默认缓存数据库编号
  --page-db N          指定页面缓存数据库编号
  --session-db N       指定会话数据库编号
  --cache-prefix STR   指定缓存前缀（默认 <site>_cache_）
  --session-prefix STR 指定会话前缀（默认 <site>_session_）
  --host HOST          Valkey 主机地址（默认 127.0.0.1）
  --port PORT          Valkey 端口（默认 6379）
  --reuse-existing     如 env.php 已配置 Redis，则继续沿用原数据库编号
  --no-reuse           强制重新分配数据库编号（默认行为）
  -h, --help           显示帮助信息
EOF
}

abort() {
    local message="$1"
    log_error "$message"
    exit 1
}

validate_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

validate_db_number() {
    local value="$1"
    if ! validate_integer "$value"; then
        abort "数据库编号必须是整数: $value"
    fi
    if (( value < DB_MIN || value > DB_MAX )); then
        abort "数据库编号需位于 ${DB_MIN}-${DB_MAX} 范围: $value"
    fi
}

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        abort "缺少必要命令: $cmd"
    fi
}

parse_args() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cache-db)
                [[ $# -lt 2 ]] && abort "--cache-db 需要一个值"
                CACHE_DB_OVERRIDE="$2"
                shift 2
                ;;
            --page-db)
                [[ $# -lt 2 ]] && abort "--page-db 需要一个值"
                PAGE_DB_OVERRIDE="$2"
                shift 2
                ;;
            --session-db)
                [[ $# -lt 2 ]] && abort "--session-db 需要一个值"
                SESSION_DB_OVERRIDE="$2"
                shift 2
                ;;
            --cache-prefix)
                [[ $# -lt 2 ]] && abort "--cache-prefix 需要一个值"
                CACHE_PREFIX_OVERRIDE="$2"
                shift 2
                ;;
            --session-prefix)
                [[ $# -lt 2 ]] && abort "--session-prefix 需要一个值"
                SESSION_PREFIX_OVERRIDE="$2"
                shift 2
                ;;
            --host)
                [[ $# -lt 2 ]] && abort "--host 需要一个值"
                VALKEY_HOST="$2"
                shift 2
                ;;
            --port)
                [[ $# -lt 2 ]] && abort "--port 需要一个值"
                VALKEY_PORT="$2"
                shift 2
                ;;
            --reuse-existing)
                REUSE_EXISTING=true
                REUSE_FLAG_SET=true
                shift
                ;;
            --no-reuse)
                REUSE_EXISTING=false
                REUSE_FLAG_SET=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                abort "未知参数: $1"
                ;;
            *)
                if [[ -z "$SITE_NAME" ]]; then
                    SITE_NAME="$1"
                    shift
                else
                    abort "多余的位置参数: $1"
                fi
                ;;
        esac
    done

    if [[ -z "$SITE_NAME" ]]; then
        abort "必须指定站点名称"
    fi
    if [[ "$SITE_NAME" =~ [^a-zA-Z0-9_-] ]]; then
        abort "站点名称包含非法字符: $SITE_NAME"
    fi
}

ensure_prerequisites() {
    require_command salt-call
    require_command php
    require_command python3
    require_command redis-cli

    if [[ -n "$CACHE_DB_OVERRIDE" ]]; then
        validate_db_number "$CACHE_DB_OVERRIDE"
    fi
    if [[ -n "$PAGE_DB_OVERRIDE" ]]; then
        validate_db_number "$PAGE_DB_OVERRIDE"
    fi
    if [[ -n "$SESSION_DB_OVERRIDE" ]]; then
        validate_db_number "$SESSION_DB_OVERRIDE"
    fi
    if ! validate_integer "$VALKEY_PORT"; then
        abort "Valkey 端口必须为整数: $VALKEY_PORT"
    fi
}

resolve_site() {
    SITE_PATH="/var/www/${SITE_NAME}"
    if [[ ! -d "$SITE_PATH" ]]; then
        abort "站点路径不存在: $SITE_PATH"
    fi
    ENV_FILE="${SITE_PATH}/app/etc/env.php"
    if [[ ! -f "$ENV_FILE" ]]; then
        abort "未找到 Magento 配置文件: $ENV_FILE"
    fi
    if [[ ! -f "${SITE_PATH}/bin/magento" ]]; then
        abort "未找到 Magento CLI: ${SITE_PATH}/bin/magento"
    fi
    SITE_REALPATH="$(readlink -f "$SITE_PATH")"
}

read_existing_config() {
    EXISTING_REDIS=false
    EXISTING_CACHE_DB=""
    EXISTING_PAGE_DB=""
    EXISTING_SESSION_DB=""
    EXISTING_CACHE_PREFIX=""
    EXISTING_SESSION_PREFIX=""

    while IFS='=' read -r key value; do
        case "$key" in
            uses_redis)
                [[ "$value" == "1" ]] && EXISTING_REDIS=true
                ;;
            cache_db)
                EXISTING_CACHE_DB="$value"
                ;;
            page_db)
                EXISTING_PAGE_DB="$value"
                ;;
            session_db)
                EXISTING_SESSION_DB="$value"
                ;;
            cache_prefix)
                EXISTING_CACHE_PREFIX="$value"
                ;;
            session_prefix)
                EXISTING_SESSION_PREFIX="$value"
                ;;
        esac
    done < <(
        ENV_FILE="$ENV_FILE" php <<'PHP'
<?php
$envFile = getenv('ENV_FILE');
$result = [
    'uses_redis' => '0',
    'cache_db' => '',
    'page_db' => '',
    'session_db' => '',
    'cache_prefix' => '',
    'session_prefix' => '',
];
if ($envFile && file_exists($envFile)) {
    $config = include $envFile;
    if (is_array($config)) {
        $default = $config['cache']['frontend']['default'] ?? [];
        if (($default['backend'] ?? '') === 'Magento\\Framework\\Cache\\Backend\\Redis') {
            $result['uses_redis'] = '1';
            $options = $default['backend_options'] ?? [];
            if (isset($options['database'])) {
                $result['cache_db'] = (string)$options['database'];
            }
            if (isset($options['id_prefix'])) {
                $result['cache_prefix'] = (string)$options['id_prefix'];
            }
        }
        $page = $config['cache']['frontend']['page_cache'] ?? [];
        if (($page['backend'] ?? '') === 'Magento\\Framework\\Cache\\Backend\\Redis') {
            $options = $page['backend_options'] ?? [];
            if (isset($options['database'])) {
                $result['page_db'] = (string)$options['database'];
            }
            if ($result['cache_prefix'] === '' && isset($options['id_prefix'])) {
                $result['cache_prefix'] = (string)$options['id_prefix'];
            }
        }
        if (($config['session']['save'] ?? '') === 'redis') {
            $session = $config['session']['redis'] ?? [];
            if (isset($session['database'])) {
                $result['session_db'] = (string)$session['database'];
            }
            if (isset($session['id_prefix'])) {
                $result['session_prefix'] = (string)$session['id_prefix'];
            }
        }
    }
}
foreach ($result as $key => $value) {
    echo $key, '=', $value, PHP_EOL;
}
PHP
    )
}

collect_database_usage() {
    USED_BY_OTHER=()
    USED_BY_SELF=()
    ORIGINAL_SELF_DBS=()

    while IFS='|' read -r db path; do
        [[ -z "$db" ]] && continue
        if [[ -n "$path" && "$path" == "$SITE_REALPATH" ]]; then
            USED_BY_SELF["$db"]=1
            ORIGINAL_SELF_DBS+=("$db")
        elif [[ -n "$path" ]]; then
            USED_BY_OTHER["$db"]="$path"
        fi
    done < <(
        php <<'PHP'
<?php
$paths = glob('/var/www/*/app/etc/env.php', GLOB_NOSORT);
foreach ($paths as $env) {
    $root = realpath(dirname(dirname(dirname($env))));
    if ($root === false) {
        continue;
    }
    $config = @include $env;
    if (!is_array($config)) {
        continue;
    }
    $dbs = [];
    $default = $config['cache']['frontend']['default']['backend_options']['database'] ?? null;
    if ($default !== null && ctype_digit((string)$default)) {
        $dbs[] = (int)$default;
    }
    $page = $config['cache']['frontend']['page_cache']['backend_options']['database'] ?? null;
    if ($page !== null && ctype_digit((string)$page)) {
        $dbs[] = (int)$page;
    }
    if (($config['session']['save'] ?? '') === 'redis') {
         $session = $config['session']['redis']['database'] ?? null;
         if ($session !== null && ctype_digit((string)$session)) {
             $dbs[] = (int)$session;
         }
    }
    if (!$dbs) {
        continue;
    }
    $dbs = array_unique($dbs);
    foreach ($dbs as $db) {
        echo $db, '|', $root, PHP_EOL;
    }
}
PHP
    )
}

pick_available_db() {
    local -a skip_list=("$@")
    local -A skip=()
    local value db

    for value in "${skip_list[@]}"; do
        [[ -n "$value" ]] && skip["$value"]=1
    done

    for ((db = DB_MIN; db <= DB_MAX; db++)); do
        if [[ -n "${skip[$db]:-}" ]]; then
            continue
        fi
        if [[ -n "${USED_BY_OTHER[$db]:-}" ]]; then
            continue
        fi
        if [[ "$REUSE_EXISTING" != true && -n "${USED_BY_SELF[$db]:-}" ]]; then
            continue
        fi
        echo "$db"
        return 0
    done

    return 1
}

assign_databases() {
    local -a chosen=()
    ASSIGNMENTS_CHANGED=false

    if [[ "$REUSE_FLAG_SET" == false && "$EXISTING_REDIS" == true ]]; then
        REUSE_EXISTING=true
    fi

    CACHE_PREFIX="${CACHE_PREFIX_OVERRIDE:-${EXISTING_CACHE_PREFIX:-${SITE_NAME}_cache_}}"
    SESSION_PREFIX="${SESSION_PREFIX_OVERRIDE:-${EXISTING_SESSION_PREFIX:-${SITE_NAME}_session_}}"

    if [[ -n "$CACHE_DB_OVERRIDE" ]]; then
        CACHE_DB="$CACHE_DB_OVERRIDE"
    elif [[ "$REUSE_EXISTING" == true && "$EXISTING_REDIS" == true && -n "$EXISTING_CACHE_DB" ]]; then
        CACHE_DB="$EXISTING_CACHE_DB"
    fi

    if [[ -n "$PAGE_DB_OVERRIDE" ]]; then
        PAGE_DB="$PAGE_DB_OVERRIDE"
    elif [[ "$REUSE_EXISTING" == true && "$EXISTING_REDIS" == true && -n "$EXISTING_PAGE_DB" ]]; then
        PAGE_DB="$EXISTING_PAGE_DB"
    fi

    if [[ -n "$SESSION_DB_OVERRIDE" ]]; then
        SESSION_DB="$SESSION_DB_OVERRIDE"
    elif [[ "$REUSE_EXISTING" == true && -n "$EXISTING_SESSION_DB" ]]; then
        SESSION_DB="$EXISTING_SESSION_DB"
    fi

    if [[ -z "$CACHE_DB" ]]; then
        CACHE_DB="$(pick_available_db "${chosen[@]}")" || abort "无法找到可用的默认缓存数据库"
    fi
    chosen+=("$CACHE_DB")

    if [[ -z "$PAGE_DB" ]]; then
        PAGE_DB="$(pick_available_db "${chosen[@]}")" || abort "无法找到可用的页面缓存数据库"
    fi
    chosen+=("$PAGE_DB")

    if [[ -z "$SESSION_DB" ]]; then
        SESSION_DB="$(pick_available_db "${chosen[@]}")" || abort "无法找到可用的会话数据库"
    fi
    chosen+=("$SESSION_DB")

    validate_db_number "$CACHE_DB"
    validate_db_number "$PAGE_DB"
    validate_db_number "$SESSION_DB"

    if [[ "$CACHE_DB" == "$PAGE_DB" || "$CACHE_DB" == "$SESSION_DB" || "$PAGE_DB" == "$SESSION_DB" ]]; then
        abort "缓存与会话数据库编号必须唯一: $CACHE_DB/$PAGE_DB/$SESSION_DB"
    fi

    local db
    for db in "$CACHE_DB" "$PAGE_DB" "$SESSION_DB"; do
        if [[ -n "${USED_BY_OTHER[$db]:-}" ]]; then
            abort "数据库编号 $db 已被站点 ${USED_BY_OTHER[$db]} 使用"
        fi
    done

    if [[ -n "$EXISTING_CACHE_DB" && "$CACHE_DB" != "$EXISTING_CACHE_DB" ]]; then
        ASSIGNMENTS_CHANGED=true
    fi
    if [[ -n "$EXISTING_PAGE_DB" && "$PAGE_DB" != "$EXISTING_PAGE_DB" ]]; then
        ASSIGNMENTS_CHANGED=true
    fi
    if [[ -n "$EXISTING_SESSION_DB" && "$SESSION_DB" != "$EXISTING_SESSION_DB" ]]; then
        ASSIGNMENTS_CHANGED=true
    fi
}

fetch_valkey_password() {
    if [[ -r "$VALKEY_CONF" ]]; then
        VALKEY_PASSWORD="$(awk '/^\s*requirepass/{print $2}' "$VALKEY_CONF" | tail -n 1 || true)"
    fi

    if [[ -z "$VALKEY_PASSWORD" ]]; then
        local output
        if output="$(salt-call --local --out=json pillar.get valkey_password 2>/dev/null)"; then
            VALKEY_PASSWORD="$(python3 -c 'import json, sys
try:
    data = json.load(sys.stdin)
    value = data.get("local", "")
    if isinstance(value, (dict, list)):
        value = ""
except Exception:
    value = ""
print(value if value is not None else "")' <<<"$output")"
        fi
    fi

    if [[ -z "$VALKEY_PASSWORD" ]]; then
        abort "无法获取 Valkey 密码，请确认 /etc/valkey/valkey.conf 或 pillar 中存在 requirepass 配置"
    fi
}

build_redis_cli_args() {
    REDIS_CLI_ARGS=(-h "$VALKEY_HOST" -p "$VALKEY_PORT" --no-auth-warning)
    if [[ -n "$VALKEY_PASSWORD" ]]; then
        REDIS_CLI_ARGS+=(-a "$VALKEY_PASSWORD")
    fi
}

ensure_valkey_connection() {
    build_redis_cli_args
    if ! redis-cli "${REDIS_CLI_ARGS[@]}" ping >/dev/null 2>&1; then
        abort "无法连接到 Valkey (${VALKEY_HOST}:${VALKEY_PORT})，请确认服务状态和密码"
    fi
}

redis_cli() {
    redis-cli "${REDIS_CLI_ARGS[@]}" "$@"
}

create_env_backup() {
    local timestamp dest_dir
    timestamp="$(date +%Y%m%d_%H%M%S)"
    dest_dir="/tmp/saltgoat/valkey/${SITE_NAME}/${timestamp}"
    if ! mkdir -p "$dest_dir"; then
        log_warning "创建备份目录失败: $dest_dir"
        return
    fi
    if cp "$ENV_FILE" "${dest_dir}/env.php"; then
        ENV_BACKUP_PATH="${dest_dir}/env.php"
        log_success "已备份 env.php 至: $ENV_BACKUP_PATH"
    else
        log_warning "备份 env.php 失败，继续执行"
    fi
}

build_pillar_payload() {
    export PILLAR_SITE_NAME="$SITE_NAME"
    export PILLAR_SITE_PATH="$SITE_PATH"
    export PILLAR_VALKEY_PASSWORD="$VALKEY_PASSWORD"
    export PILLAR_CACHE_DB="$CACHE_DB"
    export PILLAR_PAGE_DB="$PAGE_DB"
    export PILLAR_SESSION_DB="$SESSION_DB"
    export PILLAR_CACHE_PREFIX="$CACHE_PREFIX"
    export PILLAR_SESSION_PREFIX="$SESSION_PREFIX"
    export PILLAR_VALKEY_HOST="$VALKEY_HOST"
    export PILLAR_VALKEY_PORT="$VALKEY_PORT"
    export PILLAR_COMPRESS="$DEFAULT_COMPRESS_DATA"
    export PILLAR_TIMEOUT="$DEFAULT_TIMEOUT"
    export PILLAR_MAX_CONCURRENCY="$DEFAULT_MAX_CONCURRENCY"
    export PILLAR_BREAK_FRONTEND="$DEFAULT_BREAK_FRONTEND"
    export PILLAR_BREAK_ADMIN="$DEFAULT_BREAK_ADMIN"
    export PILLAR_FIRST_LIFETIME="$DEFAULT_FIRST_LIFETIME"
    export PILLAR_BOT_FIRST_LIFETIME="$DEFAULT_BOT_FIRST_LIFETIME"
    export PILLAR_BOT_LIFETIME="$DEFAULT_BOT_LIFETIME"
    export PILLAR_DISABLE_LOCKING="$DEFAULT_DISABLE_LOCKING"
    export PILLAR_MIN_LIFETIME="$DEFAULT_MIN_LIFETIME"
    export PILLAR_MAX_LIFETIME="$DEFAULT_MAX_LIFETIME"

    PILLAR_JSON="$(python3 <<'PY'
import json
import os

payload = {
    "site_name": os.environ["PILLAR_SITE_NAME"],
    "site_path": os.environ["PILLAR_SITE_PATH"],
    "valkey_password": os.environ["PILLAR_VALKEY_PASSWORD"],
    "cache_db": int(os.environ["PILLAR_CACHE_DB"]),
    "page_db": int(os.environ["PILLAR_PAGE_DB"]),
    "session_db": int(os.environ["PILLAR_SESSION_DB"]),
    "cache_prefix": os.environ["PILLAR_CACHE_PREFIX"],
    "session_prefix": os.environ["PILLAR_SESSION_PREFIX"],
    "valkey_host": os.environ["PILLAR_VALKEY_HOST"],
    "valkey_port": int(os.environ["PILLAR_VALKEY_PORT"]),
    "compress_data": os.environ["PILLAR_COMPRESS"],
    "timeout": os.environ["PILLAR_TIMEOUT"],
    "max_concurrency": os.environ["PILLAR_MAX_CONCURRENCY"],
    "break_after_frontend": os.environ["PILLAR_BREAK_FRONTEND"],
    "break_after_adminhtml": os.environ["PILLAR_BREAK_ADMIN"],
    "first_lifetime": os.environ["PILLAR_FIRST_LIFETIME"],
    "bot_first_lifetime": os.environ["PILLAR_BOT_FIRST_LIFETIME"],
    "bot_lifetime": os.environ["PILLAR_BOT_LIFETIME"],
    "disable_locking": os.environ["PILLAR_DISABLE_LOCKING"],
    "min_lifetime": os.environ["PILLAR_MIN_LIFETIME"],
    "max_lifetime": os.environ["PILLAR_MAX_LIFETIME"],
}

print(json.dumps(payload, ensure_ascii=False))
PY
)"
}

apply_salt_state() {
    log_info "应用 Salt 状态 optional.magento-valkey ..."
    if ! salt-call --local --retcode-passthrough state.apply optional.magento-valkey pillar="$PILLAR_JSON"; then
        abort "Salt 状态执行失败"
    fi
}

cleanup_replaced_databases() {
    CLEANED_DB_COUNT=0
    if [[ "$ASSIGNMENTS_CHANGED" != true ]]; then
        return
    fi
    if [[ ${#ORIGINAL_SELF_DBS[@]} -eq 0 ]]; then
        return
    fi

    declare -A current_dbs=()
    current_dbs["$CACHE_DB"]=1
    current_dbs["$PAGE_DB"]=1
    current_dbs["$SESSION_DB"]=1

    local db cleaned=0
    for db in "${ORIGINAL_SELF_DBS[@]}"; do
        if [[ -n "${current_dbs[$db]:-}" ]]; then
            continue
        fi
        if [[ -n "${USED_BY_OTHER[$db]:-}" ]]; then
            log_warning "跳过清理 DB $db，检测到其他站点使用: ${USED_BY_OTHER[$db]}"
            continue
        fi
        log_info "清理站点 ${SITE_NAME} 之前使用的 Valkey 数据库: DB $db"
        if redis_cli -n "$db" flushdb >/dev/null 2>&1; then
            ((cleaned++))
        else
            log_warning "清理 DB $db 失败"
        fi
    done

    if (( cleaned > 0 )); then
        log_success "已清理 ${cleaned} 个站点旧数据库"
    fi
    CLEANED_DB_COUNT=$cleaned
}

print_summary() {
    echo ""
    log_highlight "Valkey 配置完成:"
    echo "  站点路径: $SITE_PATH"
    echo "  默认缓存 DB: $CACHE_DB"
    echo "  页面缓存 DB: $PAGE_DB"
    echo "  会话 DB: $SESSION_DB"
    echo "  缓存前缀: $CACHE_PREFIX"
    echo "  会话前缀: $SESSION_PREFIX"
    if [[ -n "$ENV_BACKUP_PATH" ]]; then
        echo "  备份文件: $ENV_BACKUP_PATH"
    fi
    if (( ${#ORIGINAL_SELF_DBS[@]} > 0 )); then
        echo "  原站点已使用 DB: ${ORIGINAL_SELF_DBS[*]}"
    fi
    if [[ "$ASSIGNMENTS_CHANGED" == true ]]; then
        echo "  状态: 已重新分配数据库编号"
    else
        echo "  状态: 沿用现有数据库编号"
    fi
    if (( CLEANED_DB_COUNT > 0 )); then
        echo "  清理旧 DB 数: $CLEANED_DB_COUNT"
    fi
    echo ""
    log_info "建议后续操作:"
    echo "  cd $SITE_PATH"
    echo "  sudo -u www-data php bin/magento cache:status"
    echo "  sudo -u www-data php bin/magento cache:flush"
    echo ""
    log_success "Salt 原生 Valkey 配置已完成。"
}

main() {
    parse_args "$@"
    ensure_prerequisites
    resolve_site
    read_existing_config
    collect_database_usage
    assign_databases
    fetch_valkey_password
    ensure_valkey_connection
    create_env_backup
    build_pillar_payload
    apply_salt_state
    cleanup_replaced_databases
    print_summary
}

main "$@"

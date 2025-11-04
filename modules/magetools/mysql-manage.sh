#!/bin/bash
# MySQL database management helpers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../lib/logger.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"
# shellcheck source=../../lib/utils.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/utils.sh"

MYSQL_HELPER="${SCRIPT_DIR}/modules/lib/mysql_salt_helper.py"
declare -a MYSQL_CONNECTION_ARGS=()
SALT_CALL_RESULT=""
MYSQL_ROOT_PASSWORD=""
LAST_SALT_OUTPUT=""

usage() {
    cat <<'USAGE'
用法:
  saltgoat magetools mysql create --database <name> --user <user> --password <pass> [选项]
  saltgoat magetools mysql drop [--database <name>] [--user <user>] [选项]
  saltgoat magetools mysql restore --database <name> --dump <file.sql[.gz]> [选项]

create 选项:
  --host <host>           MySQL 主机，默认 localhost
  --charset <charset>     数据库字符集，默认 utf8mb4
  --collation <collation> 数据库排序规则，默认 utf8mb4_unicode_ci
  --no-super              不授予 SUPER/PROCESS 全局权限
  --help                  显示此帮助

drop 选项:
  --database <name>       要删除的数据库名称（可搭配 --keep-db 保留）
  --user <user>           要删除的账号（可搭配 --keep-user 保留）
  --host <host>           删除账号时使用的 host，默认 localhost
  --keep-db               保留数据库，仅删除账号
  --keep-user             保留账号，仅删除数据库
  --help                  显示此帮助

restore 选项:
  --database <name>       目标数据库名称（必填）
  --dump <file>           备份文件路径，支持 .sql 与 .sql.gz（必填）
  --host <host>           MySQL 主机，默认 localhost
  --create-db             若数据库不存在则创建（使用 utf8mb4/utf8mb4_unicode_ci）
  --drop-existing         在恢复前删除并重新创建数据库
  --charset <charset>     搭配 --create-db 使用时指定字符集
  --collation <collation> 搭配 --create-db 使用时指定排序规则
  --yes                   跳过交互确认
  --help                  显示此帮助

说明:
  - 自动创建数据库（若不存在）与账号；若账号已存在会跳过重复创建。
  - 默认授予 ALL PRIVILEGES ON <database>.* 以及 PROCESS、SUPER（可用 --no-super 关闭）。
  - drop 命令至少需要 --database 或 --user 之一，可通过 --keep-* 精细控制。
  - root 密码来自 Pillar 的 mysql_password，可通过 `saltgoat passwords` 查看。
USAGE
}

salt_call_bool() {
    local func="$1"
    shift || true
    local output
    output="$(PYTHONWARNINGS="ignore" salt-call --local --out=json --retcode-passthrough "$func" "$@" "${MYSQL_CONNECTION_ARGS[@]}" 2>&1)" || {
        log_error "Salt 调用失败: salt-call --local $func"
        printf '%s\n' "$output"
        exit 1
    }
    LAST_SALT_OUTPUT="$output"
    if [[ ! -x "$MYSQL_HELPER" ]]; then
        log_error "缺少 mysql helper: $MYSQL_HELPER"
        exit 1
    fi
    SALT_CALL_RESULT="$(python3 "$MYSQL_HELPER" bool --payload "$output")"
}

salt_call_run() {
    local func="$1"
    shift || true
    local output
    output="$(PYTHONWARNINGS="ignore" salt-call --local --retcode-passthrough "$func" "$@" "${MYSQL_CONNECTION_ARGS[@]}" 2>&1)" || {
        log_error "Salt 调用失败: salt-call --local $func"
        printf '%s\n' "$output"
        exit 1
    }
    LAST_SALT_OUTPUT="$output"
}

require_root_password() {
    local pillar_pass
    pillar_pass="$(get_local_pillar_value mysql_password || true)"
    if [[ -z "$pillar_pass" ]]; then
        log_error "未在 Pillar 中找到 mysql_password，无法执行操作"
        exit 1
    fi
    echo "$pillar_pass"
}

prepare_mysql_connection() {
    local db_host="$1"
    MYSQL_ROOT_PASSWORD="$(require_root_password)"
    MYSQL_CONNECTION_ARGS=("connection_user=root" "connection_pass=$MYSQL_ROOT_PASSWORD")
    if [[ "$db_host" == "localhost" || "$db_host" == "127.0.0.1" || "$db_host" == "::1" ]]; then
        MYSQL_CONNECTION_ARGS+=("connection_socket=/var/run/mysqld/mysqld.sock")
    else
        MYSQL_CONNECTION_ARGS+=("connection_host=$db_host")
    fi
}

create_database() {
    local db_name="$1"
    local charset="$2"
    local collation="$3"

    salt_call_bool mysql.db_exists "$db_name"
    if [[ "$SALT_CALL_RESULT" == "1" ]]; then
        log_info "数据库已存在，跳过创建：$db_name"
        return
    fi

    log_info "创建数据库：$db_name (charset=$charset collation=$collation)"
    salt_call_run mysql.db_create "$db_name" "character_set=$charset" "collate=$collation"
}

create_user() {
    local user="$1"
    local host="$2"
    local password="$3"

    salt_call_bool mysql.user_exists "$user" "host=$host"
    if [[ "$SALT_CALL_RESULT" == "1" ]]; then
        log_info "账号已存在，更新密码：$user@$host"
        salt_call_run mysql.user_chpass "$user" "$host" "$password"
        return
    fi

    log_info "创建账号：$user@$host"
    salt_call_run mysql.user_create "$user" "host=$host" "password=$password" "auth_plugin=caching_sha2_password"
    salt_call_bool mysql.user_exists "$user" "host=$host"
    if [[ "$SALT_CALL_RESULT" != "1" ]]; then
        log_error "账号 $user@$host 创建失败"
        printf '%s\n' "$LAST_SALT_OUTPUT"
        exit 1
    fi
}

grants_for_user() {
    local user="$1"
    local host="$2"
    local db_name="$3"
    local include_super="$4"

    log_info "授权 $user@$host 对 $db_name.*"
    salt_call_run mysql.grant_add "ALL PRIVILEGES" "${db_name}.*" "$user" "host=$host"

    if [[ "$include_super" == "1" ]]; then
        log_info "授予 SUPER, PROCESS 全局权限"
        salt_call_run mysql.grant_add "SUPER, PROCESS" "*.*" "$user" "host=$host"
    else
        salt_call_bool mysql.grant_exists "SUPER, PROCESS" "*.*" "$user" "host=$host"
        if [[ "$SALT_CALL_RESULT" == "1" ]]; then
            log_info "移除 SUPER, PROCESS 全局权限"
            salt_call_run mysql.grant_revoke "SUPER, PROCESS" "*.*" "$user" "host=$host"
        else
            log_info "账号未持有 SUPER/PROCESS，全局权限保持最小化"
        fi
    fi

    salt_call_run mysql.query "query=FLUSH PRIVILEGES;" "database=mysql"
}

handle_create() {
    local db_name=""
    local db_user=""
    local db_pass=""
    local db_host="localhost"
    local charset="utf8mb4"
    local collation="utf8mb4_unicode_ci"
    local include_super=1

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --database|--db)
                db_name="${2:-}"
                shift 2
                ;;
            --user|--username)
                db_user="${2:-}"
                shift 2
                ;;
            --password|--pass)
                db_pass="${2:-}"
                shift 2
                ;;
            --host)
                db_host="${2:-}"
                shift 2
                ;;
            --charset)
                charset="${2:-}"
                shift 2
                ;;
            --collation)
                collation="${2:-}"
                shift 2
                ;;
            --no-super)
                include_super=0
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done

    if [[ -z "$db_name" || -z "$db_user" || -z "$db_pass" ]]; then
        log_error "--database、--user、--password 为必填项"
        usage
        exit 1
    fi
    prepare_mysql_connection "$db_host"

    create_database "$db_name" "$charset" "$collation"
    create_user "$db_user" "$db_host" "$db_pass"
    grants_for_user "$db_user" "$db_host" "$db_name" "$include_super"

    log_success "数据库 $db_name 与账号 $db_user@$db_host 创建/更新完成"
}

handle_drop() {
    local db_name=""
    local db_user=""
    local db_host="localhost"
    local drop_db=0
    local drop_user=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --database|--db)
                db_name="${2:-}"
                drop_db=1
                shift 2
                ;;
            --user|--username)
                db_user="${2:-}"
                drop_user=1
                shift 2
                ;;
            --host)
                db_host="${2:-}"
                shift 2
                ;;
            --keep-db)
                drop_db=0
                shift
                ;;
            --keep-user)
                drop_user=0
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done

    if (( drop_db == 0 && drop_user == 0 )); then
        log_error "drop 命令需要至少提供 --database 或 --user"
        usage
        exit 1
    fi

    if (( drop_db == 1 )) && [[ -z "$db_name" ]]; then
        log_error "--database 值为空"
        exit 1
    fi
    if (( drop_user == 1 )) && [[ -z "$db_user" ]]; then
        log_error "--user 值为空"
        exit 1
    fi

    prepare_mysql_connection "$db_host"

    local changed=0

    if (( drop_db == 1 )); then
        salt_call_bool mysql.db_exists "$db_name"
        if [[ "$SALT_CALL_RESULT" == "1" ]]; then
            log_info "删除数据库：$db_name"
            salt_call_run mysql.db_remove "$db_name"
            changed=1
        else
            log_info "数据库不存在，跳过删除：$db_name"
        fi
    fi

    if (( drop_user == 1 )); then
        salt_call_bool mysql.user_exists "$db_user" "host=$db_host"
        if [[ "$SALT_CALL_RESULT" == "1" ]]; then
            log_info "删除账号：$db_user@$db_host"
            salt_call_run mysql.user_remove "$db_user" "$db_host"
            changed=1
        else
            log_info "账号不存在，跳过删除：$db_user@$db_host"
        fi
    fi

    if (( changed == 1 )); then
        salt_call_run mysql.query "query=FLUSH PRIVILEGES;" "database=mysql"
    fi

    log_success "数据库/账号删除完成"
}

handle_restore() {
    local db_name=""
    local dump_path=""
    local db_host="localhost"
    local create_db=0
    local drop_existing=0
    local skip_confirm=0
    local charset="utf8mb4"
    local collation="utf8mb4_unicode_ci"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --database|--db)
                db_name="${2:-}"
                shift 2
                ;;
            --dump|--file)
                dump_path="${2:-}"
                shift 2
                ;;
            --host)
                db_host="${2:-}"
                shift 2
                ;;
            --create-db|--create)
                create_db=1
                shift
                ;;
            --drop-existing|--fresh)
                drop_existing=1
                create_db=1
                shift
                ;;
            --charset)
                charset="${2:-}"
                shift 2
                ;;
            --collation)
                collation="${2:-}"
                shift 2
                ;;
            --yes|-y|--skip-confirm)
                skip_confirm=1
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done

    if [[ -z "$db_name" ]]; then
        log_error "restore 需要通过 --database 指定目标数据库"
        usage
        exit 1
    fi
    if [[ -z "$dump_path" ]]; then
        log_error "restore 需要通过 --dump 指定备份文件路径"
        usage
        exit 1
    fi

    dump_path="$(python3 - "$dump_path" <<'PY'
import os, sys
print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
)"

    if [[ ! -f "$dump_path" ]]; then
        log_error "备份文件不存在: $dump_path"
        exit 1
    fi

    prepare_mysql_connection "$db_host"

    local db_exists=0
    salt_call_bool mysql.db_exists "$db_name"
    if [[ "$SALT_CALL_RESULT" == "1" ]]; then
        db_exists=1
    fi

    if (( db_exists == 1 && drop_existing == 0 && skip_confirm == 0 )); then
        log_warning "数据库 $db_name 已存在，导入将覆盖现有数据。"
        read -r -p "确认导入到 $db_name? [y/N]: " answer
        if [[ "${answer:-}" != "y" && "${answer:-}" != "Y" ]]; then
            log_info "操作已取消"
            exit 0
        fi
    fi

    if (( drop_existing == 1 )) && (( db_exists == 1 )); then
        if (( skip_confirm == 0 )); then
            read -r -p "将删除并重建 $db_name，是否继续? [y/N]: " confirm_drop
            if [[ "${confirm_drop:-}" != "y" && "${confirm_drop:-}" != "Y" ]]; then
                log_info "操作已取消"
                exit 0
            fi
        fi
        log_warning "删除数据库：$db_name"
        salt_call_run mysql.db_remove "$db_name"
        db_exists=0
    fi

    if (( create_db == 1 )) && (( db_exists == 0 )); then
        log_info "创建数据库：$db_name (charset=$charset collation=$collation)"
        salt_call_run mysql.db_create "$db_name" "character_set=$charset" "collate=$collation"
        db_exists=1
    fi

    if (( db_exists == 0 )); then
        log_error "数据库 $db_name 不存在，可使用 --create-db 自动创建"
        exit 1
    fi

    local defaults_file
    defaults_file="$(mktemp)"
    chmod 600 "$defaults_file"
    {
        echo "[client]"
        echo "user=root"
        echo "password=${MYSQL_ROOT_PASSWORD}"
        echo "host=${db_host}"
        echo "default-character-set=${charset}"
    } >"$defaults_file"

    local cleanup_done=0
    cleanup_defaults() {
        if [[ $cleanup_done -eq 0 ]]; then
            rm -f "$defaults_file"
            cleanup_done=1
        fi
    }
    trap cleanup_defaults EXIT

    local -a reader
    if [[ "$dump_path" == *.gz ]]; then
        if ! command -v gzip >/dev/null 2>&1; then
            log_error "系统缺少 gzip，无法解压 .gz 备份"
            exit 1
        fi
        reader=(gzip -cd -- "$dump_path")
    else
        reader=(cat -- "$dump_path")
    fi

    log_info "开始导入 $dump_path 到数据库 $db_name ..."
    if ! "${reader[@]}" | mysql --defaults-extra-file="$defaults_file" --batch --silent "$db_name"; then
        log_error "数据库导入失败，请检查日志输出"
        exit 1
    fi

    cleanup_defaults
    trap - EXIT

    log_success "数据库导入完成：$db_name"
}

if [[ ${1:-} == "" || ${1:-} == "--help" || ${1:-} == "-h" ]]; then
    usage
    exit 0
fi

COMMAND="$1"
shift || true

case "$COMMAND" in
    create)
        handle_create "$@"
        ;;
    drop|delete)
        handle_drop "$@"
        ;;
    restore)
        handle_restore "$@"
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        log_error "未知的 mysql 子命令: $COMMAND"
        usage
        exit 1
        ;;
esac

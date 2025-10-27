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

usage() {
    cat <<'USAGE'
用法:
  saltgoat magetools mysql create --database <name> --user <user> --password <pass> [选项]

选项:
  --host <host>           MySQL 主机，默认 localhost
  --charset <charset>     数据库字符集，默认 utf8mb4
  --collation <collation> 数据库排序规则，默认 utf8mb4_unicode_ci
  --no-super              不授予 SUPER/PROCESS 全局权限
  --help                  显示此帮助

说明:
  - 自动创建数据库（若不存在）与账号；若账号已存在会跳过重复创建。
  - 默认授予 ALL PRIVILEGES ON <database>.* 以及 PROCESS、SUPER（可用 --no-super 关闭）。
  - root 密码来自 Pillar 的 mysql_password，可通过 `saltgoat passwords` 查看。
USAGE
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

mysql_exec() {
    local sql="$1"
    local allow_fail="${2:-0}"
    local socket="/var/run/mysqld/mysqld.sock"
    local cmd
    if [[ -S "$socket" ]]; then
        cmd=(mysql -uroot --socket="$socket" -e "$sql")
    else
        cmd=(mysql -uroot -h "$MYSQL_HOST" -e "$sql")
    fi

    if ! MYSQL_PWD="$MYSQL_ROOT_PASSWORD" "${cmd[@]}"; then
        if [[ "$allow_fail" == "1" ]]; then
            return 1
        fi
        log_error "执行 SQL 失败: $sql"
        exit 1
    fi
    return 0
}

create_database() {
    local db_name="$1"
    local charset="$2"
    local collation="$3"
    log_info "创建数据库（若不存在）：$db_name"
    mysql_exec "CREATE DATABASE IF NOT EXISTS \`$db_name\` CHARACTER SET $charset COLLATE $collation;"
}

create_user() {
    local user="$1"
    local host="$2"
    local password="$3"
    log_info "创建或更新账号：$user@$host"
    mysql_exec "CREATE USER IF NOT EXISTS '$user'@'$host' IDENTIFIED BY '$password';"
}

grants_for_user() {
    local user="$1"
    local host="$2"
    local db_name="$3"
    local include_super="$4"

    log_info "授权 $user@$host 对 $db_name.*"
    mysql_exec "GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$user'@'$host';"

    if [[ "$include_super" == "1" ]]; then
        log_info "授予 SUPER, PROCESS 全局权限"
        mysql_exec "GRANT SUPER, PROCESS ON *.* TO '$user'@'$host';"
    else
        if ! mysql_exec "REVOKE SUPER, PROCESS ON *.* FROM '$user'@'$host';" 1; then
            log_info "账号未持有 SUPER/PROCESS，全局权限保持最小化"
        fi
    fi

    mysql_exec "FLUSH PRIVILEGES;"
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

    MYSQL_ROOT_PASSWORD="$(require_root_password)"
    MYSQL_HOST="$db_host"

    create_database "$db_name" "$charset" "$collation"
    create_user "$db_user" "$db_host" "$db_pass"
    grants_for_user "$db_user" "$db_host" "$db_name" "$include_super"

    log_success "数据库 $db_name 与账号 $db_user@$db_host 创建/更新完成"
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
    help|--help|-h)
        usage
        ;;
    *)
        log_error "未知的 mysql 子命令: $COMMAND"
        usage
        exit 1
        ;;
esac

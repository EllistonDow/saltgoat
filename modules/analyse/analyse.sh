#!/bin/bash
# Analyse 模块 - 部署网站分析平台（首批支持 Matomo）

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
ANALYSE_HELPER="${MODULE_DIR}/../../modules/lib/analyse_helper.py"
# shellcheck disable=SC1091
source "${MODULE_DIR}/../../lib/logger.sh"
# shellcheck disable=SC1091
source "${MODULE_DIR}/../../lib/utils.sh"

# 默认 Matomo 配置（可通过 Pillar 覆盖）
MATOMO_DEFAULT_INSTALL_DIR="/var/www/matomo"
MATOMO_DEFAULT_DOMAIN="matomo.local"
MATOMO_DEFAULT_PHP_SOCKET="/run/php/php8.3-fpm.sock"
MATOMO_DEFAULT_OWNER="www-data"
MATOMO_DEFAULT_GROUP="www-data"
MATOMO_DEFAULT_DB_NAME="matomo"
MATOMO_DEFAULT_DB_USER="matomo"
MATOMO_DEFAULT_DB_HOST="localhost"
MATOMO_DEFAULT_DB_SOCKET="/var/run/mysqld/mysqld.sock"
MATOMO_DEFAULT_DB_PROVIDER="existing"
MATOMO_STATE_ID="optional.analyse"

generate_random_password() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 24 | tr -d '\n'
    else
        python3 "$ANALYSE_HELPER" random-password --length 24
    fi
}

get_pillar_value() {
    local key="$1"
    sudo salt-call --local pillar.get "$key" --out txt 2>/dev/null | awk '{print $2}' | tail -n 1
}

ensure_matomo_pillar_defaults() {
    local pillar_file
    pillar_file="$(get_local_pillar_file)"
    if ! sudo test -f "$pillar_file"; then
        log_warning "未找到 Pillar 文件: $pillar_file"
        return 1
    fi

    if sudo grep -q "^matomo:" "$pillar_file"; then
        return 0
    fi

    local db_password
    db_password=$(generate_random_password)
    sudo tee -a "$pillar_file" >/dev/null <<EOF

matomo:
  install_dir: '${MATOMO_DEFAULT_INSTALL_DIR}'
  domain: '${MATOMO_DEFAULT_DOMAIN}'
  php_fpm_socket: '/run/php/php8.3-fpm.sock'
  owner: 'www-data'
  group: 'www-data'
  db:
    enabled: true
    provider: '${MATOMO_DEFAULT_DB_PROVIDER}'
    name: '${MATOMO_DEFAULT_DB_NAME}'
    user: '${MATOMO_DEFAULT_DB_USER}'
    password: '${db_password}'
    host: '${MATOMO_DEFAULT_DB_HOST}'
    socket: '${MATOMO_DEFAULT_DB_SOCKET}'
EOF
    log_info "已将 Matomo 默认配置追加到 Pillar: ${pillar_file}"
    log_note "请根据实际环境更新域名、数据库名称等信息。"
    sudo salt-call --local saltutil.refresh_pillar >/dev/null 2>&1 || true
    return 0
}

analyse_install_matomo() {
    log_highlight "准备安装 Matomo 分析平台..."

    # 显示当前 Pillar 配置（如存在）
    local install_dir domain php_socket owner group db_enabled db_name db_user db_password db_host db_socket db_provider db_admin_user db_admin_password
    install_dir="$MATOMO_DEFAULT_INSTALL_DIR"
    domain="$MATOMO_DEFAULT_DOMAIN"
    php_socket="$MATOMO_DEFAULT_PHP_SOCKET"
    owner="$MATOMO_DEFAULT_OWNER"
    group="$MATOMO_DEFAULT_GROUP"
    db_enabled="false"
    db_name="$MATOMO_DEFAULT_DB_NAME"
    db_user="$MATOMO_DEFAULT_DB_USER"
    db_host="$MATOMO_DEFAULT_DB_HOST"
    db_socket="$MATOMO_DEFAULT_DB_SOCKET"
    db_provider="$MATOMO_DEFAULT_DB_PROVIDER"
    db_admin_user="root"
    db_admin_password=""
    db_password=""
    local db_password_source="default"

    local with_db="false"
    local override_db_name=""
    local override_db_user=""
    local override_db_password=""
    local override_db_provider=""
    local override_domain=""
    local override_db_admin_user=""
    local override_db_admin_password=""
    local override_db_host=""
    local override_db_socket=""
    local override_install_dir=""
    local override_php_socket=""
    local override_owner=""
    local override_group=""

    local extra_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --with-db)
                with_db="true"
                ;;
            --install-dir)
                override_install_dir="${2:-}"
                shift
                ;;
            --php-socket)
                override_php_socket="${2:-}"
                shift
                ;;
            --owner)
                override_owner="${2:-}"
                shift
                ;;
            --group)
                override_group="${2:-}"
                shift
                ;;
            --db-name)
                override_db_name="${2:-}"
                shift
                ;;
            --db-user)
                override_db_user="${2:-}"
                shift
                ;;
            --db-password)
                override_db_password="${2:-}"
                shift
                ;;
            --db-host)
                override_db_host="${2:-}"
                shift
                ;;
            --db-socket)
                override_db_socket="${2:-}"
                shift
                ;;
            --db-provider)
                override_db_provider="${2:-}"
                shift
                ;;
            --db-admin-user)
                override_db_admin_user="${2:-}"
                shift
                ;;
            --db-admin-password)
                override_db_admin_password="${2:-}"
                shift
                ;;
            --domain)
                override_domain="${2:-}"
                shift
                ;;
            --init-pillar)
                extra_args+=("--init-pillar")
                ;;
            *)
                log_warning "忽略未知选项: $1"
                ;;
        esac
        shift || break
    done

    if [[ " ${extra_args[*]} " == *" --init-pillar "* ]]; then
        ensure_matomo_pillar_defaults
    fi

    if sudo test -f "$(get_local_pillar_file)"; then
        local pillar_value
        pillar_value=$(get_pillar_value "matomo:install_dir")
        if [[ -n "$pillar_value" && "$pillar_value" != "None" ]]; then
            install_dir="$pillar_value"
        fi

        pillar_value=$(get_pillar_value "matomo:domain")
        if [[ -n "$pillar_value" && "$pillar_value" != "None" ]]; then
            domain="$pillar_value"
        fi

        pillar_value=$(get_pillar_value "matomo:php_fpm_socket")
        if [[ -n "$pillar_value" && "$pillar_value" != "None" ]]; then
            php_socket="$pillar_value"
        fi

        pillar_value=$(get_pillar_value "matomo:owner")
        if [[ -n "$pillar_value" && "$pillar_value" != "None" ]]; then
            owner="$pillar_value"
        fi

        pillar_value=$(get_pillar_value "matomo:group")
        if [[ -n "$pillar_value" && "$pillar_value" != "None" ]]; then
            group="$pillar_value"
        fi

        pillar_value=$(get_pillar_value "matomo:db:enabled")
        if [[ "$pillar_value" == "True" || "$pillar_value" == "true" ]]; then
            db_enabled="true"
        fi

        pillar_value=$(get_pillar_value "matomo:db:provider")
        if [[ -n "$pillar_value" && "$pillar_value" != "None" ]]; then
            db_provider="$pillar_value"
        fi

        pillar_value=$(get_pillar_value "matomo:db:name")
        if [[ -n "$pillar_value" && "$pillar_value" != "None" ]]; then
            db_name="$pillar_value"
        fi

        pillar_value=$(get_pillar_value "matomo:db:user")
        if [[ -n "$pillar_value" && "$pillar_value" != "None" ]]; then
            db_user="$pillar_value"
        fi

        pillar_value=$(get_pillar_value "matomo:db:password")
        if [[ -n "$pillar_value" && "$pillar_value" != "None" ]]; then
            db_password="$pillar_value"
            db_password_source="pillar"
        fi

        pillar_value=$(get_pillar_value "matomo:db:host")
        if [[ -n "$pillar_value" && "$pillar_value" != "None" ]]; then
            db_host="$pillar_value"
        fi

        pillar_value=$(get_pillar_value "matomo:db:socket")
        if [[ -n "$pillar_value" && "$pillar_value" != "None" ]]; then
            db_socket="$pillar_value"
        fi

        pillar_value=$(get_pillar_value "matomo:db:admin_user")
        if [[ -n "$pillar_value" && "$pillar_value" != "None" ]]; then
            db_admin_user="$pillar_value"
        fi

        pillar_value=$(get_pillar_value "matomo:db:admin_password")
        if [[ -n "$pillar_value" && "$pillar_value" != "None" ]]; then
            db_admin_password="$pillar_value"
        fi
    fi

    if [[ -n "$override_db_name" ]]; then
        db_name="$override_db_name"
        with_db="true"
    fi
    if [[ -n "$override_db_user" ]]; then
        db_user="$override_db_user"
        with_db="true"
    fi
    if [[ -n "$override_db_host" ]]; then
        db_host="$override_db_host"
        with_db="true"
    fi
    if [[ -n "$override_db_socket" ]]; then
        db_socket="$override_db_socket"
        with_db="true"
    fi

    if [[ -n "$override_db_password" ]]; then
        db_password="$override_db_password"
        with_db="true"
        db_password_source="override"
    fi

    if [[ -n "$override_db_provider" ]]; then
        db_provider="$override_db_provider"
        with_db="true"
    fi

    if [[ -n "$override_db_admin_user" ]]; then
        db_admin_user="$override_db_admin_user"
        with_db="true"
    fi

    if [[ -n "$override_db_admin_password" ]]; then
        db_admin_password="$override_db_admin_password"
        with_db="true"
    fi

    if [[ -n "$override_install_dir" ]]; then
        install_dir="$override_install_dir"
    fi

    if [[ -n "$override_php_socket" ]]; then
        php_socket="$override_php_socket"
    fi

    if [[ -n "$override_owner" ]]; then
        owner="$override_owner"
    fi

    if [[ -n "$override_group" ]]; then
        group="$override_group"
    fi

    if [[ -n "$override_domain" ]]; then
        domain="$override_domain"
    fi

    if [[ "$with_db" == "true" ]]; then
        db_enabled="true"
        if [[ -z "$db_provider" || "$db_provider" == "None" ]]; then
            db_provider="$MATOMO_DEFAULT_DB_PROVIDER"
        fi
    fi

    if [[ "$db_provider" == "mariadb" ]]; then
        local conflicting_pkg=""
        if command -v dpkg-query >/dev/null 2>&1; then
            local candidates=("mysql-server" "mysql-server-core-8.0" "mysql-client" "mysql-client-core-8.0" "percona-server-server" "percona-server-client")
            for pkg in "${candidates[@]}"; do
                if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
                    conflicting_pkg="$pkg"
                    break
                fi
            done
        fi
        if [[ -n "$conflicting_pkg" ]]; then
            log_error "检测到系统已安装 ${conflicting_pkg}，无法自动部署 MariaDB。请改用 --db-provider existing 或先卸载冲突组件。"
            return 1
        fi
    fi

    local saltuser_cnf="/etc/salt/mysql_saltuser.cnf"
    if [[ "$db_enabled" == "true" && -f "$saltuser_cnf" ]]; then
        if [[ -z "$db_admin_user" || "$db_admin_user" == "root" ]]; then
            local cnf_user
            cnf_user=$(sudo awk -F= '/^user=/{print $2}' "$saltuser_cnf" 2>/dev/null | tail -n1)
            if [[ -n "$cnf_user" ]]; then
                db_admin_user="$cnf_user"
            fi
        fi
        if [[ -z "$db_admin_password" ]]; then
            local cnf_pass
            cnf_pass=$(sudo awk -F= '/^password=/{print $2}' "$saltuser_cnf" 2>/dev/null | tail -n1)
            if [[ -n "$cnf_pass" ]]; then
                db_admin_password="$cnf_pass"
            fi
        fi
        if [[ -z "$db_socket" ]]; then
            local cnf_socket
            cnf_socket=$(sudo awk -F= '/^socket=/{print $2}' "$saltuser_cnf" 2>/dev/null | tail -n1)
            if [[ -n "$cnf_socket" ]]; then
                db_socket="$cnf_socket"
            fi
        fi
    fi

    if [[ "$db_enabled" == "true" && -z "$db_password" ]]; then
        db_password=$(generate_random_password)
        db_password_source="generated"
        log_info "未检测到 Pillar 中的 Matomo 数据库密码，已临时生成随机密码。"
        log_note "请将以下密码写入 Pillar (matomo:db:password) 以便后续使用: ${db_password}"
    fi

    log_info "目标目录: ${install_dir}"
    log_info "访问域名: ${domain}"
    log_info "PHP-FPM 套接字: ${php_socket}"
    log_info "运行用户: ${owner}:${group}"
    if [[ "$db_enabled" == "true" ]]; then
        log_info "数据库名称: ${db_name}"
        log_info "数据库用户: ${db_user}"
        log_info "数据库主机: ${db_host}"
        log_info "数据库套接字: ${db_socket}"
        log_info "数据库提供者: ${db_provider}"
        if [[ "$db_provider" == "mariadb" ]]; then
            log_note "将尝试安装 MariaDB 套件 (mariadb-server/client)。若系统已安装其他 MySQL 发行版，请将 matomo:db.provider 设置为 existing 并复用现有服务。"
        else
            log_note "使用现有数据库提供者 (${db_provider})，确保当前环境可通过上述主机或套接字连接。"
        fi
        if [[ -z "$db_admin_password" ]]; then
            log_note "未提供数据库管理员密码，将尝试使用无密码的 socket/本地连接。若目标实例需要凭据，请通过 --db-admin-user/--db-admin-password 或 Pillar matomo:db.admin_* 配置。"
        fi
    else
        log_note "未启用数据库自动配置，可通过 --with-db 以及 --db-* 选项启用。"
    fi
    log_info "Salt 状态: ${MATOMO_STATE_ID}"

    if ! command_exists salt-call; then
        log_error "未检测到 salt-call，无法使用 Salt 状态安装"
        return 1
    fi

    local pillar_override=""
    local override_needed="false"

    if [[ "$db_enabled" == "true" ]]; then
        override_needed="true"
        if ! command_exists mysql; then
            log_error "未检测到 mysql 客户端，请安装 mysql-client 或 percona-client 后重试。"
            return 1
        fi

        local mysql_cmd=("mysql" "-u" "$db_admin_user")
        if [[ -n "$db_admin_password" ]]; then
            mysql_cmd+=("-p${db_admin_password}")
        fi
        if [[ -n "$db_socket" && -S "$db_socket" ]]; then
            mysql_cmd+=("--socket=$db_socket")
        else
            mysql_cmd+=("-h" "$db_host")
        fi
        mysql_cmd+=("-e" "SELECT 1")

        if ! "${mysql_cmd[@]}" >/dev/null 2>&1; then
            log_error "无法使用 ${db_admin_user}@${db_host:-local socket} 连接数据库，请检查 --db-admin-* 或 Pillar 中的 matomo:db.admin_* 设置。"
            return 1
        fi
    fi

    if [[ -n "$override_install_dir" || -n "$override_php_socket" || -n "$override_owner" || -n "$override_group" || -n "$override_domain" ]]; then
        override_needed="true"
    fi

    if [[ "$db_password_source" == "generated" || "$db_password_source" == "override" ]]; then
        override_needed="true"
    fi

    if [[ "$override_needed" == "true" ]]; then
        local args=(
            "matomo-override"
            "--install-dir" "$install_dir"
            "--domain" "$domain"
            "--php-socket" "$php_socket"
            "--owner" "$owner"
            "--group" "$group"
        )
        if [[ "$db_enabled" == "true" ]]; then
            args+=(
                "--db-enabled"
                "--db-name" "$db_name"
                "--db-user" "$db_user"
                "--db-password" "$db_password"
                "--db-host" "$db_host"
                "--db-socket" "$db_socket"
                "--db-provider" "$db_provider"
                "--db-admin-user" "$db_admin_user"
                "--db-admin-password" "$db_admin_password"
            )
        fi
        pillar_override=$(python3 "$ANALYSE_HELPER" "${args[@]}")
    fi

    local apply_status
    if [[ -n "$pillar_override" ]]; then
        sudo salt-call --local state.apply "${MATOMO_STATE_ID}" pillar="$pillar_override"
        apply_status=$?
    else
        sudo salt-call --local state.apply "${MATOMO_STATE_ID}"
        apply_status=$?
    fi

    if [[ $apply_status -eq 0 ]]; then
        log_success "Matomo 安装状态已成功执行"
        log_info "请访问 http://${domain}/ 完成 Web 向导配置。"
        log_note "如需 HTTPS，可运行: saltgoat nginx add-ssl ${domain} <email>"
        if [[ "$db_enabled" == "true" ]]; then
            log_note "已尝试创建数据库 ${db_name} 并授予用户 ${db_user} 权限。"
            case "$db_password_source" in
                "generated")
                    local report_dir="/var/lib/saltgoat/reports"
                    local password_file="${report_dir}/matomo-db-password.txt"
                    sudo mkdir -p "$report_dir"
                    sudo chmod 700 "$report_dir"
                    printf 'Matomo database password (%s): %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$db_password" | sudo tee "$password_file" >/dev/null
                    sudo chmod 600 "$password_file"
                    log_note "临时数据库密码已写入 ${password_file}，请尽快同步到 Pillar 后安全删除该文件。"
                    ;;
                "pillar")
                    log_note "数据库密码已在 Pillar (matomo:db:password) 中维护，请使用 saltgoat pillar show 查看。"
                    ;;
                "override")
                    log_note "数据库密码来源于命令行参数，请确认已在安全存储中备份。"
                    ;;
                *)
                    log_note "数据库密码已配置，请确认负责方已妥善存储。"
                    ;;
            esac
        fi
        return 0
    else
        log_error "Matomo 安装状态执行失败"
        return 1
    fi
}

analyse_install() {
    local target="${1:-}"
    case "$target" in
        "matomo")
            analyse_install_matomo "${@:2}"
            ;;
        ""|"-h"|"--help"|"help")
            log_info "用法: saltgoat analyse install <matomo>"
            ;;
        *)
            log_error "未知的 analyse 组件: ${target}"
            log_info "当前支持: matomo"
            return 1
            ;;
    esac
}

analyse_handler() {
    local action="${1:-}"
    case "$action" in
        "install")
            analyse_install "${@:2}"
            ;;
        ""|"-h"|"--help"|"help")
            show_analyse_help
            ;;
        *)
            log_error "未知的 analyse 操作: ${action}"
            log_info "支持: install"
            return 1
            ;;
    esac
}

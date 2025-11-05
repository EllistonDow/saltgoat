#!/bin/bash
# Magento RabbitMQ 管理（Salt 原生）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../lib/logger.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"
# shellcheck source=../../lib/utils.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/utils.sh"
RABBIT_HELPER="${SCRIPT_DIR}/modules/lib/rabbitmq_helper.py"
NGINX_CONTEXT="${SCRIPT_DIR}/modules/lib/nginx_context.py"

RMQ_MODE="smart"
SITE_NAME=""
THREADS=1
THREADS_OVERRIDE=0
AMQP_HOST="127.0.0.1"
AMQP_PORT=5672
AMQP_USER=""
AMQP_PASSWORD=""
AMQP_VHOST=""
SERVICE_USER="www-data"
PHP_MEMORY_LIMIT="2G"
CPU_QUOTA=""
NICE_VALUE=""
SITE_PATH_OVERRIDE=""
SITE_PATH=""

usage() {
    cat <<EOF
用法:
  配置: saltgoat magetools rabbitmq-salt <mode> <site> [选项]
  检测: saltgoat magetools rabbitmq-salt check <site> [选项]
  清理: saltgoat magetools rabbitmq-salt remove <site> [选项]
  列表: saltgoat magetools rabbitmq-salt list <site|all>

mode: all | smart

选项:
  --threads N          每个消费者实例数量（默认 1）
  --amqp-host HOST     Broker 主机（默认 127.0.0.1）
  --amqp-port PORT     Broker 端口（默认 5672）
  --amqp-user USER     AMQP 用户（默认 <site>）
  --amqp-password STR  AMQP 密码（默认必填，或从 Pillar 注入）
  --amqp-vhost VHOST   AMQP 虚拟主机（默认 /<site>）
  --service-user USER  systemd 运行用户（默认 www-data）
  --php-memory STR     PHP 内存限制（默认 2G）
  --cpu-quota PCT      CPU 配额（例如 50%），默认 50%
  --nice N             nice 值(-20..19，正数更"温和")，默认 10
  --site-path PATH     指定 Magento 根目录（默认 /var/www/<site>）
  --mode all|smart     覆盖模式（仅在 check 时有用；配置时由第一个位置参数决定）
  -h, --help           显示帮助
EOF
}

abort() { log_error "$1"; exit 1; }

load_env_defaults() {
    local pillar_password
    pillar_password=$(get_local_pillar_value rabbitmq_password)
    AMQP_PASSWORD="${AMQP_PASSWORD:-${pillar_password:-$AMQP_PASSWORD}}"
}

resolve_site_path() {
    if [[ "$SITE_NAME" == "__ALL__" ]]; then
        SITE_PATH=""
        return
    fi
    local resolved="${SITE_PATH_OVERRIDE}"
    if [[ -z "$resolved" ]]; then
        local detected
        detected="$(python3 "$NGINX_CONTEXT" site-root --site "$SITE_NAME" 2>/dev/null || true)"
        detected="${detected%/}"
        if [[ "$detected" == */pub ]]; then
            detected="${detected%/pub}"
        fi
        if [[ -n "$detected" ]]; then
            if sudo test -d "$detected"; then
                resolved="$detected"
            fi
        fi
    fi
    if [[ -z "$resolved" ]]; then
        local candidates=("/var/www/${SITE_NAME}" "/var/www/${SITE_NAME}/current")
        local candidate
        for candidate in "${candidates[@]}"; do
            if sudo test -d "$candidate"; then
                resolved="$candidate"
                break
            fi
        done
    fi

    if [[ -z "$resolved" ]]; then
        abort "无法推导站点目录，请使用 --site-path 明确指定。"
    fi

    local canonical_path
    canonical_path="$(sudo readlink -f "$resolved" 2>/dev/null || sudo realpath "$resolved" 2>/dev/null || true)"
    if [[ -z "$canonical_path" ]]; then
        abort "无法解析站点目录: $resolved"
    fi
    resolved="$canonical_path"
    resolved=${resolved%/}
    if [[ "$resolved" == */current ]]; then
        resolved=${resolved%/current}
    fi

    if ! sudo test -d "$resolved"; then
        abort "站点目录不存在: $resolved"
    fi

    SITE_PATH="$resolved"

    local canonical
    canonical=$(basename "$SITE_PATH")
    if [[ "$canonical" != "$SITE_NAME" ]]; then
        log_warning "检测到站点 ${SITE_NAME} 实际目录归属 ${canonical} (路径: ${SITE_PATH})"
        abort "请使用 '--site ${canonical}' 或通过 '--site-path' 指定正确目录。"
    fi
}

auto_detect_threads() {
    local max_threads=0 unit
    while read -r unit; do
        [[ -z "$unit" ]] && continue
        if [[ "$unit" =~ ^magento-consumer@${SITE_NAME}-.+-([0-9]+)\.service$ ]]; then
            local thread="${BASH_REMATCH[1]}"
            if [[ "$thread" =~ ^[0-9]+$ ]] && (( thread > max_threads )); then
                max_threads=$thread
            fi
        fi
    done < <(systemctl list-units --type=service --all --no-legend 2>/dev/null | awk '{print $1}')

    if (( max_threads > 0 )); then
        THREADS="$max_threads"
        log_info "自动检测到现有消费者线程数: ${THREADS}"
    else
        log_info "未检测到现有消费者线程，沿用默认线程数 ${THREADS}"
    fi
}

ensure_threads_integer() {
    if ! [[ "$THREADS" =~ ^[0-9]+$ ]]; then
        abort "线程数必须为正整数"
    fi
    THREADS=$(( THREADS ))
    if (( THREADS < 1 )); then
        log_warning "线程数小于 1，已自动调整为 1"
        THREADS=1
    fi
}

ACTION="apply"

parse_args() {
    if [[ $# -lt 2 ]]; then usage; exit 1; fi
    if [[ "$1" == "check" ]]; then
        ACTION="check"; shift
        RMQ_MODE="smart"  # 默认 smart，可通过 --mode 覆盖
        SITE_NAME="$1"; shift
    elif [[ "$1" == "remove" ]]; then
        ACTION="remove"; shift
        RMQ_MODE="smart"
        SITE_NAME="$1"; shift
    elif [[ "$1" == "list" ]]; then
        ACTION="list"; shift
        RMQ_MODE="smart"
        SITE_NAME="$1"; shift
        if [[ "$SITE_NAME" == "all" ]]; then
            SITE_NAME="__ALL__"
        fi
    else
        RMQ_MODE="$1"; shift
        SITE_NAME="$1"; shift
    fi

    while [[ $# -gt 0 ]]; do
        # 忽略空参数，避免上游转发空字符串
        if [[ -z "${1:-}" ]]; then shift; continue; fi
        case "$1" in
            --threads)
                val="${2-}"; [[ -z "$val" ]] && abort "--threads 需要一个值";
                THREADS="$val"; THREADS_OVERRIDE=1; shift 2 ;;
            --threads=*)
                val="${1#*=}"; [[ -z "$val" ]] && abort "--threads 需要一个值";
                THREADS="$val"; THREADS_OVERRIDE=1; shift ;;
            -t)
                val="${2-}"; [[ -z "$val" ]] && abort "-t 需要一个值";
                THREADS="$val"; THREADS_OVERRIDE=1; shift 2 ;;
            --mode)
                val="${2-}"; [[ -z "$val" ]] && abort "--mode 需要一个值 (all|smart)";
                RMQ_MODE="$val"; shift 2 ;;
            --mode=*)
                val="${1#*=}"; [[ -z "$val" ]] && abort "--mode 需要一个值 (all|smart)";
                RMQ_MODE="$val"; shift ;;
            --amqp-host)
                val="${2-}"; [[ -z "$val" ]] && abort "--amqp-host 需要一个值";
                AMQP_HOST="$val"; shift 2 ;;
            --amqp-host=*)
                AMQP_HOST="${1#*=}"; shift ;;
            --amqp-port)
                val="${2-}"; [[ -z "$val" ]] && abort "--amqp-port 需要一个值";
                AMQP_PORT="$val"; shift 2 ;;
            --amqp-port=*)
                AMQP_PORT="${1#*=}"; shift ;;
            --amqp-user)
                val="${2-}"; [[ -z "$val" ]] && abort "--amqp-user 需要一个值";
                AMQP_USER="$val"; shift 2 ;;
            --amqp-user=*)
                AMQP_USER="${1#*=}"; shift ;;
            --amqp-password)
                val="${2-}"; [[ -z "$val" ]] && abort "--amqp-password 需要一个值";
                AMQP_PASSWORD="$val"; shift 2 ;;
            --amqp-password=*)
                AMQP_PASSWORD="${1#*=}"; shift ;;
            --amqp-vhost)
                val="${2-}"; [[ -z "$val" ]] && abort "--amqp-vhost 需要一个值";
                AMQP_VHOST="$val"; shift 2 ;;
            --amqp-vhost=*)
                AMQP_VHOST="${1#*=}"; shift ;;
            --service-user)
                val="${2-}"; [[ -z "$val" ]] && abort "--service-user 需要一个值";
                SERVICE_USER="$val"; shift 2 ;;
            --service-user=*)
                SERVICE_USER="${1#*=}"; shift ;;
            --php-memory)
                val="${2-}"; [[ -z "$val" ]] && abort "--php-memory 需要一个值";
                PHP_MEMORY_LIMIT="$val"; shift 2 ;;
            --cpu-quota)
                val="${2-}"; [[ -z "$val" ]] && abort "--cpu-quota 需要一个值 (如 50%)";
                CPU_QUOTA="$val"; shift 2 ;;
            --cpu-quota=*)
                CPU_QUOTA="${1#*=}"; shift ;;
            --nice)
                val="${2-}"; [[ -z "$val" ]] && abort "--nice 需要一个值 (-20..19)";
                NICE_VALUE="$val"; shift 2 ;;
            --nice=*)
                NICE_VALUE="${1#*=}"; shift ;;
            --php-memory=*)
                PHP_MEMORY_LIMIT="${1#*=}"; shift ;;
            --site-path)
                val="${2-}"; [[ -z "$val" ]] && abort "--site-path 需要一个值";
                SITE_PATH_OVERRIDE="$val"; shift 2 ;;
            --site-path=*)
                SITE_PATH_OVERRIDE="${1#*=}"; shift ;;
            -h|--help) usage; exit 0 ;;
            *) abort "未知参数: $1" ;;
        esac
    done

    # Load pillar defaults early (flags still override)
    load_env_defaults

    if [[ "$SITE_NAME" != "__ALL__" ]]; then
        if [[ -z "$SITE_NAME" || "$SITE_NAME" =~ [^a-zA-Z0-9_-] ]]; then
            abort "站点名称非法"
        fi
    fi
    if [[ "$ACTION" != "remove" && "$ACTION" != "list" ]]; then
        if [[ "$RMQ_MODE" != "all" && "$RMQ_MODE" != "smart" ]]; then
            abort "mode 仅支持 all 或 smart"
        fi
        if [[ -z "$AMQP_USER" ]]; then AMQP_USER="${SITE_NAME}"; fi
        if [[ -z "$AMQP_VHOST" ]]; then AMQP_VHOST="/${SITE_NAME}"; fi
        if [[ -z "$AMQP_PASSWORD" ]]; then
            abort "缺少 AMQP 密码。请在 salt/pillar/saltgoat.sls 中配置 rabbitmq_password 或使用 --amqp-password 传入。"
        fi
    fi
}

build_pillar_json() {
    PILLAR_SITE_NAME="$SITE_NAME" \
    PILLAR_SITE_PATH="$SITE_PATH" \
    PILLAR_MODE="$RMQ_MODE" \
    PILLAR_THREADS="$THREADS" \
    PILLAR_AMQP_HOST="$AMQP_HOST" \
    PILLAR_AMQP_PORT="$AMQP_PORT" \
    PILLAR_AMQP_USER="$AMQP_USER" \
    PILLAR_AMQP_PASSWORD="$AMQP_PASSWORD" \
    PILLAR_AMQP_VHOST="$AMQP_VHOST" \
    PILLAR_SERVICE_USER="$SERVICE_USER" \
    PILLAR_PHP_MEMORY_LIMIT="$PHP_MEMORY_LIMIT" \
    PILLAR_CPU_QUOTA="${CPU_QUOTA:-}" \
    PILLAR_NICE="${NICE_VALUE:-}" \
    python3 "$RABBIT_HELPER" build
}

build_remove_pillar_json() {
    PILLAR_SITE_NAME="$SITE_NAME" \
    PILLAR_SITE_PATH="$SITE_PATH" \
    PILLAR_SERVICE_USER="$SERVICE_USER" \
    python3 "$RABBIT_HELPER" remove
}

build_list_pillar_json() {
    PILLAR_SITE_NAME="$SITE_NAME" \
    python3 "$RABBIT_HELPER" list
}

apply_state() {
    local pillar_json
    case "$ACTION" in
        check)
            pillar_json="$(build_pillar_json)"
            log_info "执行 RabbitMQ 检测 ..."
            sudo salt-call --local --retcode-passthrough state.apply optional.magento-rabbitmq-check pillar="$pillar_json"
            ;;
        remove)
            pillar_json="$(build_remove_pillar_json)"
            log_info "清理 RabbitMQ 消费者 ..."
            sudo salt-call --local --retcode-passthrough state.apply optional.magento-rabbitmq-remove pillar="$pillar_json"
            ;;
        list)
            pillar_json="$(build_list_pillar_json)"
            log_info "列出 RabbitMQ 消费者 ..."
            sudo salt-call --local --retcode-passthrough state.apply optional.magento-rabbitmq-list pillar="$pillar_json"
            ;;
        *)
            pillar_json="$(build_pillar_json)"
            log_info "应用 Salt 状态 optional.magento-rabbitmq ..."
            sudo salt-call --local --retcode-passthrough state.apply optional.magento-rabbitmq pillar="$pillar_json"
            ;;
    esac
}

main() {
    parse_args "$@"
    if [[ "$SITE_NAME" != "__ALL__" ]]; then
        resolve_site_path
        log_info "使用站点目录: ${SITE_PATH}"
    fi
    if [[ "$ACTION" == "check" && "$THREADS_OVERRIDE" -eq 0 ]]; then
        auto_detect_threads
    fi
    if [[ "$ACTION" != "remove" && "$ACTION" != "list" ]]; then
        ensure_threads_integer
    fi
    apply_state
}
main "$@"

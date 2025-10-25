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

RMQ_MODE="smart"
SITE_NAME=""
THREADS=2
AMQP_HOST="127.0.0.1"
AMQP_PORT=5672
AMQP_USER=""
AMQP_PASSWORD=""
AMQP_VHOST=""
SERVICE_USER="www-data"
PHP_MEMORY_LIMIT="2G"
CPU_QUOTA=""
NICE_VALUE=""

usage() {
    cat <<EOF
用法:
  配置: saltgoat magetools rabbitmq-salt <mode> <site> [选项]
  检测: saltgoat magetools rabbitmq-salt check <site> [选项]

mode: all | smart

选项:
  --threads N          每个消费者实例数量（默认 2）
  --amqp-host HOST     Broker 主机（默认 127.0.0.1）
  --amqp-port PORT     Broker 端口（默认 5672）
  --amqp-user USER     AMQP 用户（默认 <site>）
  --amqp-password STR  AMQP 密码（默认必填，或从 Pillar 注入）
  --amqp-vhost VHOST   AMQP 虚拟主机（默认 /<site>）
  --service-user USER  systemd 运行用户（默认 www-data）
  --php-memory STR     PHP 内存限制（默认 2G）
  --cpu-quota PCT      CPU 配额（例如 50%），默认 50%
  --nice N             nice 值(-20..19，正数更"温和")，默认 10
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

ACTION="apply"

parse_args() {
    if [[ $# -lt 2 ]]; then usage; exit 1; fi
    if [[ "$1" == "check" ]]; then
        ACTION="check"; shift
        RMQ_MODE="smart"  # 默认 smart，可通过 --mode 覆盖
        SITE_NAME="$1"; shift
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
                THREADS="$val"; shift 2 ;;
            --threads=*)
                val="${1#*=}"; [[ -z "$val" ]] && abort "--threads 需要一个值";
                THREADS="$val"; shift ;;
            -t)
                val="${2-}"; [[ -z "$val" ]] && abort "-t 需要一个值";
                THREADS="$val"; shift 2 ;;
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
            -h|--help) usage; exit 0 ;;
            *) abort "未知参数: $1" ;;
        esac
    done

    # Load pillar defaults early (flags still override)
    load_env_defaults

    if [[ "$RMQ_MODE" != "all" && "$RMQ_MODE" != "smart" ]]; then
        abort "mode 仅支持 all 或 smart"
    fi
    if [[ -z "$SITE_NAME" || "$SITE_NAME" =~ [^a-zA-Z0-9_-] ]]; then
        abort "站点名称非法"
    fi
    if [[ -z "$AMQP_USER" ]]; then AMQP_USER="${SITE_NAME}"; fi
    if [[ -z "$AMQP_VHOST" ]]; then AMQP_VHOST="/${SITE_NAME}"; fi
    if [[ -z "$AMQP_PASSWORD" ]]; then
        abort "缺少 AMQP 密码。请在 salt/pillar/saltgoat.sls 中配置 rabbitmq_password 或使用 --amqp-password 传入。"
    fi
}

build_pillar_json() {
    PILLAR_SITE_NAME="$SITE_NAME" \
    PILLAR_SITE_PATH="/var/www/${SITE_NAME}" \
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
    python3 - <<'PY'
import json, os
data = {
  "site_name": os.environ["PILLAR_SITE_NAME"],
  "site_path": os.environ["PILLAR_SITE_PATH"],
  "mode": os.environ["PILLAR_MODE"],
  "threads": int(os.environ["PILLAR_THREADS"]),
  "amqp_host": os.environ["PILLAR_AMQP_HOST"],
  "amqp_port": int(os.environ["PILLAR_AMQP_PORT"]),
  "amqp_user": os.environ["PILLAR_AMQP_USER"],
  "amqp_password": os.environ["PILLAR_AMQP_PASSWORD"],
  "amqp_vhost": os.environ["PILLAR_AMQP_VHOST"],
  "service_user": os.environ["PILLAR_SERVICE_USER"],
  "php_memory_limit": os.environ["PILLAR_PHP_MEMORY_LIMIT"],
  "cpu_quota": os.environ.get("PILLAR_CPU_QUOTA", ""),
  "nice": os.environ.get("PILLAR_NICE", ""),
}
print(json.dumps(data))
PY
}

apply_state() {
    local pillar_json
    pillar_json="$(build_pillar_json)"
    if [[ "$ACTION" == "check" ]]; then
        log_info "执行 RabbitMQ 检测 ..."
        salt-call --local --retcode-passthrough state.apply optional.magento-rabbitmq-check pillar="$pillar_json"
    else
        log_info "应用 Salt 状态 optional.magento-rabbitmq ..."
        salt-call --local --retcode-passthrough state.apply optional.magento-rabbitmq pillar="$pillar_json"
    fi
}

main() { parse_args "$@"; apply_state; }
main "$@"

#!/bin/bash
# Magento 维护入口（基于 Salt 状态）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAINTENANCE_PILLAR_HELPER="${SCRIPT_DIR}/modules/lib/maintenance_pillar.py"
# shellcheck source=../../lib/logger.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"
# shellcheck source=../../lib/utils.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/utils.sh"

usage() {
    cat <<EOF
用法:
  saltgoat magetools maintenance <site> <action> [选项]

action:
  status   | enable | disable
  daily    | weekly | monthly
  backup   | health | cleanup | deploy

常用选项:
  --site-path PATH            指定站点路径（默认 /var/www/<site>）
  --magento-user USER         Magento 运行用户（默认 www-data）
  --php-bin PATH              Magento CLI 使用的 PHP（二进制，默认 php）
  --composer-bin PATH         Composer 二进制（默认 composer，可缺省）
  --valkey-cli PATH           valkey-cli 二进制（默认 valkey-cli）
  --allow-valkey-flush        在 weekly 任务中允许执行 valkey-cli FLUSHALL
  --valkey-password PASS      Valkey 密码（用于 FLUSHALL）
  --allow-setup-upgrade       允许 monthly/deploy 运行 setup:upgrade 等升级操作
  --backup-dir PATH           传统归档备份目录（tar/mysqldump）
  --backup-keep-days N        传统备份保留天数（默认 7）
  --mysql-database NAME       数据库名称（默认与 site 相同）
  --mysql-user USER           mysqldump 用户（默认 root）
  --mysql-password PASS       mysqldump 密码
  --trigger-restic            每周备份时同时执行 saltgoat-restic-backup（如存在）
  --restic-site NAME          Restic 针对单站点备份（传给 backup restic run --site）
  --restic-backup-dir PATH    Restic 仓库覆盖路径（如 /home/Dropbox/<site>/snapshots）
  --restic-extra-path PATH    Restic 额外路径，可多次使用或配合 --restic-extra-paths "p1,p2"
  --static-langs \"en_US zh_CN\"  每月/部署静态资源语言列表
  --static-jobs N             静态内容部署并行线程（默认 4）
EOF
}

if [[ $# -lt 2 ]]; then
    usage
    exit 1
fi

SITE_NAME="$1"
ACTION="$2"
shift 2 || true

case "$ACTION" in
    status|enable|disable|daily|weekly|monthly|backup|health|cleanup|deploy) ;;
    *)
        log_error "未知的维护操作: $ACTION"
        usage
        exit 1
        ;;
esac

SITE_PATH=""
MAGENTO_USER="www-data"
PHP_BIN="php"
COMPOSER_BIN="composer"
VALKEY_CLI="valkey-cli"
VALKEY_PASSWORD=""
ALLOW_VALKEY_FLUSH="0"
ALLOW_SETUP_UPGRADE="0"
BACKUP_TARGET_DIR=""
BACKUP_KEEP_DAYS="7"
MYSQL_DATABASE="$SITE_NAME"
MYSQL_USER="root"
MYSQL_PASSWORD=""
TRIGGER_RESTIC="0"
STATIC_LANGS=""
STATIC_JOBS="4"
RESTIC_SITE_OVERRIDE=""
RESTIC_REPO_OVERRIDE=""
RESTIC_EXTRA_PATHS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --site-path)
            SITE_PATH="${2:-}"; shift 2 ;;
        --magento-user)
            MAGENTO_USER="${2:-}"; shift 2 ;;
        --php-bin)
            PHP_BIN="${2:-}"; shift 2 ;;
        --composer-bin)
            COMPOSER_BIN="${2:-}"; shift 2 ;;
        --valkey-cli)
            VALKEY_CLI="${2:-}"; shift 2 ;;
        --valkey-password)
            VALKEY_PASSWORD="${2:-}"; shift 2 ;;
        --allow-valkey-flush)
            ALLOW_VALKEY_FLUSH="1"; shift ;;
        --allow-setup-upgrade)
            ALLOW_SETUP_UPGRADE="1"; shift ;;
        --backup-dir)
            BACKUP_TARGET_DIR="${2:-}"; shift 2 ;;
        --backup-keep-days)
            BACKUP_KEEP_DAYS="${2:-7}"; shift 2 ;;
        --mysql-database)
            MYSQL_DATABASE="${2:-}"; shift 2 ;;
        --mysql-user)
            MYSQL_USER="${2:-}"; shift 2 ;;
        --mysql-password)
            MYSQL_PASSWORD="${2:-}"; shift 2 ;;
        --trigger-restic)
            TRIGGER_RESTIC="1"; shift ;;
        --restic-site)
            RESTIC_SITE_OVERRIDE="${2:-}"; shift 2 ;;
        --restic-backup-dir|--restic-repo)
            RESTIC_REPO_OVERRIDE="${2:-}"; shift 2 ;;
        --restic-extra-path)
            val="${2:-}"; [[ -z "$val" ]] && { log_error "--restic-extra-path 需要路径"; exit 1; }
            if [[ -z "$RESTIC_EXTRA_PATHS" ]]; then
                RESTIC_EXTRA_PATHS="$val"
            else
                RESTIC_EXTRA_PATHS+=";$val"
            fi
            shift 2 ;;
        --restic-extra-paths)
            val="${2:-}"; [[ -z "$val" ]] && { log_error "--restic-extra-paths 需要列表"; exit 1; }
            val="${val//,/ }"
            read -ra _restic_paths <<< "$val"
            for rp in "${_restic_paths[@]}"; do
                [[ -z "$rp" ]] && continue
                if [[ -z "$RESTIC_EXTRA_PATHS" ]]; then
                    RESTIC_EXTRA_PATHS="$rp"
                else
                    RESTIC_EXTRA_PATHS+=";$rp"
                fi
            done
            shift 2 ;;
        --static-langs)
            STATIC_LANGS="${2:-}"; shift 2 ;;
        --static-jobs)
            STATIC_JOBS="${2:-4}"; shift 2 ;;
        --redis-cli)
            log_warning "参数 --redis-cli 已弃用，请改用 --valkey-cli"
            VALKEY_CLI="${2:-}"; shift 2 ;;
        --redis-password)
            log_warning "参数 --redis-password 已弃用，请改用 --valkey-password"
            VALKEY_PASSWORD="${2:-}"; shift 2 ;;
        --allow-redis-flush)
            log_warning "参数 --allow-redis-flush 已弃用，请改用 --allow-valkey-flush"
            ALLOW_VALKEY_FLUSH="1"; shift ;;
        --help|-h)
            usage; exit 0 ;;
        *)
            log_error "未知参数: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$SITE_PATH" ]]; then
    SITE_PATH="/var/www/${SITE_NAME}"
fi

build_pillar_json() {
    if [[ ! -x "$MAINTENANCE_PILLAR_HELPER" ]]; then
        log_error "缺少维护 Pillar 构建脚本: $MAINTENANCE_PILLAR_HELPER"
        exit 1
    fi
    python3 "$MAINTENANCE_PILLAR_HELPER"
}

export SITE_NAME
export SITE_PATH
export MAGENTO_USER
export PHP_BIN
export COMPOSER_BIN
export VALKEY_CLI
export VALKEY_PASSWORD
export ALLOW_VALKEY_FLUSH
export ALLOW_SETUP_UPGRADE
export BACKUP_TARGET_DIR
export BACKUP_KEEP_DAYS
export MYSQL_DATABASE
export MYSQL_USER
export MYSQL_PASSWORD
export TRIGGER_RESTIC
export STATIC_LANGS
export STATIC_JOBS
export RESTIC_SITE_OVERRIDE
export RESTIC_REPO_OVERRIDE
export RESTIC_EXTRA_PATHS

PILLAR_JSON="$(build_pillar_json)"

log_info "执行维护操作: action=${ACTION}, site=${SITE_NAME}"
sudo salt-call --local --retcode-passthrough state.apply "optional.magento-maintenance.${ACTION}" pillar="$PILLAR_JSON"

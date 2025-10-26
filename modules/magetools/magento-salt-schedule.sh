#!/bin/bash
# 兼容入口：复用新版 magento-cron Salt Schedule 管理
# modules/magetools/magento-salt-schedule.sh

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "${MODULE_DIR}/magento-cron.sh" "$@"

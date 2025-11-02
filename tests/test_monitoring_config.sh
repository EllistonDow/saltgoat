#!/bin/bash
# 验证监控相关脚本语法与示例 Pillar
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
python3 -m py_compile modules/monitoring/resource_alert.py modules/magetools/magento-schedule.py salt/_modules/saltgoat.py >/dev/null
bash -n monitoring/system.sh
if ! grep -q 'tls_warn_days' salt/pillar/monitoring.sls.sample; then
    echo "monitoring.sls.sample 缺少 tls_warn_days 字段" >&2
    exit 1
fi

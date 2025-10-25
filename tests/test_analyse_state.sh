#!/bin/bash
# Dry-run validation for optional.analyse Salt state

set -euo pipefail

if ! command -v salt-call >/dev/null 2>&1; then
    echo "salt-call command not found; skipping optional.analyse test."
    exit 0
fi

PILLAR_JSON=$(python3 - <<'PY'
import json
pillar = {
    "matomo": {
        "install_dir": "/tmp/saltgoat-matomo-test",
        "domain": "matomo.test.local",
        "php_fpm_socket": "/run/php/php8.3-fpm.sock",
        "owner": "www-data",
        "group": "www-data",
        "db": {
            "enabled": True,
            "provider": "existing",
            "name": "matomo_test",
            "user": "matomo_test",
            "password": "SaltGoatTest123!",
            "host": "localhost",
            "socket": "/var/run/mysqld/mysqld.sock",
            "admin_user": "saltuser",
            "admin_password": "SaltGoat2024!"
        }
    }
}
print(json.dumps(pillar))
PY
)

echo "[INFO] Running optional.analyse state (test mode)..."
sudo salt-call --local state.apply optional.analyse test=True pillar="$PILLAR_JSON"

echo "[SUCCESS] optional.analyse state rendered successfully in test mode."

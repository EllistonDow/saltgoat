#!/usr/bin/env python3
"""Build pillar payload for Magento maintenance Salt states."""

from __future__ import annotations

import json
import os
import sys
from typing import Dict, Any


def truthy(key: str) -> bool:
    return os.environ.get(key, "0").lower() in {"1", "true", "yes"}


def build_payload() -> Dict[str, Any]:
    data: Dict[str, Any] = {
        "site_name": os.environ.get("SITE_NAME"),
        "site_path": os.environ.get("SITE_PATH"),
        "magento_user": os.environ.get("MAGENTO_USER"),
        "php_bin": os.environ.get("PHP_BIN"),
        "composer_bin": os.environ.get("COMPOSER_BIN"),
        "valkey_cli": os.environ.get("VALKEY_CLI"),
        "allow_valkey_flush": truthy("ALLOW_VALKEY_FLUSH"),
        "valkey_password": os.environ.get("VALKEY_PASSWORD"),
        "allow_setup_upgrade": truthy("ALLOW_SETUP_UPGRADE"),
        "backup_target_dir": os.environ.get("BACKUP_TARGET_DIR"),
        "backup_keep_days": os.environ.get("BACKUP_KEEP_DAYS"),
        "mysql_database": os.environ.get("MYSQL_DATABASE"),
        "mysql_user": os.environ.get("MYSQL_USER"),
        "mysql_password": os.environ.get("MYSQL_PASSWORD"),
        "trigger_restic": truthy("TRIGGER_RESTIC"),
        "restic_site_override": os.environ.get("RESTIC_SITE_OVERRIDE"),
        "restic_repo_override": os.environ.get("RESTIC_REPO_OVERRIDE"),
        "static_languages": os.environ.get("STATIC_LANGS"),
        "static_jobs": os.environ.get("STATIC_JOBS"),
    }

    cleaned: Dict[str, Any] = {}
    for key, value in data.items():
        if value in (None, "", "None"):
            continue
        if isinstance(value, str) and value.lower() in {"true", "false"}:
            cleaned[key] = value.lower() == "true"
            continue
        if key in {"backup_keep_days", "static_jobs"}:
            try:
                cleaned[key] = int(value)
            except (ValueError, TypeError):
                continue
        else:
            cleaned[key] = value

    extra_paths = os.environ.get("RESTIC_EXTRA_PATHS", "")
    paths = [
        item.strip()
        for item in extra_paths.replace(";", ",").split(",")
        if item.strip()
    ]
    if paths:
        cleaned["restic_extra_paths"] = paths

    return cleaned


def main() -> int:
    payload = build_payload()
    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

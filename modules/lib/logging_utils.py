"""Logging path helpers for SaltGoat scripts."""
from __future__ import annotations

import os
from pathlib import Path

DEFAULT_ALERT_LOG = Path("/var/log/saltgoat/alerts.log")


def alerts_log_path() -> Path:
    """Return the alerts log path, honoring SALTGOAT_ALERT_LOG."""
    override = os.environ.get("SALTGOAT_ALERT_LOG")
    if override:
        return Path(override)
    return DEFAULT_ALERT_LOG


def ensure_alerts_log_dir() -> None:
    path = alerts_log_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass

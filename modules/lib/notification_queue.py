"""Helpers to inspect and replay notification failure queue records."""
from __future__ import annotations

import importlib
import json
import os
import sys
import time
from pathlib import Path
from typing import Dict, Tuple

from . import notification as notif
from . import logging_utils

LOGGER_SCRIPT = Path(os.environ.get("SALTGOAT_REACTOR_LOGGER", "/opt/saltgoat-reactor/logger.py"))
TELEGRAM_COMMON = Path(os.environ.get("SALTGOAT_REACTOR_COMMON", "/opt/saltgoat-reactor/reactor_common.py"))
ALERT_LOG = logging_utils.alerts_log_path()


def _load_reactor_common():
    if not TELEGRAM_COMMON.exists():
        raise RuntimeError("reactor_common missing")
    module_path = str(TELEGRAM_COMMON.parent)
    if module_path not in sys.path:
        sys.path.insert(0, module_path)
    return importlib.import_module("reactor_common")


def _noop_logger(*_args, **_kwargs) -> None:
    return None


def retry_record(record: Dict[str, object], *, dry_run: bool = False) -> Tuple[bool, str]:
    destination = record.get("destination")
    if destination == "webhook":
        return _retry_webhook(record, dry_run)
    if destination == "telegram":
        return _retry_telegram(record, dry_run)
    return False, f"unsupported destination {destination}"


def _retry_webhook(record: Dict[str, object], dry_run: bool) -> Tuple[bool, str]:
    context = record.get("context") or {}
    if not isinstance(context, dict):
        return False, "invalid context"
    url = context.get("url")
    if not url:
        return False, "missing url"
    body = record.get("payload")
    if not isinstance(body, dict):
        return False, "invalid payload"
    if dry_run:
        return True, "dry-run"
    entry = {"url": url, "headers": context.get("headers") or {}}
    ok = notif.send_webhook_entry(entry, body, queue_on_failure=False)
    return ok, "sent" if ok else "request failed"


def _retry_telegram(record: Dict[str, object], dry_run: bool) -> Tuple[bool, str]:
    payload = record.get("payload")
    if not isinstance(payload, dict):
        return False, "invalid payload"
    message = payload.get("message")
    if not message:
        return False, "missing message"
    tag = record.get("tag") or payload.get("tag")
    if not tag:
        return False, "missing tag"
    context = record.get("context") if isinstance(record.get("context"), dict) else {}
    parse_mode = context.get("parse_mode") or payload.get("parse_mode") or notif.get_parse_mode()
    thread_id = context.get("thread") or payload.get("telegram_thread") or notif.get_thread_id(tag)
    site_hint = payload.get("site")
    severity = str(payload.get("severity", "INFO")).upper()
    if not notif.should_send(tag, severity, site_hint):
        return False, "filtered"
    if dry_run:
        return True, "dry-run"
    try:
        reactor_common = _load_reactor_common()
    except Exception as exc:  # pragma: no cover - runtime environment issue
        return False, str(exc)
    profiles = reactor_common.load_telegram_profiles(None, _noop_logger)
    if not profiles:
        return False, "no_profiles"
    try:
        reactor_common.broadcast_telegram(
            message,
            profiles,
            _noop_logger,
            tag=tag,
            thread_id=thread_id,
            parse_mode=parse_mode,
        )
    except Exception as exc:  # pragma: no cover
        return False, str(exc)
    return True, "sent"


def update_record_metadata(record_path: Path, record: Dict[str, object], error: str) -> None:
    record["attempts"] = int(record.get("attempts", 0)) + 1
    record["last_error"] = error
    record["last_attempt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    record_path.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")

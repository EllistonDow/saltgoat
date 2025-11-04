from __future__ import annotations

import html
import json
import os
import re
import urllib.request
from functools import lru_cache
from pathlib import Path
from typing import Dict, List, Optional, Tuple

try:
    from salt.client import Caller  # type: ignore
except Exception:  # pragma: no cover - salt 环境不可用
    Caller = None  # type: ignore


_LEVELS = {
    "DEBUG": 0,
    "INFO": 1,
    "NOTICE": 2,
    "WARNING": 3,
    "ERROR": 4,
    "CRITICAL": 5,
}

_CALLER: Optional[Caller] = None
_CACHE: Optional[Dict[str, object]] = None
_TAG_RE = re.compile(r"<[^>]+>")
TELEGRAM_TOPICS_PATH = Path(__file__).resolve().parents[2] / "salt" / "pillar" / "telegram-topics.sls"


def _get_caller() -> Optional[Caller]:
    global _CALLER
    if Caller is None:
        return None
    if _CALLER is None:
        try:
            _CALLER = Caller()
        except Exception:
            return None
    return _CALLER


def pillar_get(path: str, default: object = None) -> object:
    caller = _get_caller()
    if caller is None:
        return default
    try:
        value = caller.cmd("pillar.get", path, default)
    except Exception:
        return default
    if value is None:
        return default
    return value


def level_value(name: str) -> int:
    return _LEVELS.get(str(name).upper(), _LEVELS["INFO"])


def _normalize_site(site: Optional[str]) -> Optional[str]:
    if not site:
        return None
    slug = site.strip().lower().replace(" ", "-").replace("/", "-")
    return slug or None


def load_config(reload: bool = False) -> Dict[str, object]:
    global _CACHE
    if _CACHE is not None and not reload:
        return _CACHE

    data = pillar_get("notifications", {})
    if not isinstance(data, dict):
        data = {}
    telegram = data.get("telegram", {}) if isinstance(data.get("telegram"), dict) else {}

    enabled = bool(telegram.get("enabled", True))
    min_level = str(telegram.get("min_severity", "INFO")).upper()
    parse_mode = telegram.get("parse_mode", "HTML")
    disabled_tags = telegram.get("disabled_tags", [])
    if isinstance(disabled_tags, (list, tuple, set)):
        disabled_tags = [str(tag) for tag in disabled_tags]
    else:
        disabled_tags = []

    site_overrides: Dict[str, Dict[str, object]] = {}
    overrides_raw = telegram.get("site_overrides", {})
    if isinstance(overrides_raw, dict):
        for site, rules in overrides_raw.items():
            if not isinstance(rules, dict):
                continue
            slug = _normalize_site(site)
            if not slug:
                continue
            override: Dict[str, object] = {
                "min_level": str(rules.get("min_severity", min_level)).upper(),
            }
            disabled = rules.get("disabled_tags", [])
            if isinstance(disabled, (list, tuple, set)):
                override["disabled_tags"] = [str(tag) for tag in disabled]
            site_overrides[slug] = override

    webhooks: List[Dict[str, object]] = []
    webhook_cfg = data.get("webhook", {})
    if isinstance(webhook_cfg, dict) and webhook_cfg.get("enabled", False):
        endpoints = webhook_cfg.get("endpoints", [])
        if isinstance(endpoints, list):
            for entry in endpoints:
                if not isinstance(entry, dict):
                    continue
                url = entry.get("url")
                if not url:
                    continue
                headers = entry.get("headers", {})
                if not isinstance(headers, dict):
                    headers = {}
                webhooks.append(
                    {
                        "name": entry.get("name") or url,
                        "url": url,
                        "headers": {str(k): str(v) for k, v in headers.items()},
                    }
                )

    _CACHE = {
        "enabled": enabled,
        "min_level": min_level,
        "min_level_value": level_value(min_level),
        "parse_mode": parse_mode,
        "disabled_tags": disabled_tags,
        "site_overrides": site_overrides,
        "webhooks": webhooks,
    }
    return _CACHE


def get_parse_mode() -> str:
    return str(load_config().get("parse_mode", "HTML"))


def _matches_disabled(tag: str, patterns: List[str]) -> bool:
    return any(tag.startswith(pattern) for pattern in patterns)


def should_send(tag: str, severity: str = "INFO", site: Optional[str] = None) -> bool:
    config = load_config()
    if not config.get("enabled", True):
        return False

    sev_value = level_value(severity)
    if sev_value < config.get("min_level_value", _LEVELS["INFO"]):
        return False

    disabled_global = config.get("disabled_tags", [])
    if isinstance(disabled_global, list) and _matches_disabled(tag, disabled_global):
        return False

    site_slug = _normalize_site(site)
    if site_slug is None:
        # attempt to infer from tag suffix
        parts = tag.split("/")
        if parts:
            site_slug = _normalize_site(parts[-1])

    overrides = config.get("site_overrides", {})
    if site_slug and site_slug in overrides:
        site_cfg = overrides[site_slug]
        min_level = site_cfg.get("min_level")
        if isinstance(min_level, str) and sev_value < level_value(min_level):
            return False
        disabled = site_cfg.get("disabled_tags", [])
        if isinstance(disabled, list) and _matches_disabled(tag, disabled):
            return False

    return True


def format_pre_block(title: str, subtitle: str, fields: List[Tuple[str, Optional[str]]]) -> Tuple[str, str]:
    entries: List[Tuple[str, str]] = []
    for label, value in fields:
        if value in (None, ""):
            continue
        entries.append((str(label), str(value)))
    underline = "=" * 30
    width = max((len(label) for label, _ in entries), default=8)
    lines = [underline, f"{title} ({subtitle})", underline]
    for label, value in entries:
        parts = value.splitlines() or [""]
        lines.append(f"{label.ljust(width)} : {parts[0]}")
        for extra in parts[1:]:
            lines.append(f"{' ' * width}   {extra}")
    plain = "\n".join(lines)
    return plain, f"<pre>{html.escape(plain)}</pre>"


def html_to_plain(content: str) -> str:
    if not content:
        return ""
    return html.unescape(_TAG_RE.sub("", content))


def dispatch_webhooks(
    tag: str,
    severity: str,
    site: Optional[str],
    plain_message: str,
    html_message: str,
    payload: Optional[Dict[str, object]] = None,
) -> int:
    config = load_config()
    endpoints = config.get("webhooks") or []
    if not endpoints:
        return 0
    body = {
        "tag": tag,
        "severity": severity,
        "site": site,
        "plain": plain_message,
        "html": html_message,
        "payload": payload or {},
    }
    data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    delivered = 0
    for entry in endpoints:
        try:
            req = urllib.request.Request(entry["url"], data=data, method="POST")
            headers = entry.get("headers") or {}
            if isinstance(headers, dict):
                for key, value in headers.items():
                    req.add_header(str(key), str(value))
            if "Content-Type" not in req.headers:
                req.add_header("Content-Type", "application/json; charset=utf-8")
            urllib.request.urlopen(req, timeout=10)  # nosec B310
            delivered += 1
        except Exception:
            continue
    return delivered


@lru_cache
def _load_topics_from_file() -> Dict[str, int]:
    if not TELEGRAM_TOPICS_PATH.exists():
        return {}
    try:
        import yaml  # type: ignore
    except Exception:
        yaml = None  # type: ignore

    try:
        raw = TELEGRAM_TOPICS_PATH.read_text(encoding="utf-8")
    except Exception:
        return {}

    if yaml is not None:
        try:
            data = yaml.safe_load(raw) or {}
        except Exception:
            return {}
    else:
        data = {}
        current_tag = None
        for line in raw.splitlines():
            stripped = line.strip()
            if stripped.startswith("saltgoat/"):
                parts = stripped.split(":")
                if len(parts) == 2:
                    data.setdefault("telegram_topics", {})[parts[0]] = int(parts[1])
        if not data:
            return {}

    topics = data.get("telegram_topics")
    if isinstance(topics, dict):
        normalized: Dict[str, int] = {}
        for key, value in topics.items():
            try:
                normalized[str(key)] = int(value)
            except Exception:
                continue
        return normalized
    return {}


def get_thread_id(tag: str) -> Optional[int]:
    topics = _load_topics_from_file()
    if not topics:
        return None
    if tag in topics:
        return topics[tag]
    parts = tag.split("/")
    while len(parts) > 1:
        parts = parts[:-1]
        candidate = "/".join(parts)
        if candidate in topics:
            return topics[candidate]
    return None

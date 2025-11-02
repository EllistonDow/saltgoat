from __future__ import annotations

import html
import os
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

    _CACHE = {
        "enabled": enabled,
        "min_level": min_level,
        "min_level_value": level_value(min_level),
        "parse_mode": parse_mode,
        "disabled_tags": disabled_tags,
        "site_overrides": site_overrides,
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

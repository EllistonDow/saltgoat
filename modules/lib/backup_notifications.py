"""Backup notification helper."""
from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from html import escape
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

from . import notification as notif


@dataclass(frozen=True)
class TelegramMessage:
    tag: str
    severity: str
    parse_mode: str
    log_path: Path
    html_message: str
    site_slug: str
    context: Dict[str, object]


def _sanitize(value: Optional[str], fallback: Optional[str]) -> str:
    raw = (value or fallback or "default").lower()
    return raw.replace(" ", "-").replace("/", "-") or "default"


def _format_entries(title: str, entries: List[Tuple[str, str]]) -> str:
    underline = "=" * 30
    width = max((len(key) for key, _ in entries), default=len(title))
    lines = [underline, title, underline]
    for key, value in entries:
        parts = value.splitlines() or [""]
        lines.append(f"{key.ljust(width)} : {parts[0]}")
        for extra in parts[1:]:
            lines.append(f"{' ' * width}   {extra}")
    return "\n".join(lines)


def build_message(
    *,
    title: str,
    status: str,
    tag_prefix: str,
    entries: Iterable[Tuple[str, str]],
    site: Optional[str],
    host: Optional[str],
    log_path: Optional[str],
    parse_mode: Optional[str],
    extra_context: Dict[str, object],
) -> TelegramMessage:
    site_slug = _sanitize(site, host)
    severity = "INFO" if status == "success" else "ERROR"

    list_entries = list(entries)
    if not any(key.lower() == "time" for key, _ in list_entries):
        timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        list_entries.append(("Time", timestamp))

    plain = _format_entries(title, list_entries)
    html_message = f"<pre>{escape(plain)}</pre>"

    context = {
        "severity": severity,
        "site": site_slug,
        "entries": list_entries,
    }
    context.update(extra_context)

    return TelegramMessage(
        tag=f"{tag_prefix}/{site_slug}",
        severity=severity,
        parse_mode=parse_mode or notif.get_parse_mode(),
        log_path=Path(log_path or "/var/log/saltgoat/alerts.log"),
        html_message=html_message,
        site_slug=site_slug,
        context=context,
    )


def should_send(tag: str, severity: str, site: Optional[str]) -> bool:
    return notif.should_send(tag, severity, site)


def emit(logger_script: Path, message: TelegramMessage) -> None:
    logger_script.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "python3",
            str(logger_script),
            "TELEGRAM",
            str(message.log_path),
            message.tag,
            json.dumps(message.context, ensure_ascii=False),
        ],
        check=False,
        timeout=5,
    )

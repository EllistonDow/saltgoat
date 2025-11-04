#!/usr/bin/env python3
"""Unified backup notification helper for SaltGoat."""
from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from modules.lib import notification as notif  # type: ignore

UNIT_TEST = os.environ.get("SALTGOAT_UNIT_TEST") == "1"
HOSTNAME = socket.getfqdn()
REACTOR_DIR = Path(os.environ.get("SALTGOAT_REACTOR_DIR", "/opt/saltgoat-reactor"))
LOGGER_SCRIPT = REACTOR_DIR / "logger.py"
TELEGRAM_COMMON = REACTOR_DIR / "reactor_common.py"
TELEGRAM_CONFIG = Path(
    os.environ.get("SALTGOAT_TELEGRAM_CONFIG", "/etc/saltgoat/telegram.json")
)
ALERT_LOG = Path(os.environ.get("SALTGOAT_ALERT_LOG", "/var/log/saltgoat/alerts.log"))


def _path_exists(path: Path) -> bool:
    try:
        path.stat()
        return True
    except (FileNotFoundError, PermissionError):
        return False


if not UNIT_TEST and _path_exists(TELEGRAM_COMMON):
    sys.path.insert(0, str(TELEGRAM_COMMON.parent))
    try:
        import reactor_common  # type: ignore
    except Exception:  # pragma: no cover
        reactor_common = None
else:  # pragma: no cover - unit tests do not load reactor
    reactor_common = None


def _slug(value: str | None, fallback: str | None) -> str:
    raw = (value or fallback or "default").lower()
    return raw.replace(" ", "-").replace("/", "-") or "default"


def _format_entries(title: str, subtitle: str, entries: Iterable[Tuple[str, str]]) -> Tuple[str, str]:
    return notif.format_pre_block(title, subtitle, list(entries))


def _log(label: str, payload: Dict[str, object]) -> None:
    if UNIT_TEST or not _path_exists(LOGGER_SCRIPT):
        return
    try:
        subprocess.run(
            [
                "python3",
                str(LOGGER_SCRIPT),
                "TELEGRAM",
                str(ALERT_LOG),
                label,
                json.dumps(payload, ensure_ascii=False),
            ],
            check=False,
            timeout=5,
        )
    except Exception:  # pragma: no cover
        pass


def _send(tag: str, plain: str, html: str, payload: Dict[str, object], site: str) -> None:
    severity = payload.get("severity", "INFO")
    if UNIT_TEST:
        print(json.dumps({"tag": tag, "payload": payload}, ensure_ascii=False))
        return
    if not notif.should_send(tag, severity, site):
        _log(f"{tag}/skip", {"reason": "filtered", "severity": severity})
        return
    thread_id = payload.get("telegram_thread") or notif.get_thread_id(tag)
    if thread_id is not None:
        payload["telegram_thread"] = thread_id

    notif.dispatch_webhooks(tag, str(severity), site, plain, html, payload)

    if reactor_common is None or not _path_exists(TELEGRAM_CONFIG):
        _log(f"{tag}/skip", {"reason": "reactor_unavailable"})
        return

    def logger(label: str, extra: Dict[str, object]) -> None:
        _log(f"{tag}/{label}", extra)

    try:
        profiles = reactor_common.load_telegram_profiles(
            str(TELEGRAM_CONFIG), logger
        )
    except Exception as exc:  # pragma: no cover
        logger("error", {"message": str(exc)})
        return

    if not profiles:
        logger("skip", {"reason": "no_profiles"})
        return

    try:
        reactor_common.broadcast_telegram(
            html,
            profiles,
            logger,
            tag=tag,
            thread_id=payload.get("telegram_thread"),
            parse_mode=notif.get_parse_mode(),
        )
    except Exception as exc:  # pragma: no cover
        logger("error", {"message": str(exc)})


def handle_mysql(args: argparse.Namespace) -> None:
    site_slug = _slug(args.site, args.database or args.host)
    entries: List[Tuple[str, str]] = [
        ("Host", args.host or HOSTNAME),
        ("Site", site_slug),
        ("Status", args.status.upper()),
        ("File", args.path or "n/a"),
        ("Return", str(args.return_code)),
    ]
    if args.size and args.size.lower() != "unknown":
        entries.append(("Size", args.size))
    if args.database:
        entries.append(("Database", args.database))
    if args.reason:
        entries.append(("Reason", args.reason))
    entries.append(("Time", datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")))

    plain, html = _format_entries("MYSQL DUMP BACKUP", site_slug.upper(), entries)
    payload = {
        "severity": "INFO" if args.status == "success" else "ERROR",
        "site": site_slug,
        "database": args.database,
        "size": args.size,
        "compressed": args.compressed,
    }
    tag = f"saltgoat/backup/mysql_dump/{site_slug}"
    _send(tag, plain, html, payload, site_slug)


def handle_restic(args: argparse.Namespace) -> None:
    site_slug = _slug(args.site, args.host)
    entries: List[Tuple[str, str]] = [
        ("Host", args.host or HOSTNAME),
        ("Site", site_slug),
        ("Status", args.status.upper()),
        ("Repo", args.repo or "n/a"),
        ("Return", str(args.return_code)),
    ]
    if args.log_file:
        entries.append(("Log", args.log_file))
    if args.paths:
        entries.append(("Paths", args.paths))
    if args.tags:
        entries.append(("Tags", args.tags))
    entries.append(("Origin", args.origin))
    entries.append(("Time", datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")))

    plain, html = _format_entries("RESTIC BACKUP", site_slug.upper(), entries)
    payload = {
        "severity": "INFO" if args.status == "success" else "ERROR",
        "site": site_slug,
        "repo": args.repo,
        "paths": args.paths,
        "tags": args.tags,
        "origin": args.origin,
    }
    tag = f"saltgoat/backup/restic/{site_slug}"
    _send(tag, plain, html, payload, site_slug)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="SaltGoat backup notification helper")
    sub = parser.add_subparsers(dest="command", required=True)

    mysql = sub.add_parser("mysql", help="Notify MySQL dump result")
    mysql.add_argument("--status", required=True, choices=["success", "failure"])
    mysql.add_argument("--database", default="")
    mysql.add_argument("--path", default="")
    mysql.add_argument("--size", default="unknown")
    mysql.add_argument("--reason", default="")
    mysql.add_argument("--return-code", type=int, default=0)
    mysql.add_argument("--compressed", default="1")
    mysql.add_argument("--site", default="")
    mysql.add_argument("--host", default="")
    mysql.set_defaults(func=handle_mysql)

    restic = sub.add_parser("restic", help="Notify Restic backup result")
    restic.add_argument("--status", required=True, choices=["success", "failure"])
    restic.add_argument("--repo", default="")
    restic.add_argument("--site", default="")
    restic.add_argument("--log-file", default="")
    restic.add_argument("--paths", default="")
    restic.add_argument("--tags", default="")
    restic.add_argument("--return-code", type=int, default=0)
    restic.add_argument("--origin", default="manual")
    restic.add_argument("--host", default="")
    restic.set_defaults(func=handle_restic)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

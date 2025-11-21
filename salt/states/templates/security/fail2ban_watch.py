#!/usr/bin/env python3
"""
Fail2ban watcher with Telegram notifications.

Scans all configured jails, prints a summary table, and notifies when new IPs are banned.
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Sequence

BASE_DIR = Path(__file__).resolve().parent
LIB_CANDIDATES = [
    BASE_DIR / "lib",
    BASE_DIR.parent / "modules",
    Path("/srv/saltgoat/modules"),
    Path("/home/doge/saltgoat/modules"),
    Path("/opt/saltgoat/modules"),
]
for candidate in LIB_CANDIDATES:
    try:
        if candidate.exists() and str(candidate) not in sys.path:
            sys.path.insert(0, str(candidate))
    except PermissionError:
        continue

from lib import notification as notif  # type: ignore

HOSTNAME = socket.getfqdn()
STATE_FILE = Path("/var/log/saltgoat/fail2ban-state.json")
LOGGER_SCRIPT = Path("/opt/saltgoat-reactor/logger.py")
TELEGRAM_COMMON = Path("/opt/saltgoat-reactor/reactor_common.py")
ALERT_LOG = Path(os.environ.get("SALTGOAT_ALERT_LOG", "/var/log/saltgoat/alerts.log"))


def path_exists(path: Path) -> bool:
    try:
        path.stat()
        return True
    except (FileNotFoundError, PermissionError):
        return False


TELEGRAM_AVAILABLE = path_exists(LOGGER_SCRIPT) and path_exists(TELEGRAM_COMMON)

if TELEGRAM_AVAILABLE:
    sys.path.insert(0, str(TELEGRAM_COMMON.parent))
    try:
        import reactor_common  # type: ignore
    except Exception:  # pragma: no cover
        TELEGRAM_AVAILABLE = False


def run_client(args: Sequence[str]) -> str:
    cmd = ["fail2ban-client", *args]
    try:
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode().strip()
    except subprocess.CalledProcessError:
        return ""


def parse_jails(status_output: str) -> List[str]:
    for line in status_output.splitlines():
        if "Jail list:" in line:
            _, _, rest = line.partition("Jail list:")
            items = [item.strip() for item in rest.replace(",", " ").split()]
            return [item for item in items if item]
    return []


def parse_jail_status(jail: str) -> Dict[str, object]:
    output = run_client(["status", jail])
    currently = 0
    total = 0
    ips: List[str] = []
    for line in output.splitlines():
        clean = line.strip()
        if "Currently banned" in clean:
            try:
                currently = int(clean.split(":")[-1].strip())
            except ValueError:
                pass
        elif "Total banned" in clean:
            try:
                total = int(clean.split(":")[-1].strip())
            except ValueError:
                pass
        elif clean.endswith("IP list:") or clean.endswith("Banned IP list:"):
            continue
        elif clean.startswith("- IP list:") or clean.startswith("`- IP list:"):
            values = clean.split(":", 1)[-1]
            ips = [ip.strip() for ip in values.replace(",", " ").split() if ip.strip()]
        elif clean.startswith(("|  `- IP list:", "`- Banned IP list:")):
            values = clean.split(":", 1)[-1]
            ips = [ip.strip() for ip in values.replace(",", " ").split() if ip.strip()]
    return {"currently": currently, "total": total, "ips": ips}


def load_state(path: Path) -> Dict[str, List[str]]:
    if not path_exists(path):
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def save_state(path: Path, data: Dict[str, List[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True), encoding="utf-8")


def log_to_file(tag: str, payload: Dict[str, object]) -> None:
    if not path_exists(LOGGER_SCRIPT):
        return
    try:
        subprocess.run(
            [
                sys.executable,
                str(LOGGER_SCRIPT),
                "TELEGRAM",
                str(ALERT_LOG),
                tag,
                json.dumps(payload, ensure_ascii=False),
            ],
            check=False,
            timeout=5,
        )
    except Exception:
        pass


def send_telegram(tag: str, message: str, payload: Dict[str, object]) -> None:
    severity = payload.get("severity", "WARNING")
    site_hint = payload.get("site")
    if not notif.should_send(tag, severity, site_hint):
        log_to_file(f"{tag}/skip", {"reason": "filtered", **payload})
        return
    if not TELEGRAM_AVAILABLE:
        log_to_file(f"{tag}/skip", {"reason": "telegram_unavailable"})
        return
    parse_mode = notif.get_parse_mode()
    thread_id = payload.get("telegram_thread") or notif.get_thread_id(tag)
    if thread_id is not None:
        payload["telegram_thread"] = thread_id

    def _log(label: str, extra: Dict[str, object]) -> None:
        log_to_file(f"{tag}/{label}", extra)

    try:
        profiles = reactor_common.load_telegram_profiles(None, _log)
    except Exception as exc:
        _log("error", {"message": str(exc)})
        notif.queue_failure(
            "telegram",
            tag,
            payload,
            str(exc),
            {"thread": payload.get("telegram_thread"), "parse_mode": parse_mode},
        )
        return
    if not profiles:
        _log("skip", {"reason": "no_profiles"})
        notif.queue_failure(
            "telegram",
            tag,
            payload,
            "no_profiles",
            {"thread": payload.get("telegram_thread"), "parse_mode": parse_mode},
        )
        return
    try:
        reactor_common.broadcast_telegram(
            message,
            profiles,
            _log,
            tag=tag,
            thread_id=thread_id,
            parse_mode=parse_mode,
        )
    except Exception as exc:
        _log("error", {"message": str(exc)})
        notif.queue_failure(
            "telegram",
            tag,
            payload,
            str(exc),
            {"thread": payload.get("telegram_thread"), "parse_mode": parse_mode},
        )


def notify_new_ban(jail: str, ip: str, stats: Dict[str, object]) -> None:
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    fields = [
        ("Host", HOSTNAME),
        ("Jail", jail),
        ("IP", ip),
        ("Currently", str(stats.get("currently", 0))),
        ("Total", str(stats.get("total", 0))),
        ("Time", timestamp),
    ]
    _, html = notif.format_pre_block("FAIL2BAN", jail.upper(), fields)
    payload = {
        "severity": "WARNING",
        "site": jail,
        "message": html,
    }
    tag = f"saltgoat/security/fail2ban/{jail}"
    send_telegram(tag, html, payload)


def main() -> None:
    parser = argparse.ArgumentParser(description="Fail2ban watcher")
    parser.add_argument("--state", default=str(STATE_FILE), help="State file path")
    args = parser.parse_args()
    status = run_client(["status"])
    if not status:
        print("fail2ban-client not available", file=sys.stderr)
        sys.exit(1)

    jails = parse_jails(status)
    if not jails:
        print("No jails configured")
        sys.exit(0)

    prev_state = load_state(Path(args.state))
    next_state: Dict[str, List[str]] = {}

    print(f"{'Jail':<16} {'Current':<8} {'Total':<8} Banned IPs")
    print("=" * 60)
    for jail in jails:
        stats = parse_jail_status(jail)
        ips = stats.get("ips", [])
        current = stats.get("currently", 0)
        total = stats.get("total", 0)
        ip_list = ", ".join(ips) if ips else "-"
        print(f"{jail:<16} {current:<8} {total:<8} {ip_list}")

        old_ips = set(prev_state.get(jail, []))
        new_ips = [ip for ip in ips if ip not in old_ips]
        for ip in new_ips:
            notify_new_ban(jail, ip, stats)
        next_state[jail] = list(ips)

    save_state(Path(args.state), next_state)


if __name__ == "__main__":
    main()

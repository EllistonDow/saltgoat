#!/usr/bin/env python3
"""
SaltGoat daily summary reporter.

Generates a concise system summary, writes it to /var/log/saltgoat/monitor/, and pushes Telegram + Salt events.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import shutil
import socket
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

try:
    from salt.client import Caller  # type: ignore
except Exception:  # pragma: no cover
    Caller = None  # type: ignore

HOSTNAME = socket.getfqdn()
MONITOR_DIR = Path("/var/log/saltgoat/monitor")
ALERT_LOG = Path("/var/log/saltgoat/alerts.log")
LOGGER_SCRIPT = Path("/opt/saltgoat-reactor/logger.py")
TELEGRAM_COMMON = Path("/opt/saltgoat-reactor/reactor_common.py")
TELEGRAM_CONFIG = Path("/etc/saltgoat/telegram.json")
REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
from modules.lib import notification as notif  # type: ignore


def path_exists(path: Path) -> bool:
    try:
        path.stat()
        return True
    except (PermissionError, FileNotFoundError):
        return False


TELEGRAM_AVAILABLE = (
    path_exists(LOGGER_SCRIPT)
    and path_exists(TELEGRAM_COMMON)
    and path_exists(TELEGRAM_CONFIG)
)

if TELEGRAM_AVAILABLE:
    sys.path.insert(0, str(TELEGRAM_COMMON.parent))
    try:
        import reactor_common  # type: ignore
    except Exception:  # pragma: no cover
        TELEGRAM_AVAILABLE = False


def run_cmd(cmd: List[str]) -> str:
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        return out.decode().strip()
    except subprocess.CalledProcessError:
        return ""


def safe_float(value: str) -> Optional[float]:
    try:
        return float(value)
    except ValueError:
        return None


def loadavg() -> Tuple[float, float, float]:
    try:
        return os.getloadavg()
    except OSError:
        return (0.0, 0.0, 0.0)


def memory_usage() -> Tuple[float, str]:
    info: Dict[str, int] = {}
    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as fh:
            for line in fh:
                if ":" not in line:
                    continue
                k, v = line.split(":", 1)
                value = v.strip().split()[0]
                info[k] = int(value)
    except FileNotFoundError:
        return (0.0, "")

    total = info.get("MemTotal", 0)
    available = info.get("MemAvailable")
    if available is None:
        available = info.get("MemFree", 0) + info.get("Buffers", 0) + info.get("Cached", 0)
    used = total - available
    percent = (used / total * 100.0) if total else 0.0
    summary = f"{used/1024/1024:.1f}G / {total/1024/1024:.1f}G"
    return percent, summary


def disk_summary(paths: Iterable[Path]) -> Dict[str, Tuple[float, str]]:
    result: Dict[str, Tuple[float, str]] = {}
    for path in paths:
        try:
            usage = shutil.disk_usage(path)
        except FileNotFoundError:
            continue
        percent = usage.used / usage.total * 100.0
        summary = f"{usage.used/1024/1024/1024:.1f}G/{usage.total/1024/1024/1024:.1f}G"
        result[str(path)] = (percent, summary)
    return result


def service_status(services: Iterable[str]) -> Dict[str, bool]:
    status: Dict[str, bool] = {}
    for svc in services:
        ok = subprocess.call(
            ["systemctl", "is-active", "--quiet", svc],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ) == 0
        status[svc] = ok
    return status


def tail_last_backup(kind: str) -> Optional[str]:
    if not path_exists(ALERT_LOG):
        return None
    tag = f"saltgoat/backup/{kind}/success"
    try:
        with open(ALERT_LOG, "r", encoding="utf-8", errors="ignore") as fh:
            lines = fh.readlines()
        needle = f"[BACKUP] tag={tag}"
        for line in reversed(lines):
            if needle in line:
                return line.strip()
    except Exception:
        return None
    return None


def log_to_file(label: str, tag: str, payload: Dict[str, Any]) -> None:
    if not path_exists(LOGGER_SCRIPT):
        return
    try:
        subprocess.run(
            [
                sys.executable,
                str(LOGGER_SCRIPT),
                label,
                str(ALERT_LOG),
                tag,
                json.dumps(payload, ensure_ascii=False),
            ],
            check=False,
            timeout=5,
        )
    except Exception:
        pass


def telegram_notify(tag: str, message: str, payload: Dict[str, Any], plain_message: Optional[str] = None) -> None:
    plain_block = plain_message or message
    notif.dispatch_webhooks(tag, str(payload.get("severity", "INFO")), payload.get("site"), plain_block, message, payload)
    if not TELEGRAM_AVAILABLE:
        return

    def _log(kind: str, extra: Dict[str, Any]) -> None:
        log_to_file("TELEGRAM", f"{tag} {kind}", extra)

    profiles = reactor_common.load_telegram_profiles(str(TELEGRAM_CONFIG), _log)
    if not profiles:
        _log("skip", {"reason": "no_profiles"})
        return
    _log("profile_summary", {"count": len(profiles)})
    reactor_common.broadcast_telegram(message, profiles, _log, tag=tag)


def emit_event(tag: str, payload: Dict[str, Any]) -> None:
    if Caller is None:
        return
    try:
        caller = Caller()  # type: ignore[call-arg]
        caller.cmd("event.send", tag, payload)
    except Exception:
        pass


def compile_summary() -> Tuple[str, Dict[str, Any]]:
    cpu_cores = os.cpu_count() or 1
    load1, load5, load15 = loadavg()
    mem_percent, mem_summary = memory_usage()
    disks = disk_summary([Path("/"), Path("/var/lib/mysql"), Path("/home")])
    services = service_status(["nginx", "php8.3-fpm", "mysql", "valkey", "rabbitmq", "salt-minion"])

    restic_last = tail_last_backup("restic")
    dump_last = tail_last_backup("mysql_dump")

    lines = [
        f"[SaltGoat] Daily Summary - {HOSTNAME}",
        f"Date: {dt.datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}",
        f"Load avg: {load1:.2f} {load5:.2f} {load15:.2f} (cores={cpu_cores})",
        f"Memory: {mem_percent:.1f}% used ({mem_summary})",
    ]

    if disks:
        lines.append("Disks:")
        for mount, (percent, summary) in disks.items():
            lines.append(f"  - {mount}: {percent:.1f}% ({summary})")

    failing = [svc for svc, ok in services.items() if not ok]
    if failing:
        lines.append("Services: ⚠️ " + ", ".join(failing) + " down")
    else:
        lines.append("Services: all running")

    if restic_last:
        lines.append(f"Restic: {restic_last}")
    if dump_last:
        lines.append(f"MySQL dump: {dump_last}")

    payload = {
        "host": HOSTNAME,
        "load": {"1m": load1, "5m": load5, "15m": load15},
        "cpu_cores": cpu_cores,
        "memory": {"percent": mem_percent, "summary": mem_summary},
        "disks": disks,
        "services": services,
        "restic_reference": restic_last,
        "mysqldump_reference": dump_last,
    }
    return "\n".join(lines), payload


def ensure_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def write_report(text: str, filename: Optional[str]) -> Optional[Path]:
    if not filename:
        return None
    ensure_directory(MONITOR_DIR)
    target = MONITOR_DIR / filename
    target.write_text(text, encoding="utf-8")
    return target


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="SaltGoat daily summary")
    parser.add_argument(
        "--outfile",
        help="写入报告文件名（默认 daily-YYYYMMDD.txt）",
        default=f"daily-{dt.datetime.utcnow().strftime('%Y%m%d')}.txt",
    )
    parser.add_argument(
        "--no-telegram",
        action="store_true",
        help="仅生成报告，不发送 Telegram",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="不在控制台打印总结",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    summary_text, payload = compile_summary()
    write_report(summary_text, args.outfile)
    tag = "saltgoat/monitor/daily"
    payload_with_tag = payload | {"tag": tag}
    log_to_file("REPORT", tag, payload_with_tag)
    emit_event(tag, payload)
    if not args.no_telegram:
        payload_with_tag.setdefault("severity", "INFO")
        thread_id = payload_with_tag.get("telegram_thread") or notif.get_thread_id(tag)
        if thread_id is not None:
            payload_with_tag["telegram_thread"] = thread_id
        telegram_notify(tag, summary_text, payload_with_tag, summary_text)
    if not args.quiet:
        print(summary_text)


if __name__ == "__main__":
    main()

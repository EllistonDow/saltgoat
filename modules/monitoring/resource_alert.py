#!/usr/bin/env python3
"""
SaltGoat resource alert helper.

Evaluates load/memory/disk/service health and pushes Telegram + Salt events when thresholds are exceeded.
"""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import sys
from argparse import ArgumentParser
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

try:
    from salt.client import Caller  # type: ignore
except Exception:  # pragma: no cover - salt 不存在时回退纯本地模式
    Caller = None  # type: ignore

HOSTNAME = socket.getfqdn()
ALERT_LOG = Path("/var/log/saltgoat/alerts.log")
LOGGER_SCRIPT = Path("/opt/saltgoat-reactor/logger.py")
TELEGRAM_COMMON = Path("/opt/saltgoat-reactor/reactor_common.py")
TELEGRAM_CONFIG = Path("/etc/saltgoat/telegram.json")


def shell_exists(path: Path) -> bool:
    try:
        path.stat()
        return True
    except PermissionError:
        return False
    except FileNotFoundError:
        return False


TELEGRAM_AVAILABLE = (
    shell_exists(LOGGER_SCRIPT)
    and shell_exists(TELEGRAM_COMMON)
    and shell_exists(TELEGRAM_CONFIG)
)

if TELEGRAM_AVAILABLE:
    sys.path.insert(0, str(TELEGRAM_COMMON.parent))
    try:
        import reactor_common  # type: ignore
    except Exception:  # pragma: no cover
        TELEGRAM_AVAILABLE = False


def run_cmd(args: List[str]) -> str:
    try:
        out = subprocess.check_output(args, stderr=subprocess.DEVNULL)
        return out.decode().strip()
    except subprocess.CalledProcessError:
        return ""


def get_load() -> Tuple[float, float, float]:
    try:
        return os.getloadavg()
    except OSError:
        return (0.0, 0.0, 0.0)


def read_meminfo() -> Dict[str, int]:
    result: Dict[str, int] = {}
    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as fh:
            for line in fh:
                if ":" not in line:
                    continue
                key, value = line.split(":", 1)
                value = value.strip().split()[0]
                try:
                    result[key] = int(value)
                except ValueError:
                    continue
    except FileNotFoundError:
        pass
    return result


def memory_usage_percent() -> float:
    info = read_meminfo()
    mem_total = info.get("MemTotal")
    if not mem_total:
        return 0.0
    mem_available = info.get("MemAvailable")
    if mem_available is None:
        mem_free = info.get("MemFree", 0)
        buffers = info.get("Buffers", 0)
        cached = info.get("Cached", 0)
        mem_available = mem_free + buffers + cached
    used = mem_total - mem_available
    return (used / mem_total) * 100.0


def disk_usage(paths: Iterable[Path]) -> Dict[str, float]:
    stats: Dict[str, float] = {}
    for path in paths:
        try:
            usage = shutil.disk_usage(path)
            percent = usage.used / usage.total * 100.0
            stats[str(path)] = percent
        except FileNotFoundError:
            continue
    return stats


def service_status(services: Iterable[str]) -> Dict[str, bool]:
    result: Dict[str, bool] = {}
    for svc in services:
        ok = subprocess.call(
            ["systemctl", "is-active", "--quiet", svc],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ) == 0
        result[svc] = ok
    return result


def hostname() -> str:
    return HOSTNAME or run_cmd(["hostname"]) or "localhost"


def load_thresholds(cpu_count: int) -> Dict[str, float]:
    # baseline: warning at 1.25x cores, critical at 1.5x
    return {
        "warn_1m": cpu_count * 1.25,
        "crit_1m": cpu_count * 1.5,
        "warn_5m": cpu_count * 1.1,
        "crit_5m": cpu_count * 1.4,
        "warn_15m": cpu_count * 1.0,
        "crit_15m": cpu_count * 1.3,
    }


def log_to_file(label: str, tag: str, payload: Dict[str, Any]) -> None:
    if not shell_exists(LOGGER_SCRIPT):
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


def telegram_notify(tag: str, message: str, payload: Dict[str, Any]) -> None:
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


def emit_salt_event(tag: str, payload: Dict[str, Any]) -> None:
    if Caller is None:
        return
    try:
        caller = Caller()  # type: ignore[call-arg]
        caller.cmd("event.send", tag, payload)
    except Exception:
        pass


def color_severity(level: str) -> str:
    return level


def evaluate() -> Tuple[str, List[str], Dict[str, Any]]:
    cpu_count = os.cpu_count() or 1
    load1, load5, load15 = get_load()
    thresholds = load_thresholds(cpu_count)

    severity = "INFO"
    details: List[str] = []

    def bump(level: str) -> None:
        nonlocal severity
        order = {"INFO": 0, "NOTICE": 1, "WARNING": 2, "CRITICAL": 3}
        if order[level] > order[severity]:
            severity = level

    # Load check
    load_line = f"Load average: 1m={load1:.2f} 5m={load5:.2f} 15m={load15:.2f} (cores={cpu_count})"
    details.append(load_line)
    if load1 >= thresholds["crit_1m"] or load5 >= thresholds["crit_5m"] or load15 >= thresholds["crit_15m"]:
        bump("CRITICAL")
    elif load1 >= thresholds["warn_1m"] or load5 >= thresholds["warn_5m"] or load15 >= thresholds["warn_15m"]:
        bump("WARNING")

    # Memory
    mem_percent = memory_usage_percent()
    details.append(f"Memory used: {mem_percent:.1f}%")
    if mem_percent >= 92:
        bump("CRITICAL")
    elif mem_percent >= 85:
        bump("WARNING")
    elif mem_percent >= 78:
        bump("NOTICE")

    # Disk
    disks = disk_usage([Path("/"), Path("/var/lib/mysql"), Path("/home")])
    for mount, percent in disks.items():
        details.append(f"Disk {mount}: {percent:.1f}% used")
        if percent >= 95:
            bump("CRITICAL")
        elif percent >= 90:
            bump("WARNING")
        elif percent >= 80:
            bump("NOTICE")

    # Services
    services = service_status(["nginx", "php8.3-fpm", "mysql", "valkey", "rabbitmq", "salt-minion"])
    failing = [svc for svc, ok in services.items() if not ok]
    if failing:
        bump("CRITICAL")
        details.append("Services down: " + ", ".join(failing))
    else:
        details.append("All critical services running.")

    payload = {
        "host": hostname(),
        "severity": severity,
        "load": {"1m": load1, "5m": load5, "15m": load15},
        "memory": mem_percent,
        "disks": disks,
        "services": services,
    }
    return severity, details, payload


def parse_args():
    parser = ArgumentParser(description="SaltGoat resource alert")
    parser.add_argument(
        "--force-severity",
        choices=["INFO", "NOTICE", "WARNING", "CRITICAL"],
        help="测试用途：强制使用指定告警级别",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    severity, details, payload = evaluate()
    if args.force_severity:
        severity = args.force_severity

    if severity in {"WARNING", "CRITICAL"}:
        lines = [
            f"[SaltGoat] {severity} resource alert",
            f"Host: {payload['host']}",
        ]
        lines.extend(details)
        message = "\n".join(lines)
        tag = f"saltgoat/monitor/resources/{severity.lower()}"
        augmented = payload | {"details": details, "tag": tag}
        log_to_file("RESOURCE", tag, augmented)
        telegram_notify("saltgoat/monitor/resources", message, augmented)
        emit_salt_event(tag, payload)
        print(message)
    else:
        print("Resources within normal range; no alert issued.")


if __name__ == "__main__":
    main()

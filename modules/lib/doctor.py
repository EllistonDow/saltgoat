#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

REPO_ROOT = Path(__file__).resolve().parents[2]
UNIT_TEST = os.environ.get("SALTGOAT_UNIT_TEST") == "1"


def run(cmd: list[str]) -> str:
    if UNIT_TEST:
        return "[stub] " + " ".join(cmd)
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return proc.stdout.strip()


def gather() -> dict:
    data = {}
    dt = datetime.utcnow()
    data["timestamp"] = dt.strftime("%Y-%m-%d %H:%M:%S UTC")
    data["host"] = socket.getfqdn()
    if UNIT_TEST:
        data["goat_pulse"] = "[stub] goat pulse snapshot"
    else:
        try:
            data["goat_pulse"] = run(["python3", str(REPO_ROOT / "scripts" / "goat_pulse.py"), "--once", "--plain"]).strip()
        except Exception as exc:
            data["goat_pulse"] = f"[ERROR] Goat Pulse failed: {exc}"
    data["disk"] = run(["df", "-h", "/", "/var/lib/mysql"])
    data["ps"] = run(["bash", "-c", "ps -eo pid,comm,%mem,%cpu --sort=-%mem | head -n 6"])
    alerts = Path("/var/log/saltgoat/alerts.log")
    try:
        data["alerts"] = alerts.read_text()[-2000:] if alerts.exists() else ""
    except PermissionError:
        data["alerts"] = "[Permission denied]"
    return data


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="SaltGoat doctor helper")
    parser.add_argument("--format", choices=["text", "json", "markdown"], default="text")
    parser.add_argument("--json", action="store_true", help="(deprecated) same as --format json")
    args = parser.parse_args(list(argv) if argv is not None else None)

    data = gather()
    fmt = "json" if args.json else args.format
    if fmt == "json":
        print(json.dumps(data, ensure_ascii=False, indent=2))
    elif fmt == "markdown":
        print(f"# SaltGoat Doctor Snapshot\n\n- **Host**: {data['host']}\n- **Timestamp**: {data['timestamp']}\n\n## Goat Pulse\n```\n{data['goat_pulse']}\n```\n\n## Disk Usage\n```\n{data['disk']}\n```\n\n## Top Memory Processes\n```\n{data['ps']}\n```\n\n## Recent Alerts\n```\n{(data['alerts'] or 'No alerts.')}\n```\n")
    else:
        print(f"SaltGoat Doctor Snapshot @ {data['timestamp']} (Host: {data['host']})")
        print(data["goat_pulse"])
        print("\nDisk Usage:\n" + data["disk"])
        print("\nTop Memory Processes:\n" + data["ps"])
        print("\nRecent Alerts:\n" + (data["alerts"] or "No alerts."))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

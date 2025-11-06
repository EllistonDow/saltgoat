#!/usr/bin/env python3
"""Generate a human-readable report from Uptime Kuma SQLite DB."""

import argparse
import sqlite3
from datetime import datetime, timedelta


def main() -> int:
    parser = argparse.ArgumentParser(description="Inspect Uptime Kuma monitor history")
    parser.add_argument("db", help="Path to kuma.db, e.g. /opt/saltgoat/docker/uptime-kuma/data/kuma.db")
    parser.add_argument("monitor", type=int, help="Monitor ID")
    parser.add_argument("--hours", type=int, default=7, help="Lookback window")
    args = parser.parse_args()

    conn = sqlite3.connect(args.db)
    cur = conn.cursor()
    since = datetime.utcnow() - timedelta(hours=args.hours)
    rows = cur.execute(
        "SELECT time, status, msg FROM heartbeat WHERE monitor_id=? AND time>=? ORDER BY time",
        (args.monitor, since.isoformat()),
    ).fetchall()

    if not rows:
        print("No data in window")
        return 0

    print(f"Heartbeat entries for monitor {args.monitor} since {since} UTC:")
    for t, status, msg in rows:
        label = "UP" if status == 1 else "DOWN"
        print(f"{t} | {label:<4} | {msg}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
